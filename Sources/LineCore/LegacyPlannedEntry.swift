import Foundation

enum LegacyPlanState: String, Codable, Sendable {
    case scheduled, active, paused, completed, skipped, missed
}

/// Version 2 only. Decoded during migration; never written to the current store.
struct LegacyPlannedEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var taskID: UUID
    var start: Date
    var end: Date
    var state: LegacyPlanState
    var runningEntryID: UUID?
}

