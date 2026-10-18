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
        let task = candidate.tasks.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? TrackedTask(id: UUID(), name: name, color: TaskColor.allCases.randomElement()!)
        guard runningTask?.id != task.id else { return }
        let instant = try checkedInstant()
        finishRunning(in: &candidate, at: instant)
        if !candidate.tasks.contains(where: { $0.id == task.id }) {
            candidate.tasks.append(task)
        }
        candidate.entries.append(TimeEntry(id: UUID(), taskID: task.id, start: instant, end: nil))
        candidate.checkpoint = instant
        try commit(candidate)
    }

    public func stop() throws {
        guard runningEntry != nil else { return }
        var candidate = snapshot
        finishRunning(in: &candidate, at: try checkedInstant())
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
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(candidate)
        try data.write(to: url, options: .atomic)
        snapshot = candidate
    }
}
