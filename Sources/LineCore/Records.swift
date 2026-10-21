import Foundation

public enum TaskColor: String, Codable, CaseIterable, Sendable {
    case red, orange, brown, yellow, green, teal, blue, purple, pink

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        // Preserve saved tasks when loading shades removed from the palette.
        switch value {
        case "cyan", "mint": self = .teal
        case "indigo": self = .blue
        default:
            guard let color = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown task color: \(value)")
            }
            self = color
        }
    }
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
    var defaultZoomHours: Int?
    var timeFormat: TimeFormat?
    var taskOrder: TaskOrder?
    var resumeCountdownSeconds: Int?
    var automaticResumeEnabled: Bool?
    var shortBreakMinutes: Int?
    var shortBreakSeconds: Int?
}
