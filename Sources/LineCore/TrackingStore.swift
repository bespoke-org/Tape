import Foundation
import Observation

/// The application boundary for tracking operations. A failed save never publishes a mutation.
@MainActor
@Observable
public final class TrackingStore {
    private var snapshot: TrackingSnapshot
    private let url: URL
    private let now: () -> Date

    public var tasks: [TrackedTask] { snapshot.tasks }
    public var entries: [TimeEntry] { snapshot.entries }
    public var timelineSpan: TimeInterval { TimelineViewport.usableSpan(snapshot.timelineSpan ?? TimelineViewport.defaultSpan) }
    public var runningEntry: TimeEntry? { entries.last(where: { $0.end == nil }) }
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
        guard snapshot.version == 1 else { throw TrackingError.unsupportedStoreVersion }
        if let checkpoint = snapshot.checkpoint, runningEntry != nil {
            var recovered = snapshot
            finishRunning(in: &recovered, at: checkpoint)
            recovered.checkpoint = nil
            try commit(recovered)
        } else {
            let usedTasks = Set(entries.map(\.taskID))
            if tasks.contains(where: { !usedTasks.contains($0.id) }) {
                try commit(snapshot)
            }
        }
    }

    public func task(id: UUID) -> TrackedTask? {
        tasks.first { $0.id == id }
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
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TrackingError.emptyTaskName }
        var candidate = snapshot
        let existingTask = candidate.tasks.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if let existingTask, runningTask?.id == existingTask.id { return }
        let instant = try checkedInstant()
        finishRunning(in: &candidate, at: instant)
        let task = existingTask ?? TrackedTask(id: UUID(), name: name, color: initialColor(in: candidate))
        if !candidate.tasks.contains(where: { $0.id == task.id }) {
            candidate.tasks.append(task)
        }
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
        guard min(first, second) < instant else {
            throw roundedStart == roundedEnd ? TrackingError.emptyInterval : TrackingError.futureInterval
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
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TrackingError.emptyTaskName }
        let instant = try checkedInstant()
        try validate(selection, at: instant)
        var candidate = snapshot
        if selection.overwritesExisting { removeOverlaps(with: selection, from: &candidate, at: instant) }
        let task = candidate.tasks.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? TrackedTask(id: UUID(), name: name, color: initialColor(in: candidate))
        if !candidate.tasks.contains(where: { $0.id == task.id }) { candidate.tasks.append(task) }
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
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        let entry = entries[index]
        guard date.timeIntervalSince1970.isFinite else { throw TrackingError.emptyInterval }
        let instant = try checkedInstant()
        let snapped = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        let lower = !overwriting && index > 0 ? entries[index - 1].end ?? .distantPast : .distantPast
        let upper = !overwriting && index + 1 < entries.count ? entries[index + 1].start : instant
        let startBoundary = date <= lower ? lower : max(lower, snapped)
        let endBoundary = date >= upper ? upper : min(upper, snapped)
        let continues = edge == .end && (overwriting || index == entries.count - 1) && (reachesNow || date >= instant)
        let selection = EntrySelection(start: edge == .start ? startBoundary : entry.start,
                                       end: continues ? nil : edge == .end ? endBoundary : entry.end, overwritesExisting: overwriting)
        try validate(selection, at: instant, excluding: id)
        return selection
    }

    public func resizeEntry(id: UUID, edge: EntryEdge, to date: Date, reachesNow: Bool = false,
                            overwriting: Bool = false) throws {
        let selection = try prepareResize(id: id, edge: edge, to: date, reachesNow: reachesNow, overwriting: overwriting)
        guard let original = entries.first(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        let instant = try checkedInstant()
        var candidate = snapshot
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

    private func removeOverlaps(with selection: EntrySelection, from candidate: inout TrackingSnapshot, at instant: Date) {
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

    private func mergeConnectedEntries(at insertionIndex: Int, in candidate: inout TrackingSnapshot, preserving id: UUID? = nil) {
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
        guard let entry = entries.first(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        var candidate = snapshot
        candidate.entries.removeAll { $0.id == id }
        if entry.end == nil { candidate.checkpoint = nil }
        try commit(candidate)
    }

    public func setTaskColor(id: UUID, color: TaskColor) throws {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingTask }
        var candidate = snapshot
        candidate.tasks[index] = TrackedTask(id: id, name: tasks[index].name, color: color)
        try commit(candidate)
    }

    public func reassignEntry(id: UUID, taskName rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TrackingError.emptyTaskName }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        var candidate = snapshot
        let task = tasks.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? TrackedTask(id: UUID(), name: name, color: initialColor(in: candidate))
        let entry = entries[index]
        guard task.id != entry.taskID else { return }
        if !candidate.tasks.contains(where: { $0.id == task.id }) { candidate.tasks.append(task) }
        candidate.entries[index] = TimeEntry(id: entry.id, taskID: task.id, start: entry.start, end: entry.end)
        try commit(candidate)
    }

    public func updateEntry(id: UUID, taskID: UUID, start: Date, end: Date?) throws {
        guard let original = entries.first(where: { $0.id == id }) else { throw TrackingError.missingEntry }
        guard task(id: taskID) != nil else { throw TrackingError.missingTask }
        guard (original.end == nil) == (end == nil) else { throw TrackingError.trackingStateChanged }
        let instant = try checkedInstant()
        try validate(EntrySelection(start: start, end: end, overwritesExisting: false), at: instant, excluding: id)
        var candidate = snapshot
        candidate.entries.removeAll { $0.id == id }
        let entry = TimeEntry(id: id, taskID: taskID, start: start, end: end)
        let index = candidate.entries.firstIndex { $0.start > start } ?? candidate.entries.endIndex
        candidate.entries.insert(entry, at: index)
        if end == nil { candidate.checkpoint = instant }
        try commit(candidate)
    }

    private func validate(_ selection: EntrySelection, at instant: Date, excluding id: UUID? = nil) throws {
        let end = selection.end ?? instant
        guard selection.start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              selection.start < end else { throw TrackingError.emptyInterval }
        guard selection.start < instant, end <= instant else { throw TrackingError.futureInterval }
        let overlapEnd = selection.end ?? .distantFuture
        guard selection.overwritesExisting || !entries.contains(where: { $0.id != id && $0.start < overlapEnd && ($0.end ?? .distantFuture) > selection.start }) else {
            throw TrackingError.overlappingEntry
        }
    }

    public func stop(at boundary: Date? = nil) throws {
        guard let running = runningEntry else { return }
        let instant = try checkedInstant()
        let end = boundary ?? instant
        guard end.timeIntervalSince1970.isFinite, end >= running.start else { throw TrackingError.emptyInterval }
        guard end <= instant else { throw TrackingError.futureInterval }
        var candidate = snapshot
        finishRunning(in: &candidate, at: end)
        candidate.checkpoint = nil
        try commit(candidate)
    }

    public func checkpoint() throws {
        guard runningEntry != nil else { return }
        var candidate = snapshot
        candidate.checkpoint = try checkedInstant()
        try commit(candidate)
    }

    public func setTimelineSpan(_ span: TimeInterval) throws {
        let span = TimelineViewport.usableSpan(span)
        guard span != timelineSpan else { return }
        var candidate = snapshot
        candidate.timelineSpan = span
        try commit(candidate)
    }

    private func checkedInstant() throws -> Date {
        let instant = now()
        if let latest = snapshot.checkpoint ?? entries.last?.end, instant < latest {
            throw TrackingError.clockMovedBackwards
        }
        return instant
    }

    private func finishRunning(in candidate: inout TrackingSnapshot, at instant: Date) {
        guard let index = candidate.entries.lastIndex(where: { $0.end == nil }) else { return }
        if candidate.entries[index].start == instant {
            candidate.entries.remove(at: index)
        } else {
            candidate.entries[index].end = instant
        }
    }

    private func commit(_ candidate: TrackingSnapshot) throws {
        var candidate = candidate
        let usedTasks = Set(candidate.entries.map(\.taskID))
        candidate.tasks.removeAll { !usedTasks.contains($0.id) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(candidate)
        try data.write(to: url, options: .atomic)
        snapshot = candidate
    }
}
