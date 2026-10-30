import Foundation
import Observation

/// The application boundary for tracking operations. A failed save never publishes a mutation.
@MainActor
@Observable
public final class TrackingStore {
    var snapshot: TrackingSnapshot
    private let url: URL
    let now: () -> Date

    public var tasks: [TrackedTask] { snapshot.tasks }
    public var entries: [TimeEntry] { snapshot.entries }
    public var scheduledEntries: [TimeEntry] { entries.filter { $0.isAutomatic } }
    public var activeScheduledEntry: TimeEntry? { entries.first { $0.isRunning && $0.end != nil } }
    public static let defaultZoomPresets = [1, 2, 4, 8, 12, 16, 24]
    public var defaultZoomHours: Int { Self.nearestZoomPreset(snapshot.defaultZoomHours ?? 8) }
    public var statisticsDayStartHour: Int { StatisticsDayBoundary(hour: snapshot.statisticsDayStartHour ?? 0).hour }
    public var timeFormat: TimeFormat { snapshot.timeFormat ?? .system }
    public var taskOrder: TaskOrder { snapshot.taskOrder ?? .recentlyUsed }
    public static let resumeCountdownRange = 1...60
    public static let defaultResumeCountdownSeconds = 9
    public var resumeCountdownSeconds: Int {
        Self.boundedResumeCountdown(snapshot.resumeCountdownSeconds ?? Self.defaultResumeCountdownSeconds)
    }
    public var runningEntry: TimeEntry? { entries.first(where: { $0.isRunning }) }
    public var automaticResumeEnabled: Bool { snapshot.automaticResumeEnabled ?? true }
    public static let shortBreakRange = 0...3_600
    public var shortBreakSeconds: Int {
        let legacySeconds = min(max(snapshot.shortBreakMinutes ?? 5, 0), 60) * 60
        return Self.boundedShortBreak(snapshot.shortBreakSeconds ?? legacySeconds)
    }
    public var runningTask: TrackedTask? {
        guard let entry = runningEntry else { return nil }
        return task(id: entry.taskID)
    }

