import Foundation

/// An unsaved interval. A nil end retains the intent to start tracking after task selection.
public struct EntrySelection: Equatable, Sendable {
    public let start: Date
    public let end: Date?
}
