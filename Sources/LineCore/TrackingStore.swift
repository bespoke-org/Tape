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
    public var plans: [PlannedEntry] { snapshot.plans ?? [] }
    public var activePlan: PlannedEntry? { plans.first { $0.state == .active } }
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
    public var runningEntry: TimeEntry? { entries.last(where: { $0.end == nil }) }
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
        guard snapshot.version == 1 || snapshot.version == 2 else { throw TrackingError.unsupportedStoreVersion }
        if let checkpoint = snapshot.checkpoint, runningEntry != nil {
            var recovered = snapshot
            for index in (recovered.plans ?? []).indices where recovered.plans?[index].state == .active {
                recovered.plans?[index].state = .paused
                recovered.plans?[index].runningEntryID = nil
            }
            finishRunning(in: &recovered, at: min(checkpoint, activePlan?.end ?? checkpoint))
            recovered.checkpoint = nil
            try commit(recovered)
        } else {
            let usedTasks = Set(entries.map(\.taskID) + plans.map(\.taskID))
            if tasks.contains(where: { !usedTasks.contains($0.id) }) {
                try commit(snapshot)
            }
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
        // Entries are chronological and non-overlapping. Skip history in logarithmic time.
        var lower = 0
        var upper = entries.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if (entries[middle].end ?? now) <= range.start {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return entries[lower...].prefix { $0.start < range.end }
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
        let usedTasks = Set(candidate.entries.map(\.taskID) + (candidate.plans ?? []).map(\.taskID))
        let usedColors = Set(candidate.tasks.filter { usedTasks.contains($0.id) }.map(\.color))
        let unused = TaskColor.allCases.filter { !usedColors.contains($0) }
        return (unused.isEmpty ? TaskColor.allCases : unused).randomElement()!
    }

    public func prepareResize(id: UUID, edge: EntryEdge, to date: Date, reachesNow: Bool = false,
                              overwriting: Bool = false) throws -> EntrySelection {
        if let plan = plans.first(where: { $0.id == id }) {
            if plan.state == .active && edge == .end && (reachesNow || date == now()) {
                return EntrySelection(start: plan.start, end: nil, overwritesExisting: overwriting)
            }
            return try preparePlanResize(plan, edge: edge, to: date, overwriting: overwriting)
        }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        let entry = entries[index]
        guard date.timeIntervalSince1970.isFinite else { throw TrackingError.emptyInterval }
        let instant = try checkedInstant()
        let snapped = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        let lower = !overwriting && index > 0 ? entries[index - 1].end ?? .distantPast : .distantPast
        let nextRecord = !overwriting && index + 1 < entries.count ? entries[index + 1].start : nil
        let nextPlan = !overwriting ? plans.filter {
            $0.state.isAutomatic && $0.runningEntryID != id && $0.start > instant
        }.map(\.start).min() : nil
        let upper = nextRecord ?? (edge == .end ? nextPlan ?? .distantFuture : instant)
        let startBoundary = date <= lower ? lower : max(lower, snapped)
        let endBoundary = date >= upper ? upper : min(upper, snapped)
        let futureEndpoint = edge == .end && !reachesNow && date > instant && snapped > instant
        let continues = edge == .end && nextRecord == nil && !futureEndpoint && (reachesNow || date >= instant)
        let selection = EntrySelection(start: edge == .start ? startBoundary : entry.start,
                                       end: continues ? nil : edge == .end ? endBoundary : entry.end, overwritesExisting: overwriting)
        try validate(selection, at: instant, excluding: id)
        return selection
    }

    public func resizeEntry(id: UUID, edge: EntryEdge, to date: Date, reachesNow: Bool = false,
                            overwriting: Bool = false) throws {
        if let plan = plans.first(where: { $0.id == id }) {
            if plan.state == .active && edge == .end && (reachesNow || date == now()) {
                try setPlanState(id: id, state: .skipped)
            } else {
                try resizePlan(plan, edge: edge, to: date, overwriting: overwriting)
            }
            return
        }
        let selection = try prepareResize(id: id, edge: edge, to: date, reachesNow: reachesNow, overwriting: overwriting)
        guard let original = entries.first(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        let instant = try checkedInstant()
        if let end = selection.end, end > instant {
            try scheduleResizedEntry(original, selection: selection, at: instant)
            return
        }
        var candidate = snapshot
        if edge == .end && selection.end == nil,
           let planIndex = candidate.plans?.firstIndex(where: { $0.runningEntryID == id && $0.state == .active }) {
            candidate.plans?[planIndex].state = .skipped
            candidate.plans?[planIndex].runningEntryID = nil
        }
        candidate.entries.removeAll { $0.id == id }
        if overwriting { removeOverlaps(with: selection, from: &candidate, at: instant) }
        let entry = TimeEntry(id: id, taskID: original.taskID, start: selection.start, end: selection.end)
        let index = candidate.entries.firstIndex { $0.start >= entry.start } ?? candidate.entries.endIndex
        candidate.entries.insert(entry, at: index)
        if overwriting { mergeConnectedEntries(at: index, in: &candidate, preserving: id) }
        if selection.end == nil {
            candidate.checkpoint = instant
        } else if !candidate.entries.contains(where: { $0.end == nil }) {
            candidate.checkpoint = nil
        }
        try commit(candidate)
    }

    func removeOverlaps(with selection: EntrySelection, from candidate: inout TrackingSnapshot, at instant: Date) {
        if candidate.entries.contains(where: { $0.end == nil && $0.start < (selection.end ?? .distantFuture) }) {
            // A surviving running tail may begin after its previous recovery checkpoint.
            candidate.checkpoint = instant
        }
        candidate.entries = candidate.entries.flatMap { entry -> [TimeEntry] in
            guard entry.start < (selection.end ?? .distantFuture),
                  (entry.end ?? .distantFuture) > selection.start else { return [entry] }
            var fragments: [TimeEntry] = []
            if entry.start < selection.start {
                fragments.append(TimeEntry(id: entry.id, taskID: entry.taskID, start: entry.start, end: selection.start))
            }
            if let end = selection.end, end < (entry.end ?? .distantFuture) {
                fragments.append(TimeEntry(id: fragments.isEmpty ? entry.id : UUID(), taskID: entry.taskID,
                                           start: end, end: entry.end))
            }
            return fragments
        }
    }

    func mergeConnectedEntries(at insertionIndex: Int, in candidate: inout TrackingSnapshot, preserving id: UUID? = nil) {
        var index = insertionIndex
        let taskID = candidate.entries[index].taskID
        while index > 0,
              candidate.entries[index - 1].taskID == taskID,
              candidate.entries[index - 1].end == candidate.entries[index].start {
            let left = candidate.entries[index - 1]
            candidate.entries[index - 1] = TimeEntry(id: id ?? left.id, taskID: taskID,
                                                    start: left.start, end: candidate.entries[index].end)
            candidate.entries.remove(at: index)
            index -= 1
        }
        while index + 1 < candidate.entries.count,
              candidate.entries[index + 1].taskID == taskID,
              candidate.entries[index].end == candidate.entries[index + 1].start {
            candidate.entries[index].end = candidate.entries[index + 1].end
            candidate.entries.remove(at: index + 1)
        }
    }

    public func deleteEntry(id: UUID) throws {
        if plans.contains(where: { $0.id == id }) {
            try deletePlan(id: id)
            return
        }
        guard let entry = entries.first(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        var candidate = snapshot
        candidate.entries.removeAll { $0.id == id }
        if entry.end == nil { candidate.checkpoint = nil }
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
        if plans.contains(where: { $0.id == id }) {
            try reassignPlan(id: id, input: input)
            return
        }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        var candidate = snapshot
        let task = resolveTask(input, replacingTags: true, in: &candidate)
        let entry = entries[index]
        if task.id == entry.taskID && task == self.task(id: entry.taskID) { return }
        candidate.entries[index] = TimeEntry(id: entry.id, taskID: task.id, start: entry.start, end: entry.end)
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
        let entry = TimeEntry(id: id, taskID: taskID, start: start, end: end)
        let index = candidate.entries.firstIndex { $0.start > start } ?? candidate.entries.endIndex
        candidate.entries.insert(entry, at: index)
        if end == nil { candidate.checkpoint = instant }
        try commit(candidate)
    }

    func validate(_ selection: EntrySelection, at instant: Date, excluding id: UUID? = nil) throws {
        let end = selection.end ?? instant
        guard selection.start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              selection.start < end else { throw TrackingError.emptyInterval }
        if end > instant || selection.startsInFuture {
            try validatePlan(selection, at: instant, excluding: id, checkingRecordedTime: !selection.startsInFuture)
            return
        }
        guard selection.start < instant else { throw TrackingError.futureInterval }
        let overlapEnd = selection.end ?? .distantFuture
        guard selection.overwritesExisting || !entries.contains(where: { $0.id != id && $0.start < overlapEnd && ($0.end ?? .distantFuture) > selection.start }) else {
            throw TrackingError.overlappingEntry
        }
    }

    public func stop(at boundary: Date? = nil, preservingPlan: Bool = false) throws {
        guard let running = runningEntry else { return }
        let instant = try checkedInstant()
        let end = boundary ?? instant
        guard end.timeIntervalSince1970.isFinite, end >= running.start else { throw TrackingError.emptyInterval }
        guard end <= instant else { throw TrackingError.futureInterval }
        var candidate = snapshot
        if preservingPlan, let index = candidate.plans?.firstIndex(where: { $0.state == .active }) {
            candidate.plans?[index].state = .paused
            candidate.plans?[index].runningEntryID = nil
        }
        finishRunning(in: &candidate, at: end)
        candidate.checkpoint = nil
        try commit(candidate)
    }

    public func checkpoint() throws {
        guard runningEntry != nil else { return }
        var candidate = snapshot
        candidate.checkpoint = min(try checkedInstant(), activePlan?.end ?? .distantFuture)
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
        if let latest = snapshot.checkpoint ?? entries.last?.end, instant < latest {
            throw TrackingError.clockMovedBackwards
        }
        return instant
    }

    func finishRunning(in candidate: inout TrackingSnapshot, at instant: Date) {
        guard let index = candidate.entries.lastIndex(where: { $0.end == nil }) else { return }
        if candidate.entries[index].start == instant {
            candidate.entries.remove(at: index)
        } else {
            candidate.entries[index].end = instant
        }
    }

    func commit(_ candidate: TrackingSnapshot) throws {
        var candidate = candidate
        if candidate.plans != nil { candidate.version = 2 }
        // Manual stops, switches, reassignment, deletion, and overwrite all detach
        // automation from the old running entry in the same atomic transaction.
        for index in (candidate.plans ?? []).indices {
            guard let plan = candidate.plans?[index], plan.state == .active else { continue }
            if !candidate.entries.contains(where: { $0.id == plan.runningEntryID && $0.end == nil && $0.taskID == plan.taskID }) {
                candidate.plans?[index].state = .skipped
                candidate.plans?[index].runningEntryID = nil
            }
        }
        let usedTasks = Set(candidate.entries.map(\.taskID) + (candidate.plans ?? []).map(\.taskID))
        candidate.tasks.removeAll { !usedTasks.contains($0.id) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(candidate)
        try data.write(to: url, options: .atomic)
        snapshot = candidate
    }
}
