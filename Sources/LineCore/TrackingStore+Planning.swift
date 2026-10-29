import Foundation

extension TrackingStore {
    /// The editor uses the same task, color, and delete controls for plans and records.
    public func editableEntry(id: UUID) -> TimeEntry? {
        entries.first { $0.id == id } ?? plans.first { $0.id == id }.map {
            TimeEntry(id: $0.id, taskID: $0.taskID, start: $0.start, end: $0.end)
        }
    }

    /// Plans only fill unrecorded portions of the timeline, never cover actual work.
    public func plannedSegments(in range: DateInterval, at instant: Date) -> [PlannedSegment] {
        plans.flatMap { plan -> [PlannedSegment] in
            guard plan.start < range.end, plan.end > range.start else { return [] }
            var gaps = [DateInterval(start: max(plan.start, range.start), end: min(plan.end, range.end))]
            for entry in entries(overlapping: range, now: instant) {
                let end = entry.end ?? instant
                gaps = gaps.flatMap { gap -> [DateInterval] in
                    guard entry.start < gap.end, end > gap.start else { return [gap] }
                    var rest: [DateInterval] = []
                    if gap.start < entry.start { rest.append(DateInterval(start: gap.start, end: entry.start)) }
                    if end < gap.end { rest.append(DateInterval(start: end, end: gap.end)) }
                    return rest
                }
            }
            return gaps.flatMap { gap -> [PlannedSegment] in
                let label = plan.state == .skipped ? "Skipped" : plan.state == .missed || plan.state == .completed ? "Missed" : "Planned"
                if label == "Planned", gap.start < instant {
                    var result = [PlannedSegment(plan: plan, interval: DateInterval(start: gap.start, end: min(gap.end, instant)), label: "Missed")]
                    if gap.end > instant {
                        result.append(PlannedSegment(plan: plan, interval: DateInterval(start: instant, end: gap.end), label: label))
                    }
                    return result
                }
                return [PlannedSegment(plan: plan, interval: gap, label: label)]
            }
        }
    }

    private func occupiedIntervals(at instant: Date, excluding id: UUID? = nil) -> [DateInterval] {
        let recorded = entries.filter { $0.id != id }.map { DateInterval(start: $0.start, end: max($0.start, $0.end ?? instant)) }
        let scheduled = plans.filter { $0.id != id && $0.state.isAutomatic }.map { DateInterval(start: $0.start, end: $0.end) }
        return (recorded + scheduled).sorted { $0.start < $1.start }
    }

    func preparePlan(from first: Date, to second: Date, start: Date, end: Date,
                     overwriting: Bool, at instant: Date) throws -> EntrySelection {
        var start = start
        var end = end
        if !overwriting {
            let occupied = occupiedIntervals(at: instant)
            guard !occupied.contains(where: { $0.start <= first && $0.end > first }) else { throw TrackingError.overlappingEntry }
            let lower = occupied.filter { $0.end <= first }.map(\.end).max() ?? .distantPast
            let upper = occupied.first { $0.start > first }?.start ?? .distantFuture
            start = max(lower, min(upper, min(first, second) <= lower ? lower : start))
            end = min(upper, max(lower, max(first, second) >= upper ? upper : end))
        }
        let startsInFuture = min(first, second) >= instant
        if startsInFuture { start = max(start, instant) }
        let selection = EntrySelection(start: start, end: end, overwritesExisting: overwriting, startsInFuture: startsInFuture)
        try validate(selection, at: instant)
        return selection
    }

