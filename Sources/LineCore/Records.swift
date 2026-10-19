import Foundation

public enum TaskColor: String, Codable, CaseIterable, Sendable {
    case blue, teal, green, orange, pink, purple, indigo, red, yellow, mint, cyan, brown
}

public struct TrackedTask: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let color: TaskColor
}

public struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let start: Date
    public internal(set) var end: Date?

    public func duration(at now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

struct TrackingSnapshot: Codable {
    var version = 1
    var tasks: [TrackedTask] = []
    var entries: [TimeEntry] = []
    var checkpoint: Date?
    var timelineSpan: TimeInterval?
}