    public init(url: URL, now: @escaping () -> Date = Date.init) throws {
        self.url = url
        self.now = now
        if FileManager.default.fileExists(atPath: url.path) {
            snapshot = try JSONDecoder().decode(TrackingSnapshot.self, from: Data(contentsOf: url))
        } else {
            snapshot = TrackingSnapshot()
        }
        guard (1...3).contains(snapshot.version) else { throw TrackingError.unsupportedStoreVersion }
        let migrating = snapshot.version < 3
        if migrating {
            let backup = url.appendingPathExtension("before-unified-entries-v\(snapshot.version).json")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.copyItem(at: url, to: backup)
            }
            snapshot = try snapshot.unifyingEntries()
        }
        if let checkpoint = snapshot.checkpoint, let running = runningEntry {
            var recovered = snapshot
            let boundary = min(checkpoint, running.end ?? checkpoint)
            finishRunning(in: &recovered, at: boundary, preservingSchedule: running.end != nil)
            recovered.checkpoint = nil
            try commit(recovered)
        } else if migrating || tasks.contains(where: { task in !entries.contains { $0.taskID == task.id } }) {
            try commit(snapshot)
        }
    }

    public func task(id: UUID) -> TrackedTask? {
        tasks.first { $0.id == id }
    }

    public func taskSuggestions(matching query: String) -> [TrackedTask] {
        let input = TaskInput(query)
        let matches = tasks.filter { task in
            (input.name.isEmpty || task.name.localizedCaseInsensitiveContains(input.name))
                && input.tags.allSatisfy { task.tags.contains($0) }
        }
        return taskOrder.sorted(matches, entries: entries)
    }

    public var tags: [String] {
        Set(tasks.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func resolveTask(_ input: TaskInput, replacingTags: Bool = false,
                             in candidate: inout TrackingSnapshot) -> TrackedTask {
        if let index = candidate.tasks.firstIndex(where: { $0.name.caseInsensitiveCompare(input.name) == .orderedSame }) {
            let existing = candidate.tasks[index]
            let task = TrackedTask(id: existing.id, name: existing.name, color: existing.color,
                                   tags: replacingTags ? input.tags : existing.tags + input.tags)
            candidate.tasks[index] = task
            return task
        }
        let task = TrackedTask(id: UUID(), name: input.name, color: initialColor(in: candidate), tags: input.tags)
        candidate.tasks.append(task)
        return task
    }

    public func entries(overlapping range: DateInterval, now: Date) -> ArraySlice<TimeEntry> {
        ArraySlice(entries.filter { $0.start < range.end && ($0.end ?? now) > range.start })
    }

    /// Collision checks use actual intervals; the entry remains the editing identity.
    var recordedEntries: [TimeEntry] {
        entries.flatMap { entry in
            entry.recorded.map { TimeEntry(id: entry.id, taskID: entry.taskID, start: $0.start, end: $0.end) }
        }.sorted { $0.start < $1.start }
    }

    public func startTask(named rawName: String) throws {
        let input = TaskInput(rawName)
        guard !input.name.isEmpty else { throw TrackingError.emptyTaskName }
        var candidate = snapshot
        if let runningTask, runningTask.name.caseInsensitiveCompare(input.name) == .orderedSame {
            let task = resolveTask(input, in: &candidate)
            if runningTask.tags != task.tags { try commit(candidate) }
            return
        }
        let instant = try checkedInstant()
        finishRunning(in: &candidate, at: instant)
        let task = resolveTask(input, in: &candidate)
        candidate.entries.append(TimeEntry(id: UUID(), taskID: task.id, start: instant, end: nil))
        candidate.checkpoint = instant
        try commit(candidate)
    }

    public func prepareEntry(from first: Date, to second: Date, reachesNow: Bool = false, snap: EntrySnap = .minute,
                             overwriting: Bool = false) throws -> EntrySelection {
        let instant = try checkedInstant()
        guard first.timeIntervalSince1970.isFinite, second.timeIntervalSince1970.isFinite,
              first != second else { throw TrackingError.emptyInterval }
        let step = snap.rawValue
        let roundedStart = Date(timeIntervalSince1970: (min(first, second).timeIntervalSince1970 / step).rounded() * step)
        let roundedEnd = Date(timeIntervalSince1970: (max(first, second).timeIntervalSince1970 / step).rounded() * step)
        // Only a drag ending at Now is open-ended. A later endpoint is a plan.
        if min(first, second) >= instant && roundedStart == roundedEnd { throw TrackingError.emptyInterval }
        let futureEnd = min(first, second) >= instant || (!reachesNow && max(first, second) > instant && roundedEnd > instant)
        if futureEnd {
            return try preparePlan(from: first, to: second, start: roundedStart, end: roundedEnd,
                                   overwriting: overwriting, at: instant)
        }
        if overwriting {
            let continues = reachesNow || max(first, second) >= instant
            let selection = EntrySelection(start: roundedStart, end: continues ? nil : min(instant, roundedEnd),
                                           overwritesExisting: true)
            try validate(selection, at: instant)
            return selection
        }
        let entries = recordedEntries
        guard !entries.contains(where: { $0.start <= first && ($0.end ?? .distantFuture) > first }) else {
            throw TrackingError.overlappingEntry
        }
        // Keep the selection in the empty gap containing the drag's starting point.
        // Exact entry boundaries take precedence over the snapping grid.
        let lower = entries.last(where: { ($0.end ?? .distantFuture) <= first })?.end ?? .distantPast
        let upper = entries.first(where: { $0.start > first })?.start
        let snappedStart = min(first, second) <= lower ? lower : roundedStart
        let snappedEnd: Date
        if let upper, max(first, second) >= upper {
            snappedEnd = upper
        } else {
            snappedEnd = roundedEnd
        }
        let start = max(lower, min(upper ?? .distantFuture, snappedStart))
        let continues = (reachesNow || max(first, second) >= instant) && upper == nil
        let end: Date? = continues ? nil : min(upper ?? instant, min(instant, max(lower, snappedEnd)))
        let selection = EntrySelection(start: start, end: end, overwritesExisting: false)
        try validate(selection, at: instant)
        return selection
    }

    public func createEntry(named rawName: String, selection: EntrySelection) throws {
        let input = TaskInput(rawName)
        guard !input.name.isEmpty else { throw TrackingError.emptyTaskName }
        let instant = try checkedInstant()
        try validate(selection, at: instant)
        if let end = selection.end, end > instant || selection.startsInFuture {
            try createPlan(input: input, selection: selection, at: instant)
            return
        }
        var candidate = snapshot
        if selection.overwritesExisting { removeOverlaps(with: selection, from: &candidate, at: instant) }
        let task = resolveTask(input, in: &candidate)
        let entry = TimeEntry(id: UUID(), taskID: task.id, start: selection.start, end: selection.end)
        let index = candidate.entries.firstIndex { $0.start >= entry.start } ?? candidate.entries.endIndex
        candidate.entries.insert(entry, at: index)
        if selection.overwritesExisting { mergeConnectedEntries(at: index, in: &candidate) }
        if selection.end == nil { candidate.checkpoint = instant }
        try commit(candidate)
    }

    private func initialColor(in candidate: TrackingSnapshot) -> TaskColor {
        let usedTasks = Set(candidate.entries.map(\.taskID))
        let usedColors = Set(candidate.tasks.filter { usedTasks.contains($0.id) }.map(\.color))
        let unused = TaskColor.allCases.filter { !usedColors.contains($0) }
        return (unused.isEmpty ? TaskColor.allCases : unused).randomElement()!
    }

    public func prepareResize(id: UUID, edge: EntryEdge, to date: Date, reachesNow: Bool = false,
                              overwriting: Bool = false) throws -> EntrySelection {
        guard let entry = entries.first(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        guard date.timeIntervalSince1970.isFinite else { throw TrackingError.emptyInterval }
        let instant = try checkedInstant()
        var boundary = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        let occupied = occupiedIntervals(at: instant, excluding: id)
        let upper = overwriting ? Date.distantFuture : occupied.filter { $0.start >= (entry.end ?? instant) }.map(\.start).min() ?? .distantFuture
        if edge == .start {
            let lower = overwriting ? Date.distantPast : occupied.filter { $0.end <= entry.start }.map(\.end).max() ?? .distantPast
            boundary = date <= lower ? lower : max(lower, boundary)
        } else {
            boundary = date >= upper ? upper : min(upper, boundary)
        }
        let snapsToNow = edge == .end && entry.start < instant && upper > instant &&
            (reachesNow || date == instant || (date >= instant && boundary <= instant))
        let selection = EntrySelection(start: edge == .start ? boundary : entry.start,
                                       end: snapsToNow ? nil : edge == .end ? boundary : entry.end,
                                       overwritesExisting: overwriting,
                                       startsInFuture: edge == .start ? boundary >= instant : entry.start >= instant)
        guard selection.start < (selection.end ?? instant) else { throw TrackingError.emptyInterval }
        let resized = try previewResizedEntry(id: id, edge: edge, selection: selection)
        if !overwriting { try validateResizedEntry(resized, at: instant) }
        return selection
    }

    private func validateResizedEntry(_ resized: TimeEntry, at instant: Date) throws {
        for other in entries where other.id != resized.id {
            let recordedOverlap = resized.recorded.contains { part in
                other.recorded.contains {
                    part.start < ($0.end ?? instant) && $0.start < (part.end ?? instant)
                }
            }
            let reservationOverlap = resized.isAutomatic && other.isAutomatic &&
                resized.end != nil && other.end != nil &&
                max(resized.start, other.start, instant) < min(resized.end!, other.end!)
            if recordedOverlap || reservationOverlap || (resized.isRunning && other.isRunning) {
                throw TrackingError.overlappingEntry
            }
        }
    }

    public func resizeEntry(id: UUID, edge: EntryEdge, to date: Date, reachesNow: Bool = false,
                            overwriting: Bool = false) throws {
        let selection = try prepareResize(id: id, edge: edge, to: date, reachesNow: reachesNow, overwriting: overwriting)
        let instant = try checkedInstant()
        let entry = try previewResizedEntry(id: id, edge: edge, selection: selection)
        var candidate = snapshot
        candidate.entries.removeAll { $0.id == id }
        if overwriting { removeOverlaps(with: selection, from: &candidate, at: instant) }
        candidate.entries.append(entry)
        candidate.entries.sort { $0.start < $1.start }
        if overwriting, let index = candidate.entries.firstIndex(where: { $0.id == id }) {
            mergeConnectedEntries(at: index, in: &candidate, preserving: id)
        }
        candidate.checkpoint = candidate.entries.contains(where: \.isRunning) ? instant : nil
        try commit(candidate)
    }

    public func previewResizedEntry(id: UUID, edge: EntryEdge, selection: EntrySelection) throws -> TimeEntry {
        guard var entry = entries.first(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        let instant = try checkedInstant()
        let oldStart = entry.start
        let oldEnd = entry.end
        let wasScheduled = entry.state.awaitsStart
        entry.start = selection.start
        entry.end = selection.end
        entry.clipRecording(to: DateInterval(start: entry.start, end: entry.end ?? .distantFuture))
        if entry.start >= instant {
            entry.recorded = []
            entry.state = (entry.end ?? instant) > instant ? .scheduled : .missed
        } else if edge == .end && selection.end == nil {
            // Dragging back onto Now explicitly resumes through Now and removes a deadline.
            extendRecording(&entry, from: min(oldEnd ?? instant, instant), through: instant, running: true)
            entry.state = .active
        } else if let end = entry.end, end <= instant {
            // Keep internal pauses; only the newly added edge is counted as a correction.
            if edge == .end, let oldEnd, end > oldEnd {
                extendRecording(&entry, from: oldEnd, through: end, running: false)
            }
            entry.stopRecording(at: end)
            entry.state = entry.recorded.isEmpty ? .missed : .completed
        } else if entry.state == .paused && edge == .end {
            // Extending a paused entry never backfills the pause or starts tracking.
        } else if edge == .end || (edge == .start && wasScheduled) {
            extendRecording(&entry, from: wasScheduled ? entry.start : min(oldEnd ?? instant, instant), through: instant, running: true)
            entry.state = .active
        }
        if edge == .start && entry.start < oldStart && entry.start < instant {
            if !entry.recorded.contains(where: { $0.start <= entry.start }) {
                extendRecording(&entry, from: entry.start, through: min(oldStart, instant), running: false)
            }
        }
        return entry
    }

    func extendRecording(_ entry: inout TimeEntry, from start: Date, through end: Date, running: Bool) {
        guard start < end || running else { return }
        if !running, let first = entry.recorded.first, end <= first.start {
            if end == first.start { entry.recorded[0].start = start }
            else { entry.recorded.insert(RecordedInterval(start: start, end: end), at: 0) }
            return
        }
        if let last = entry.recorded.last, last.end == nil { return }
        if let index = entry.recorded.indices.last, entry.recorded[index].end == start {
            entry.recorded[index].end = running ? nil : end
        } else {
            entry.recorded.append(RecordedInterval(start: start, end: running ? nil : end))
            entry.recorded.sort { $0.start < $1.start }
        }
    }

    func removeOverlaps(with selection: EntrySelection, from candidate: inout TrackingSnapshot, at instant: Date) {
        let end = selection.end ?? .distantFuture
        var changedRunningEntry = false
        candidate.entries = candidate.entries.flatMap { original -> [TimeEntry] in
            let entryEnd = original.end ?? .distantFuture
            guard original.start < end, entryEnd > selection.start else { return [original] }
            if original.isRunning { changedRunningEntry = true }
            var fragments: [TimeEntry] = []
            if original.start < selection.start {
                var left = original
                left.end = selection.start
                left.clipRecording(to: DateInterval(start: left.start, end: selection.start))
                if selection.start <= instant {
                    left.stopRecording(at: selection.start)
                    left.state = left.recorded.isEmpty ? .missed : .completed
                }
                fragments.append(left)
            }
            if end < entryEnd && (original.end != nil || end < instant) {
                var right = TimeEntry(id: fragments.isEmpty ? original.id : UUID(), taskID: original.taskID,
                                      start: end, end: original.end, state: original.state, recorded: original.recorded)
                right.clipRecording(to: DateInterval(start: end, end: entryEnd))
                if end > instant {
                    right.recorded = []
                    right.state = .scheduled
                }
                fragments.append(right)
            }
            return fragments
        }
        if changedRunningEntry {
            candidate.checkpoint = candidate.entries.contains(where: \.isRunning) ? instant : nil
        }
    }

    func mergeConnectedEntries(at insertionIndex: Int, in candidate: inout TrackingSnapshot, preserving id: UUID? = nil) {
        var index = insertionIndex
        while index > 0 && canMerge(candidate.entries[index - 1], candidate.entries[index]) {
            let left = candidate.entries[index - 1]
            let right = candidate.entries[index]
            candidate.entries[index - 1] = merged(left, right, id: id ?? left.id)
            candidate.entries.remove(at: index)
            index -= 1
        }
        while index + 1 < candidate.entries.count && canMerge(candidate.entries[index], candidate.entries[index + 1]) {
            let left = candidate.entries[index]
            candidate.entries[index] = merged(left, candidate.entries[index + 1], id: id ?? left.id)
            candidate.entries.remove(at: index + 1)
        }
    }

    private func canMerge(_ left: TimeEntry, _ right: TimeEntry) -> Bool {
        left.taskID == right.taskID && left.end == right.start && !left.state.awaitsStart && !right.state.awaitsStart
    }

    private func merged(_ left: TimeEntry, _ right: TimeEntry, id: UUID) -> TimeEntry {
        var recorded = left.recorded
        for part in right.recorded {
            if let last = recorded.indices.last, recorded[last].end == part.start {
                recorded[last].end = part.end
            } else { recorded.append(part) }
        }
        return TimeEntry(id: id, taskID: left.taskID, start: left.start, end: right.end, state: right.state, recorded: recorded)
    }

    public func deleteEntry(id: UUID) throws {
        guard entries.contains(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        var candidate = snapshot
        candidate.entries.removeAll { $0.id == id }
        if !candidate.entries.contains(where: \.isRunning) { candidate.checkpoint = nil }
        try commit(candidate)
    }

    public func setTaskColor(id: UUID, color: TaskColor) throws {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingTask }
        var candidate = snapshot
        candidate.tasks[index] = TrackedTask(id: id, name: tasks[index].name, color: color, tags: tasks[index].tags)
        try commit(candidate)
    }

    public func reassignEntry(id: UUID, taskName rawName: String) throws {
        let input = TaskInput(rawName)
        guard !input.name.isEmpty else { throw TrackingError.emptyTaskName }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        var candidate = snapshot
        let task = resolveTask(input, replacingTags: true, in: &candidate)
        let entry = entries[index]
        if task.id == entry.taskID && task == self.task(id: entry.taskID) { return }
        candidate.entries[index].taskID = task.id
        try commit(candidate)
    }

    public func updateEntry(id: UUID, taskID: UUID, start: Date, end: Date?) throws {
        guard let original = entries.first(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        guard task(id: taskID) != nil else { throw TrackingError.missingTask }
        guard (original.end == nil) == (end == nil) else { throw TrackingError.trackingStateChanged }
        let instant = try checkedInstant()
        try validate(EntrySelection(start: start, end: end, overwritesExisting: false), at: instant, excluding: id)
        guard start < instant, (end ?? instant) <= instant else { throw TrackingError.futureInterval }
        var candidate = snapshot
        candidate.entries.removeAll { $0.id == id }
        var entry = original
        entry.taskID = taskID
        entry.start = start
        entry.end = end
        entry.clipRecording(to: DateInterval(start: start, end: end ?? .distantFuture))
        if start < original.start { extendRecording(&entry, from: start, through: original.start, running: false) }
        if let end, let oldEnd = original.end, end > oldEnd { extendRecording(&entry, from: oldEnd, through: end, running: false) }
        let index = candidate.entries.firstIndex { $0.start > start } ?? candidate.entries.endIndex
        candidate.entries.insert(entry, at: index)
        if end == nil { candidate.checkpoint = instant }
        try commit(candidate)
    }

    func validate(_ selection: EntrySelection, at instant: Date, excluding id: UUID? = nil) throws {
        let end = selection.end ?? instant
        guard selection.start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              selection.start < end else { throw TrackingError.emptyInterval }
        guard selection.overwritesExisting else {
            let future = end > instant || selection.startsInFuture
            let collisionEnd = selection.end ?? .distantFuture
            for entry in entries where entry.id != id {
                let recordedOverlap = entry.recorded.contains {
                    ($0.start < (future ? min(end, instant) : collisionEnd) &&
                    ($0.end ?? (future ? instant : .distantFuture)) > selection.start) ||
                    (future && $0.end == nil && selection.start < instant)
                }
                let scheduledOverlap = entry.isAutomatic && entry.end != nil &&
                    entry.start < end && entry.end! > max(selection.start, instant)
                if recordedOverlap || scheduledOverlap { throw TrackingError.overlappingEntry }
            }
            return
        }
    }

    public func stop(at boundary: Date? = nil, preservingPlan: Bool = false) throws {
        guard let running = runningEntry else { return }
        let instant = try checkedInstant()
        let end = boundary ?? instant
        guard end.timeIntervalSince1970.isFinite, end >= (running.recorded.last?.start ?? running.start) else { throw TrackingError.emptyInterval }
        guard end <= instant else { throw TrackingError.futureInterval }
        var candidate = snapshot
        finishRunning(in: &candidate, at: min(end, running.end ?? end), preservingSchedule: preservingPlan && running.end != nil)
        candidate.checkpoint = nil
        try commit(candidate)
    }

    public func checkpoint() throws {
        guard runningEntry != nil else { return }
        var candidate = snapshot
        candidate.checkpoint = min(try checkedInstant(), activeScheduledEntry?.end ?? .distantFuture)
        try commit(candidate)
    }

    public func setDefaultZoomHours(_ hours: Int) throws {
        let hours = Self.nearestZoomPreset(hours)
        guard hours != defaultZoomHours else { return }
        var candidate = snapshot
        candidate.defaultZoomHours = hours
        try commit(candidate)
    }

    public func setStatisticsDayStartHour(_ hour: Int) throws {
        let hour = StatisticsDayBoundary(hour: hour).hour
        guard hour != statisticsDayStartHour else { return }
        var candidate = snapshot
        candidate.statisticsDayStartHour = hour
        try commit(candidate)
    }

    public func setTimeFormat(_ format: TimeFormat) throws {
        guard format != timeFormat else { return }
        var candidate = snapshot
        candidate.timeFormat = format
        try commit(candidate)
    }

    public func setTaskOrder(_ order: TaskOrder) throws {
        guard order != taskOrder else { return }
        var candidate = snapshot
        candidate.taskOrder = order
        try commit(candidate)
    }

    private static func nearestZoomPreset(_ hours: Int) -> Int {
        let bounded = min(max(hours, 1), 24)
        return defaultZoomPresets.min { abs($0 - bounded) < abs($1 - bounded) }!
    }

    public func setResumeCountdownSeconds(_ seconds: Int) throws {
        let seconds = Self.boundedResumeCountdown(seconds)
        guard seconds != resumeCountdownSeconds else { return }
        var candidate = snapshot
        candidate.resumeCountdownSeconds = seconds
        try commit(candidate)
    }

    private static func boundedResumeCountdown(_ seconds: Int) -> Int {
        min(max(seconds, resumeCountdownRange.lowerBound), resumeCountdownRange.upperBound)
    }

    public func setAutomaticResumeEnabled(_ enabled: Bool) throws {
        guard enabled != automaticResumeEnabled else { return }
        var candidate = snapshot
        candidate.automaticResumeEnabled = enabled
        try commit(candidate)
    }

    public func setShortBreakSeconds(_ seconds: Int) throws {
        let seconds = Self.boundedShortBreak(seconds)
        guard seconds != shortBreakSeconds else { return }
        var candidate = snapshot
        candidate.shortBreakSeconds = seconds
        candidate.shortBreakMinutes = nil
        try commit(candidate)
    }

    private static func boundedShortBreak(_ seconds: Int) -> Int {
        min(max(seconds, shortBreakRange.lowerBound), shortBreakRange.upperBound)
    }

    func checkedInstant() throws -> Date {
        let instant = now()
        let latest = snapshot.checkpoint ?? entries.flatMap(\.recorded).compactMap(\.end).max()
        if let latest, instant < latest { throw TrackingError.clockMovedBackwards }
        return instant
    }

    func finishRunning(in candidate: inout TrackingSnapshot, at instant: Date, preservingSchedule: Bool = false) {
        guard let index = candidate.entries.firstIndex(where: \.isRunning) else { return }
        candidate.entries[index].stopRecording(at: instant)
        if preservingSchedule {
            candidate.entries[index].state = .paused
        } else {
            candidate.entries[index].end = instant
            candidate.entries[index].state = .completed
            if candidate.entries[index].recorded.isEmpty { candidate.entries.remove(at: index) }
        }
    }

    func commit(_ candidate: TrackingSnapshot) throws {
        var candidate = candidate
        candidate.version = 3
        candidate.plans = nil
        candidate.entries.sort { $0.start < $1.start }
        let usedTasks = Set(candidate.entries.map(\.taskID))
        candidate.tasks.removeAll { !usedTasks.contains($0.id) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(candidate)
        try data.write(to: url, options: .atomic)
        snapshot = candidate
    }
}