    func validatePlan(_ selection: EntrySelection, at instant: Date, excluding id: UUID? = nil, checkingRecordedTime: Bool = true) throws {
        guard let end = selection.end, end > selection.start,
              selection.start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite else { throw TrackingError.emptyInterval }
        guard !selection.overwritesExisting else { return }
        // An active plan's actual entry is allowed inside its own intended interval.
        let ownPlan = plans.first { $0.id == id || (id != nil && $0.runningEntryID == id) }
        let ownEntry = ownPlan?.runningEntryID
        let overlapsRecord = entries.contains {
            $0.id != ownEntry && $0.id != id &&
                (($0.end == nil && selection.start < instant) || ($0.start < min(end, instant) && ($0.end ?? instant) > selection.start))
        }
        let overlapsPlan = plans.contains {
            $0.id != id && $0.id != ownPlan?.id && $0.state.isAutomatic && $0.start < end && $0.end > selection.start
        }
        guard (!checkingRecordedTime || !overlapsRecord) && !overlapsPlan else { throw TrackingError.overlappingEntry }
    }

    func createPlan(input: TaskInput, selection: EntrySelection, at instant: Date) throws {
        var candidate = snapshot
        if selection.overwritesExisting { trimPlans(selection, in: &candidate) }
        let task = resolveTask(input, in: &candidate)
        var plan = PlannedEntry(id: UUID(), taskID: task.id, start: selection.start, end: selection.end!, state: selection.end! <= instant ? .missed : .scheduled)
        if selection.start < instant && !selection.startsInFuture {
            if selection.overwritesExisting { removeOverlaps(with: EntrySelection(start: selection.start, end: nil, overwritesExisting: true), from: &candidate, at: instant) }
            let entry = TimeEntry(id: UUID(), taskID: task.id, start: selection.start, end: nil)
            candidate.entries.append(entry)
            candidate.entries.sort { $0.start < $1.start }
            candidate.checkpoint = instant
            plan.state = .active
            plan.runningEntryID = entry.id
        }
        candidate.plans = (candidate.plans ?? []) + [plan]
        try commit(candidate)
    }

    func scheduleResizedEntry(_ original: TimeEntry, selection: EntrySelection, at instant: Date) throws {
        var candidate = snapshot
        let ownPlan = plans.first { $0.state == .active && $0.runningEntryID == original.id }
        candidate.entries.removeAll { $0.id == original.id }
        if selection.overwritesExisting {
            // Actual time ends at Now; never create a future tail of a running record.
            removeOverlaps(with: EntrySelection(start: selection.start, end: nil, overwritesExisting: true), from: &candidate, at: instant)
            trimPlans(selection, in: &candidate, excluding: ownPlan?.id)
        }
        let entry = TimeEntry(id: original.id, taskID: original.taskID, start: selection.start, end: nil)
        let index = candidate.entries.firstIndex { $0.start >= entry.start } ?? candidate.entries.endIndex
        candidate.entries.insert(entry, at: index)
        if selection.overwritesExisting { mergeConnectedEntries(at: index, in: &candidate, preserving: original.id) }
        let start = candidate.entries.first { $0.id == original.id }!.start
        if let planIndex = candidate.plans?.firstIndex(where: { $0.id == ownPlan?.id }) {
            candidate.plans?[planIndex].start = start
            candidate.plans?[planIndex].end = selection.end!
        } else {
            let plan = PlannedEntry(id: UUID(), taskID: original.taskID, start: start, end: selection.end!,
                                    state: .active, runningEntryID: original.id)
            candidate.plans = (candidate.plans ?? []) + [plan]
        }
        candidate.checkpoint = instant
        try commit(candidate)
    }

    private func trimPlans(_ selection: EntrySelection, in candidate: inout TrackingSnapshot, excluding id: UUID? = nil) {
        guard let end = selection.end else { return }
        candidate.plans = (candidate.plans ?? []).flatMap { plan -> [PlannedEntry] in
            guard plan.id != id, plan.state.isAutomatic, plan.start < end, plan.end > selection.start else { return [plan] }
            var parts: [PlannedEntry] = []
            if plan.start < selection.start {
                var left = plan
                left.end = selection.start
                parts.append(left)
            }
            if plan.end > end {
                parts.append(PlannedEntry(id: parts.isEmpty ? plan.id : UUID(), taskID: plan.taskID,
                                          start: end, end: plan.end, state: .scheduled))
            }
            return parts
        }
    }

