import Foundation

public enum EntrySegmentKind: Sendable { case recorded, planned, untracked }

public struct EntrySegment: Identifiable, Sendable {
    public var id: String { "\(entry.id)-\(interval.start.timeIntervalSinceReferenceDate)-\(kind)" }
    public let entry: TimeEntry
    public let interval: DateInterval
    public let kind: EntrySegmentKind
}
