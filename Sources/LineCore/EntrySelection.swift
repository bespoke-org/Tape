import Foundation

public enum EntryEdge: Sendable {
    case start, end
}

public enum EntrySnap: TimeInterval, Sendable {
    case minute = 60
    case fiveMinutes = 300
    case quarterHour = 900
}

/// An unsaved interval. A nil end means the committed entry should keep tracking.
public struct EntrySelection: Equatable, Sendable {
    public let start: Date
    public let end: Date?
    public let startsInFuture: Bool
    public let overwritesExisting: Bool

    public init(start: Date, end: Date?, overwritesExisting: Bool = false, startsInFuture: Bool = false) {
        self.start = start
        self.end = end
        self.overwritesExisting = overwritesExisting
        self.startsInFuture = startsInFuture
    }
}
