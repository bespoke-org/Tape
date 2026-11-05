import Foundation

extension TrackingStore {
    public var calendarsEnabled: Bool { snapshot.calendars?.enabled ?? false }
    public var automaticCalendarTracking: Bool { snapshot.calendars?.automaticTracking ?? true }
    public var selectedCalendarIDs: Set<String> { snapshot.calendars?.selectedIDs ?? [] }
    public var calendarOccurrences: [CalendarOccurrence] { snapshot.calendars?.occurrences ?? [] }

    public func calendarOccurrence(id: UUID) -> CalendarOccurrence? { calendarOccurrences.first { $0.id == id } }
    public func isLinkedToCalendar(id: UUID) -> Bool {
        calendarOccurrence(id: id).map { !$0.detached && !$0.suppressed } ?? false
    }
    public func setCalendarsEnabled(_ enabled: Bool) throws {
        var candidate = snapshot
        if candidate.calendars == nil { candidate.calendars = CalendarPreferences() }
        candidate.calendars!.enabled = enabled
        try commit(candidate)
    }
    public func setAutomaticCalendarTracking(_ enabled: Bool) throws {
        var candidate = snapshot
        if candidate.calendars == nil { candidate.calendars = CalendarPreferences() }
        candidate.calendars!.automaticTracking = enabled
        try commit(candidate)
    }
    public func setCalendarSelected(_ id: String, selected: Bool) throws {
        var candidate = snapshot
        if candidate.calendars == nil { candidate.calendars = CalendarPreferences() }
        if selected { candidate.calendars!.selectedIDs.insert(id) }
        else { candidate.calendars!.selectedIDs.remove(id) }
        try commit(candidate)
    }

    private func selected(_ occurrence: CalendarOccurrence) -> Bool {
        calendarsEnabled && calendarAccessAvailable && selectedCalendarIDs.contains(occurrence.event.calendarID)
    }

    func calendarDisplayTask(id: UUID) -> TrackedTask? {
        guard let occurrence = calendarOccurrence(id: id) else { return nil }
        let input = TaskInput(occurrence.taskInput ?? occurrence.event.title)
        let matching = tasks.first { $0.name.caseInsensitiveCompare(input.name) == .orderedSame }
        return TrackedTask(id: occurrence.id, name: matching?.name ?? input.name,
                           color: matching?.color ?? occurrence.color, tags: input.tags)
    }

    public func timelineEntries(at instant: Date) -> [TimeEntry] {
        entries + calendarOccurrences.compactMap { occurrence in
            guard selected(occurrence), !occurrence.suppressed, !occurrence.detached, !occurrence.event.excluded, !occurrence.sourceMissing,
                  occurrence.event.end > instant, !entries.contains(where: { $0.id == occurrence.id }) else { return nil }
            return projection(occurrence)
        }
    }

    func projection(_ occurrence: CalendarOccurrence) -> TimeEntry {
        TimeEntry(id: occurrence.id, taskID: occurrence.id, start: occurrence.event.start, end: occurrence.event.end,
                  state: .scheduled, recorded: [])
    }

    func schedulingEntries(at instant: Date) -> [TimeEntry] {
        timelineEntries(at: instant).filter { entry in
            guard entry.isAutomatic else { return false }
            guard let occurrence = calendarOccurrence(id: entry.id), !occurrence.detached else { return true }
            if entry.isRunning { return true }
            guard !occurrence.suppressed, !occurrence.event.excluded, !occurrence.sourceMissing else { return false }
            return occurrence.explicitTracking || (selected(occurrence) && automaticCalendarTracking &&
                occurrence.event.eligibleForAutomaticTracking && !occurrence.preventsAutomaticStart)
        }
    }

    public func isCalendarCandidate(_ entry: TimeEntry) -> Bool { isLinkedToCalendar(id: entry.id) }