    func preparePlanResize(_ plan: PlannedEntry, edge: EntryEdge, to date: Date, overwriting: Bool) throws -> EntrySelection {
        guard date.timeIntervalSince1970.isFinite else { throw TrackingError.emptyInterval }
        let instant = try checkedInstant()
        var boundary = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        if !overwriting {
            // Clamp against other plans and recorded time, excluding this plan's running entry.
            let occupied = occupiedIntervals(at: instant, excluding: plan.id).filter { interval in
                guard let own = entries.first(where: { $0.id == plan.runningEntryID }) else { return true }
                return interval.start != own.start || interval.end != (own.end ?? instant)
            }
            if edge == .start {
                let lower = occupied.filter { $0.end <= plan.start }.map(\.end).max() ?? .distantPast
                boundary = date <= lower ? lower : max(lower, boundary)
            } else {
                let upper = occupied.filter { $0.start >= plan.end }.map(\.start).min() ?? .distantFuture
                boundary = date >= upper ? upper : min(upper, boundary)
            }
        }
        let selection = EntrySelection(start: edge == .start ? boundary : plan.start,
                                       end: edge == .end ? boundary : plan.end, overwritesExisting: overwriting)
        try validatePlan(selection, at: instant, excluding: plan.id,
                         checkingRecordedTime: !(edge == .end && (plan.state == .active || plan.state == .paused)))
        return selection
    }

    func resizePlan(_ plan: PlannedEntry, edge: EntryEdge, to date: Date, overwriting: Bool) throws {
        let instant = try checkedInstant()
        let selection = try preparePlanResize(plan, edge: edge, to: date, overwriting: overwriting)
        var candidate = snapshot
        if overwriting { trimPlans(selection, in: &candidate, excluding: plan.id) }
        guard let index = candidate.plans?.firstIndex(where: { $0.id == plan.id }) else { throw TrackingError.missingEntry }
        candidate.plans?[index].start = selection.start
        candidate.plans?[index].end = selection.end!
        if let entryIndex = candidate.entries.firstIndex(where: { $0.id == plan.runningEntryID && $0.end == nil }) {
            if edge == .start && selection.start < instant {
                let entry = candidate.entries[entryIndex]
                candidate.entries.remove(at: entryIndex)
                if overwriting {
                    removeOverlaps(with: EntrySelection(start: selection.start, end: nil, overwritesExisting: true), from: &candidate, at: instant)
                }
                candidate.entries.append(TimeEntry(id: entry.id, taskID: entry.taskID, start: selection.start, end: nil))
                candidate.entries.sort { $0.start < $1.start }
            } else if selection.start >= instant || selection.end! <= instant {
                finishRunning(in: &candidate, at: max(candidate.entries[entryIndex].start, min(instant, selection.end!)))
                candidate.plans?[index].state = selection.start >= instant ? .scheduled : .completed
                candidate.plans?[index].runningEntryID = nil
                candidate.checkpoint = nil
            }
        } else if plan.state == .paused && edge == .end {
            candidate.plans?[index].state = selection.end! > instant ? .paused : .completed
        } else if selection.end! > instant {
            candidate.plans?[index].state = .scheduled
            if selection.start < instant {
                if overwriting { removeOverlaps(with: EntrySelection(start: selection.start, end: nil, overwritesExisting: true), from: &candidate, at: instant) }
                let entry = TimeEntry(id: UUID(), taskID: plan.taskID, start: selection.start, end: nil)
                candidate.entries.append(entry)
                candidate.entries.sort { $0.start < $1.start }
                candidate.plans?[index].state = .active
                candidate.plans?[index].runningEntryID = entry.id
                candidate.checkpoint = instant
            }
        }
        try commit(candidate)
    }

