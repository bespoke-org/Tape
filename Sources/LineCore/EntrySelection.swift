import Foundation

public enum EntrySnap: TimeInterval, Sendable {
    case minute = 60
    case fiveMinutes = 300
    case quarterHour = 900
}

/// An unsaved interval. A nil end retains the intent to start tracking after task selection.
public struct EntrySelection: Equatable, Sendable {
    public let start: Date
    public let end: Date?
    public let overwritesExisting: Bool
}