    public func calendarStartIsBlocked(_ entry: TimeEntry, at instant: Date) -> Bool {
        guard isCalendarCandidate(entry) else { return false }
        // An explicitly scheduled Tape entry owns its time, including when it was chosen from a calendar.
        return entries.contains { other in
            guard other.id != entry.id, other.isAutomatic, let end = other.end,
                  max(entry.start, other.start, instant) < min(entry.end ?? instant, end) else { return false }
            return !isCalendarCandidate(other) || calendarOccurrence(id: other.id)?.explicitTracking == true || other.isRunning
        }
    }

    /// Refetch results are authoritative only for the successfully read range and calendars.
    public func reconcileCalendars(_ events: [CalendarEvent], in range: DateInterval, calendarIDs: Set<String>) throws {
        guard calendarsEnabled else { return }
        let instant = try checkedInstant()
        var candidate = snapshot
        var preferences = candidate.calendars ?? CalendarPreferences()
        let incoming = events.filter { calendarIDs.contains($0.calendarID) && $0.start < $0.end &&
            $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite }
        let keys = Set(incoming.map(\.key))
        // Missing occurrences are cancellations, never a reason to erase recorded work.
        for index in preferences.occurrences.indices {
            let occurrence = preferences.occurrences[index]
            let event = occurrence.event
            guard !occurrence.detached, !occurrence.suppressed, event.end > instant,
                  calendarIDs.contains(event.calendarID), event.start < range.end, event.end > range.start,
                  !keys.contains(event.key) else { continue }
            if let entry = candidate.entries.first(where: { $0.id == occurrence.id }), !entry.state.awaitsStart && !entry.isRunning { continue }
            preferences.occurrences[index].sourceMissing = true
            finishCalendarOccurrence(occurrence.id, in: &candidate, at: instant)
        }
        for event in incoming {
            if let index = preferences.occurrences.firstIndex(where: { $0.event.key == event.key }) {
                let old = preferences.occurrences[index]
                guard !old.detached, !old.suppressed, !preferences.suppressedSeries.contains(event.seriesKey ?? "") else { continue }
                if let entry = candidate.entries.first(where: { $0.id == old.id }), !entry.state.awaitsStart && !entry.isRunning { continue }
                preferences.occurrences[index].sourceMissing = false
                preferences.occurrences[index].event = event
                if event.excluded {
                    finishCalendarOccurrence(old.id, in: &candidate, at: instant)
                } else if let entryIndex = candidate.entries.firstIndex(where: { $0.id == old.id }) {
                    if candidate.entries[entryIndex].recorded.isEmpty {
                        candidate.entries[entryIndex].start = event.start
                        if old.taskInput == nil {
                            let task = resolveTask(TaskInput(event.title), in: &candidate)
                            candidate.entries[entryIndex].taskID = task.id
                        }
                    }
                    // A revised end never truncates already recorded intervals.
                    let lastRecorded = candidate.entries[entryIndex].recorded.map { $0.end ?? instant }.max() ?? .distantPast
                    candidate.entries[entryIndex].end = max(event.end, lastRecorded)
                    if candidate.entries[entryIndex].isRunning && event.end <= instant {
                        finishCalendarOccurrence(old.id, in: &candidate, at: instant)
                    }
                }
            } else if event.end > instant && !event.excluded && !preferences.suppressedSeries.contains(event.seriesKey ?? "") {
                let name = TaskInput(event.title).name
                let matching = candidate.tasks.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                let previous = preferences.occurrences.first { TaskInput($0.taskInput ?? $0.event.title).name.caseInsensitiveCompare(name) == .orderedSame }
                let used = Set(candidate.tasks.map(\.color) + preferences.occurrences.map(\.color))
                let unused = TaskColor.allCases.filter { !used.contains($0) }
                let color = matching?.color ?? previous?.color ?? (unused.isEmpty ? TaskColor.allCases : unused).randomElement()!
                preferences.occurrences.append(CalendarOccurrence(id: UUID(), event: event, color: color,
                    taskInput: event.seriesKey.flatMap { preferences.seriesTasks[$0] }))
            }
        }
        candidate.calendars = preferences
        if candidate.calendars != snapshot.calendars || candidate.entries != entries || candidate.tasks != tasks { try commit(candidate) }
    }

