import Foundation

public struct CalendarDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let account: String
    public init(id: String, title: String, account: String) { self.id = id; self.title = title; self.account = account }
}

/// Values copied from EventKit. No framework objects cross the provider boundary.
public struct CalendarEvent: Codable, Equatable, Sendable {
    public var key: String
    public var seriesKey: String?
    public var calendarID: String
    public var calendarTitle: String
    public var title: String
    public var start: Date
    public var end: Date
    public var eligibleForAutomaticTracking: Bool
    public var excluded: Bool

    public init(key: String, seriesKey: String? = nil, calendarID: String, calendarTitle: String,
                title: String, start: Date, end: Date, eligibleForAutomaticTracking: Bool = true, excluded: Bool = false) {
        self.key = key; self.seriesKey = seriesKey; self.calendarID = calendarID; self.calendarTitle = calendarTitle
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.title.isEmpty { self.title = "Untitled event" }
        self.start = start; self.end = end
        self.eligibleForAutomaticTracking = eligibleForAutomaticTracking; self.excluded = excluded
    }
}

public struct CalendarOccurrence: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public internal(set) var event: CalendarEvent
    public internal(set) var color: TaskColor
    public internal(set) var taskInput: String?
    public internal(set) var explicitTracking = false
    public internal(set) var detached = false
    public internal(set) var suppressed = false
    public internal(set) var sourceMissing = false
    public internal(set) var preventsAutomaticStart = false
    public internal(set) var requiresChoice = false
}

public enum CalendarScope: Sendable { case occurrence, series }

struct CalendarPreferences: Codable, Equatable {
    var enabled = false
    var automaticTracking = true
    var selectedIDs: Set<String> = []
    var occurrences: [CalendarOccurrence] = []
    var suppressedSeries: Set<String> = []
    var seriesTasks: [String: String] = [:]
}
