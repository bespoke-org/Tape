import Foundation

extension TrackingStore {
    public func editableEntry(id: UUID) -> TimeEntry? { entries.first { $0.id == id } }

    func occupiedIntervals(at instant: Date, excluding id: UUID? = nil) -> [DateInterval] {
        entries.filter { $0.id != id }.flatMap { entry in
            let recorded = entry.recorded.map { DateInterval(start: $0.start, end: max($0.start, $0.end ?? instant)) }
            if entry.isAutomatic, let end = entry.end { return recorded + [DateInterval(start: entry.start, end: end)] }
            return recorded
        }.sorted { $0.start < $1.start }
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

    func createPlan(input: TaskInput, selection: EntrySelection, at instant: Date) throws {
        var candidate = snapshot
        if selection.overwritesExisting { removeOverlaps(with: selection, from: &candidate, at: instant) }
        let task = resolveTask(input, in: &candidate)
        let active = selection.start < instant && !selection.startsInFuture
        let id = UUID()
        let entry = TimeEntry(id: id, taskID: task.id, start: selection.start, end: selection.end,
                              state: active ? .active : selection.end! <= instant ? .missed : .scheduled,
                              recorded: active ? [RecordedInterval(id: id, start: selection.start, end: nil)] : [])
        candidate.entries.append(entry)
        if active { candidate.checkpoint = instant }
        try commit(candidate)
    }

    public func rescheduleEntry(id: UUID, start: Date, end: Date) throws {
        let instant = try checkedInstant()
        guard start >= instant else { throw TrackingError.pastPlanStart }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        // Moving recorded work into the future would discard history. Only untouched entries can move wholesale.
        guard entries[index].recorded.isEmpty else { throw TrackingError.entryHasRecordedTime }
        try validate(EntrySelection(start: start, end: end, startsInFuture: true), at: instant, excluding: id)
        var candidate = snapshot
        candidate.entries[index].start = start
        candidate.entries[index].end = end
        candidate.entries[index].state = .scheduled
        try commit(candidate)
    }

    public func skipScheduledEntry(id: UUID) throws {
        var candidate = snapshot
        guard let index = candidate.entries.firstIndex(where: { $0.id == id }) else { return }
        if candidate.entries[index].isRunning {
            // Keep tracking removes the deadline from this entry; there is no leftover plan.
            candidate.entries[index].end = nil
        } else {
            candidate.entries[index].state = .skipped
        }
        try commit(candidate)
    }

    public func markEntryMissed(id: UUID) throws {
        var candidate = snapshot
        guard let index = candidate.entries.firstIndex(where: { $0.id == id }), candidate.entries[index].state.awaitsStart else { return }
        candidate.entries[index].state = candidate.entries[index].recorded.isEmpty ? .missed : .completed
        try commit(candidate)
    }

    public func startScheduledEntry(id: UUID, at boundary: Date? = nil) throws {
        let instant = try checkedInstant()
        guard let entry = entries.first(where: { $0.id == id }), entry.state.awaitsStart,
              let end = entry.end, instant < end else { return }
        let start = boundary ?? instant
        guard start <= instant, start < end else { throw TrackingError.futureInterval }
        var candidate = snapshot
        let latest = entries.flatMap(\.recorded).compactMap(\.end).max() ?? .distantPast
        let actualStart = max(start, runningEntry?.recorded.last?.start ?? .distantPast, latest)
        guard actualStart < end else { return }
        finishRunning(in: &candidate, at: actualStart)
        guard let index = candidate.entries.firstIndex(where: { $0.id == id }) else { return }
        candidate.entries[index].recorded.append(RecordedInterval(start: actualStart, end: nil))
        candidate.entries[index].start = min(entry.start, actualStart)
        candidate.entries[index].state = .active
        candidate.checkpoint = instant
        try commit(candidate)
    }

    public func finishScheduledEntry(id: UUID, at boundary: Date? = nil) throws {
        guard let entry = entries.first(where: { $0.id == id }), entry.isRunning else { return }
        let instant = try checkedInstant()
        var candidate = snapshot
        finishRunning(in: &candidate, at: max(entry.recorded.last?.start ?? entry.start, min(boundary ?? instant, instant)))
        candidate.checkpoint = nil
        try commit(candidate)
    }

    public func timelineSegments(in range: DateInterval, at instant: Date) -> [EntrySegment] {
        entries.flatMap { timelineSegments(for: $0, in: range, at: instant) }
    }

    public func timelineSegments(for entry: TimeEntry, in range: DateInterval, at instant: Date) -> [EntrySegment] {
        guard entry.start < range.end, (entry.end ?? instant) > range.start else { return [] }
        let visible = DateInterval(start: max(entry.start, range.start), end: min(entry.end ?? instant, range.end))
        var segments: [EntrySegment] = []
        var gaps = [visible]
        for part in entry.recorded {
            let end = min(part.end ?? instant, entry.end ?? instant, instant)
            guard end > part.start else { continue }
            if part.start < visible.end && end > visible.start {
                segments.append(EntrySegment(entry: entry, interval: DateInterval(start: max(part.start, visible.start), end: min(end, visible.end)), kind: .recorded))
            }
            gaps = gaps.flatMap { gap in
                guard part.start < gap.end && end > gap.start else { return [gap] }
                var rest: [DateInterval] = []
                if gap.start < part.start { rest.append(DateInterval(start: gap.start, end: part.start)) }
                if end < gap.end { rest.append(DateInterval(start: end, end: gap.end)) }
                return rest
            }
        }
        for gap in gaps {
            if gap.start < instant {
                segments.append(EntrySegment(entry: entry, interval: DateInterval(start: gap.start, end: min(gap.end, instant)), kind: .untracked))
            }
            if gap.end > instant {
                segments.append(EntrySegment(entry: entry, interval: DateInterval(start: max(gap.start, instant), end: gap.end), kind: entry.isAutomatic ? .planned : .untracked))
            }
        }
        return segments
    }
}