    func finishCalendarOccurrence(_ id: UUID, in candidate: inout TrackingSnapshot, at instant: Date) {
        guard let index = candidate.entries.firstIndex(where: { $0.id == id }) else { return }
        if candidate.entries[index].isRunning {
            candidate.entries[index].stopRecording(at: min(instant, candidate.entries[index].end ?? instant))
            candidate.checkpoint = nil
        }
        if candidate.entries[index].recorded.isEmpty { candidate.entries.remove(at: index) }
        else {
            candidate.entries[index].end = candidate.entries[index].recorded.compactMap(\.end).max()
            candidate.entries[index].state = .completed
        }
    }

    public func suppressCalendarOccurrence(id: UUID, scope: CalendarScope = .occurrence) throws {
        guard let occurrence = calendarOccurrence(id: id) else { throw TrackingError.missingEntry }
        let instant = try checkedInstant()
        var candidate = snapshot
        if scope == .series, let series = occurrence.event.seriesKey { candidate.calendars!.suppressedSeries.insert(series) }
        for index in candidate.calendars!.occurrences.indices {
            let other = candidate.calendars!.occurrences[index]
            guard other.id == id || (scope == .series && occurrence.event.seriesKey != nil && other.event.seriesKey == occurrence.event.seriesKey) else { continue }
            if other.detached { continue }
            if other.id != id, let entry = candidate.entries.first(where: { $0.id == other.id }), entry.state == .completed { continue }
            candidate.calendars!.occurrences[index].suppressed = true
            finishCalendarOccurrence(other.id, in: &candidate, at: instant)
        }
        try commit(candidate)
    }