    func deletePlan(id: UUID) throws {
        var candidate = snapshot
        // Deleting the plan cancels its automation but preserves already recorded work.
        candidate.plans?.removeAll { $0.id == id }
        try commit(candidate)
    }

    func reassignPlan(id: UUID, input: TaskInput) throws {
        var candidate = snapshot
        guard let index = candidate.plans?.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        let task = resolveTask(input, replacingTags: true, in: &candidate)
        candidate.plans?[index].taskID = task.id
        if let entryIndex = candidate.entries.firstIndex(where: { $0.id == candidate.plans?[index].runningEntryID && $0.end == nil }) {
            let entry = candidate.entries[entryIndex]
            candidate.entries[entryIndex] = TimeEntry(id: entry.id, taskID: task.id, start: entry.start, end: nil)
        }
        try commit(candidate)
    }

    public func reschedulePlan(id: UUID, start: Date, end: Date) throws {
        let instant = try checkedInstant()
        guard start >= instant else { throw TrackingError.pastPlanStart }
        let selection = EntrySelection(start: start, end: end, startsInFuture: true)
        try validatePlan(selection, at: instant, excluding: id)
        var candidate = snapshot
        guard let index = candidate.plans?.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        candidate.plans?[index].start = start
        candidate.plans?[index].end = end
        candidate.plans?[index].state = .scheduled
        candidate.plans?[index].runningEntryID = nil
        try commit(candidate)
    }

    public func setPlanState(id: UUID, state: PlanState) throws {
        var candidate = snapshot
        guard let index = candidate.plans?.firstIndex(where: { $0.id == id }) else { return }
        candidate.plans?[index].state = state
        candidate.plans?[index].runningEntryID = nil
        try commit(candidate)
    }

    public func startPlan(id: UUID, at boundary: Date? = nil) throws {
        let instant = try checkedInstant()
        guard let plan = plans.first(where: { $0.id == id }), plan.state.awaitsStart, instant < plan.end else { return }
        let start = boundary ?? instant
        guard start <= instant, start < plan.end else { throw TrackingError.futureInterval }
        var candidate = snapshot
        let running = runningEntry
        if let activeIndex = candidate.plans?.firstIndex(where: { $0.state == .active }) {
            let finished = candidate.plans![activeIndex].end <= instant
            candidate.plans?[activeIndex].state = finished ? .completed : .skipped
            candidate.plans?[activeIndex].runningEntryID = nil
        }
        let entryID: UUID
        if let running, running.taskID == plan.taskID {
            entryID = running.id
        } else {
            // Never backdate across work recorded after the intended boundary.
            let actualStart = max(start, running?.start ?? .distantPast, entries.last?.end ?? .distantPast)
            finishRunning(in: &candidate, at: actualStart)
            let entry = TimeEntry(id: UUID(), taskID: plan.taskID, start: actualStart, end: nil)
            candidate.entries.append(entry)
            entryID = entry.id
        }
        let index = candidate.plans!.firstIndex { $0.id == id }!
        candidate.plans?[index].state = .active
        candidate.plans?[index].runningEntryID = entryID
        candidate.checkpoint = instant
        try commit(candidate)
    }

    public func finishPlan(id: UUID, at boundary: Date? = nil) throws {
        guard let plan = plans.first(where: { $0.id == id }), plan.state == .active else { return }
        let instant = try checkedInstant()
        var candidate = snapshot
        let index = candidate.plans!.firstIndex { $0.id == id }!
        candidate.plans?[index].state = (boundary ?? instant) < plan.end ? .skipped : .completed
        candidate.plans?[index].runningEntryID = nil
        if let running = runningEntry, running.id == plan.runningEntryID {
            finishRunning(in: &candidate, at: max(running.start, min(boundary ?? instant, instant)))
            candidate.checkpoint = nil
        }
        try commit(candidate)
    }
}
