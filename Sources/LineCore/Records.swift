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
    public let tags: [String]

    public init(id: UUID, name: String, color: TaskColor, tags: [String] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.tags = TaskInput.normalizedTags(tags)
    }

    private enum CodingKeys: String, CodingKey { case id, name, color, tags }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id),
                  name: try values.decode(String.self, forKey: .name),
                  color: try values.decode(TaskColor.self, forKey: .color),
                  tags: try values.decodeIfPresent([String].self, forKey: .tags) ?? [])
    }

    public var inputText: String { TaskInput.text(name: name, tags: tags) }
    public var tagText: String { tags.map { ":" + $0 }.joined(separator: " ") }
}

public enum EntryState: String, Codable, Sendable {
    case scheduled, active, paused, completed, skipped, missed
    public var awaitsStart: Bool { self == .scheduled || self == .paused }
}

public struct RecordedInterval: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public internal(set) var start: Date
    public internal(set) var end: Date?

    public init(id: UUID = UUID(), start: Date, end: Date?) {
        self.id = id
        self.start = start
        self.end = end
    }
}

public struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public internal(set) var taskID: UUID
    /// Intended bounds. A future end is a deadline, never recorded time.
    public internal(set) var start: Date
    public internal(set) var end: Date?
    public internal(set) var state: EntryState
    /// Only these intervals count toward tracked time; nil end denotes live recording.
    public internal(set) var recorded: [RecordedInterval]
    public var isRunning: Bool { state == .active }
    public var isAutomatic: Bool { state.awaitsStart || (isRunning && end != nil) }

    public init(id: UUID, taskID: UUID, start: Date, end: Date?, state: EntryState? = nil,
                recorded: [RecordedInterval]? = nil) {
        self.id = id
        self.taskID = taskID
        self.start = start
        self.end = end
        self.state = state ?? (end == nil ? .active : .completed)
        self.recorded = recorded ?? [RecordedInterval(id: id, start: start, end: end)]
    }

    private enum CodingKeys: String, CodingKey { case id, taskID, start, end, state, recorded }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id), taskID: try values.decode(UUID.self, forKey: .taskID),
                  start: try values.decode(Date.self, forKey: .start), end: try values.decodeIfPresent(Date.self, forKey: .end),
                  state: try values.decodeIfPresent(EntryState.self, forKey: .state),
                  recorded: try values.decodeIfPresent([RecordedInterval].self, forKey: .recorded))
    }

    public func duration(at now: Date) -> TimeInterval {
        recorded.reduce(0) { $0 + max(0, min($1.end ?? now, now, end ?? now).timeIntervalSince($1.start)) }
    }

    mutating func stopRecording(at instant: Date) {
        for index in recorded.indices where recorded[index].end == nil {
            recorded[index].end = max(recorded[index].start, instant)
        }
        recorded.removeAll { $0.end == $0.start }
    }

    mutating func clipRecording(to range: DateInterval) {
        recorded = recorded.compactMap { part in
            let start = max(part.start, range.start)
            let end = min(part.end ?? range.end, range.end)
            guard end > start else { return nil }
            return RecordedInterval(id: part.id, start: start, end: part.end == nil ? nil : end)
        }
    }
}

struct TrackingSnapshot: Codable {
    var version = 3
    var tasks: [TrackedTask] = []
    var entries: [TimeEntry] = []
    var calendars: CalendarPreferences?
    var plans: [LegacyPlannedEntry]?
    var checkpoint: Date?
    var defaultZoomHours: Int?
    var statisticsDayStartHour: Int?
    var timeFormat: TimeFormat?
    var taskOrder: TaskOrder?
    var resumeCountdownSeconds: Int?
    var automaticResumeEnabled: Bool?
    var shortBreakMinutes: Int?
    var shortBreakSeconds: Int?
}