    public func setCalendarColor(id: UUID, color: TaskColor) throws {
        guard let occurrence = calendarOccurrence(id: id) else { throw TrackingError.missingEntry }
        let task = entries.first { $0.id == id }.flatMap { self.task(id: $0.taskID) } ?? calendarDisplayTask(id: id)
        let name = task?.name ?? TaskInput(occurrence.taskInput ?? occurrence.event.title).name
        var candidate = snapshot
        if let index = candidate.tasks.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            let existing = candidate.tasks[index]
            candidate.tasks[index] = TrackedTask(id: existing.id, name: existing.name, color: color, tags: existing.tags)
        }
        // Reserve the task color without creating a task or recorded entry for a passive event.
        for index in candidate.calendars!.occurrences.indices {
            let other = candidate.calendars!.occurrences[index]
            let otherName = TaskInput(other.taskInput ?? other.event.title).name
            if other.id == id || otherName.caseInsensitiveCompare(name) == .orderedSame {
                candidate.calendars!.occurrences[index].color = color
            }
        }
        try commit(candidate)
    }

    public func assignCalendarTask(id: UUID, input: String, scope: CalendarScope = .occurrence) throws {
        guard !TaskInput(input).name.isEmpty else { throw TrackingError.emptyTaskName }
        guard let occurrence = calendarOccurrence(id: id) else { throw TrackingError.missingEntry }
        var candidate = snapshot
        if scope == .series, let series = occurrence.event.seriesKey { candidate.calendars!.seriesTasks[series] = input }
        for index in candidate.calendars!.occurrences.indices {
            let other = candidate.calendars!.occurrences[index]
            guard other.id == id || (scope == .series && occurrence.event.seriesKey != nil && other.event.seriesKey == occurrence.event.seriesKey) else { continue }
            if let entry = candidate.entries.first(where: { $0.id == other.id }), !entry.recorded.isEmpty && other.id != id { continue }
            if other.detached && other.id != id { continue }
            candidate.calendars!.occurrences[index].taskInput = input
            if let entryIndex = candidate.entries.firstIndex(where: { $0.id == other.id }) {
                let task = resolveTask(TaskInput(input), replacingTags: true, in: &candidate)
                candidate.entries[entryIndex].taskID = task.id
            }
        }
        try commit(candidate)
    }

    func materializeCalendarEntry(id: UUID, in candidate: inout TrackingSnapshot, explicit: Bool) throws {
        guard let index = candidate.calendars?.occurrences.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        let occurrence = candidate.calendars!.occurrences[index]
        guard !occurrence.suppressed, !occurrence.detached, !occurrence.event.excluded, !occurrence.sourceMissing else { throw TrackingError.missingEntry }
        if explicit { candidate.calendars!.occurrences[index].explicitTracking = true }
        candidate.calendars!.occurrences[index].preventsAutomaticStart = false
        candidate.calendars!.occurrences[index].requiresChoice = false
        if candidate.entries.contains(where: { $0.id == id }) { return }
        let input = TaskInput(occurrence.taskInput ?? occurrence.event.title)
        let existed = candidate.tasks.contains { $0.name.caseInsensitiveCompare(input.name) == .orderedSame }
        var task = resolveTask(input, in: &candidate)
        if !existed {
            task = TrackedTask(id: task.id, name: task.name, color: occurrence.color, tags: task.tags)
            candidate.tasks[candidate.tasks.firstIndex(where: { $0.id == task.id })!] = task
        }
        candidate.entries.append(TimeEntry(id: id, taskID: task.id, start: occurrence.event.start, end: occurrence.event.end,
                                          state: .scheduled, recorded: []))
    }

    public func trackCalendarOccurrence(id: UUID) throws {
        if runningEntry?.id == id { return }
        let instant = try checkedInstant()
        guard let occurrence = calendarOccurrence(id: id), occurrence.event.end > instant else { throw TrackingError.missingEntry }
        let projected = projection(occurrence)
        guard !calendarStartIsBlocked(projected, at: instant) else { throw TrackingError.overlappingEntry }
        var candidate = snapshot
        try materializeCalendarEntry(id: id, in: &candidate, explicit: true)
        if occurrence.event.start <= instant {
            finishRunning(in: &candidate, at: instant)
            let index = candidate.entries.firstIndex { $0.id == id }!
            candidate.entries[index].state = .active
            candidate.entries[index].recorded.append(RecordedInterval(start: instant, end: nil))
            candidate.checkpoint = instant
        }
        try commit(candidate)
    }

    public func requireCalendarChoice(ids: Set<UUID>) throws {
        var candidate = snapshot
        var changed = false
        for index in (candidate.calendars?.occurrences ?? []).indices where ids.contains(candidate.calendars!.occurrences[index].id) {
            if !candidate.calendars!.occurrences[index].requiresChoice {
                candidate.calendars!.occurrences[index].requiresChoice = true; changed = true
            }
        }
        if changed { try commit(candidate) }
    }

    public func chooseCalendarOccurrence(id: UUID, among ids: Set<UUID>) throws {
        var candidate = snapshot
        for index in (candidate.calendars?.occurrences ?? []).indices where ids.contains(candidate.calendars!.occurrences[index].id) {
            candidate.calendars!.occurrences[index].requiresChoice = false
            candidate.calendars!.occurrences[index].preventsAutomaticStart = candidate.calendars!.occurrences[index].id != id
        }
        try materializeCalendarEntry(id: id, in: &candidate, explicit: true)
        try commit(candidate)
    }

    public func disconnectAndResizeCalendarEntry(id: UUID, edge: EntryEdge, to date: Date,
                                                reachesNow: Bool, overwriting: Bool) throws {
        let selection = try prepareResize(id: id, edge: edge, to: date, reachesNow: reachesNow, overwriting: overwriting)
        var resized = try previewResizedEntry(id: id, edge: edge, selection: selection)
        var candidate = snapshot
        try materializeCalendarEntry(id: id, in: &candidate, explicit: true)
        resized.taskID = candidate.entries.first { $0.id == id }!.taskID
        let index = candidate.calendars!.occurrences.firstIndex { $0.id == id }!
        candidate.calendars!.occurrences[index].detached = true
        try saveResizedEntry(resized, selection: selection, in: candidate)
    }
}
