import Foundation

public enum PlanState: String, Codable, Sendable {
    case scheduled, active, paused, completed, skipped, missed

    public var awaitsStart: Bool { self == .scheduled || self == .paused }
    public var isAutomatic: Bool { awaitsStart || self == .active }
}

/// Intended time is kept separately from recorded time, including after a missed start.
public struct PlannedEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public internal(set) var taskID: UUID
    public internal(set) var start: Date
    public internal(set) var end: Date
    public internal(set) var state: PlanState
    public internal(set) var runningEntryID: UUID?
}

public struct PlannedSegment: Identifiable, Sendable {
    public var id: String { "\(plan.id)-\(interval.start.timeIntervalSinceReferenceDate)" }
    public let plan: PlannedEntry
    public let interval: DateInterval
    public let label: String
    public var isMissed: Bool { label != "Planned" }
}
