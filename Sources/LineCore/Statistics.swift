import Foundation

public enum StatisticsPeriod: String, CaseIterable, Sendable {
    case day, week, month

    public func interval(containing date: Date, dayStartHour: Int = 0,
                         calendar: Calendar = .autoupdatingCurrent) -> DateInterval {
        let boundary = StatisticsDayBoundary(hour: dayStartHour)
        let day = boundary.date(containing: date, calendar: calendar)
        let period = calendar.dateInterval(of: self == .day ? .day : self == .week ? .weekOfYear : .month, for: day)!
        return DateInterval(start: boundary.start(on: period.start, calendar: calendar),
                            end: boundary.start(on: period.end, calendar: calendar))
    }
}

public enum StatisticsGrouping: String, CaseIterable, Sendable {
    case tasks, tags
}

public enum StatisticsFilter: Hashable, Sendable {
    case task(UUID), tag(String), untagged

    public var grouping: StatisticsGrouping {
        if case .task = self { return .tasks }
        return .tags
    }

    public func matches(_ task: TrackedTask) -> Bool {
        switch self {
        case .task(let id): task.id == id
        case .tag(let tag): task.tags.contains(tag)
        case .untagged: task.tags.isEmpty
        }
    }
}

public struct StatisticsSession: Identifiable, Sendable {
    public let id: UUID
    public let task: TrackedTask
    public let interval: DateInterval
    public var duration: TimeInterval { interval.duration }
}

public struct StatisticsDay: Identifiable, Sendable {
    public var id: Date { interval.start }
    public let interval: DateInterval
    public let total: TimeInterval
    public let selected: TimeInterval
}

public struct StatisticsRow: Identifiable, Sendable {
    public let id: StatisticsFilter
    public let name: String
    public let color: TaskColor?
    public let duration: TimeInterval
}

public struct StatisticsSegment: Identifiable, Sendable {
    public let id: StatisticsFilter
    public let name: String
    public let color: TaskColor?
    public let duration: TimeInterval
    public let highlightedDuration: TimeInterval
}

/// A read-only projection. Clip every session to the period and to now, then split
/// it at the configured local day boundary; days need not contain exactly 24 hours.
public struct StatisticsReport: Sendable {
    public let interval: DateInterval
    public let sessions: [StatisticsSession]
    public let days: [StatisticsDay]
    public let total: TimeInterval
    public let selectedTotal: TimeInterval
    public let filter: StatisticsFilter?
    private let colors: [StatisticsFilter: TaskColor]

    public init(tasks: [TrackedTask], entries: [TimeEntry], interval: DateInterval,
                now: Date, filter: StatisticsFilter? = nil, dayStartHour: Int = 0,
                calendar: Calendar = .autoupdatingCurrent) {
        self.interval = interval
        self.filter = filter
        let lookup = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var colors = Dictionary(uniqueKeysWithValues: tasks.map { (StatisticsFilter.task($0.id), $0.color) })
        // Resolve tag colors from all history, not just the displayed period or
        // filtered rows. The earliest entry's task supplies its current color.
        let chronological = entries.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id.uuidString < $1.id.uuidString
        }
        for entry in chronological where entry.start <= now {
            guard let task = lookup[entry.taskID] else { continue }
            for tag in task.tags where colors[.tag(tag)] == nil {
                colors[.tag(tag)] = task.color
            }
        }
        self.colors = colors
        let sessions = entries.compactMap { entry -> StatisticsSession? in
            guard let task = lookup[entry.taskID] else { return nil }
            let start = max(entry.start, interval.start)
            let end = min(entry.end ?? now, now, interval.end)
            guard end > start else { return nil }
            return StatisticsSession(id: entry.id, task: task, interval: DateInterval(start: start, end: end))
        }.sorted { $0.interval.start < $1.interval.start }
        self.sessions = sessions
        total = sessions.reduce(0) { $0 + $1.duration }
        selectedTotal = sessions.filter { filter?.matches($0.task) ?? true }.reduce(0) { $0 + $1.duration }
        var days: [StatisticsDay] = []
        let boundary = StatisticsDayBoundary(hour: dayStartHour)
        var cursor = interval.start
        while cursor < interval.end {
            let end = min(boundary.interval(containing: cursor, calendar: calendar).end, interval.end)
            var total: TimeInterval = 0
            var selected: TimeInterval = 0
            for session in sessions where session.interval.start < end && session.interval.end > cursor {
                let duration = min(session.interval.end, end).timeIntervalSince(max(session.interval.start, cursor))
                total += duration
                if filter?.matches(session.task) ?? true { selected += duration }
            }
            days.append(StatisticsDay(interval: DateInterval(start: cursor, end: end), total: total, selected: selected))
            cursor = end
        }
        self.days = days
    }

    public func color(for filter: StatisticsFilter) -> TaskColor? {
        colors[filter]
    }

    /// Keep the full stack and its order independent of selection. Tags share
    /// elapsed time equally; selection only changes the highlighted portion.
    public func segments(in interval: DateInterval, grouping: StatisticsGrouping) -> [StatisticsSegment] {
        var durations: [StatisticsFilter: TimeInterval] = [:]
        var highlighted: [StatisticsFilter: TimeInterval] = [:]
        for session in sessions {
            let start = max(session.interval.start, interval.start)
            let end = min(session.interval.end, interval.end)
            guard end > start else { continue }
            let keys: [StatisticsFilter] = grouping == .tasks ? [.task(session.task.id)] :
                session.task.tags.isEmpty ? [.untagged] : session.task.tags.map { .tag($0) }
            let share = end.timeIntervalSince(start) / Double(keys.count)
            for key in keys {
                durations[key, default: 0] += share
                let matches = filter.map { $0.grouping == grouping ? $0 == key : $0.matches(session.task) } ?? true
                if matches { highlighted[key, default: 0] += share }
            }
        }
        // Use the unfiltered period's breakdown order on every day, even when
        // switching grouping while a task or tag remains selected.
        return rows(grouping: grouping, source: sessions, search: "").compactMap { row in
            guard let duration = durations[row.id] else { return nil }
            return StatisticsSegment(id: row.id, name: row.name, color: row.color, duration: duration,
                                     highlightedDuration: highlighted[row.id, default: 0])
        }
    }

    public func rows(grouping: StatisticsGrouping, search: String = "") -> [StatisticsRow] {
        // Retain sibling rows within the selected grouping. Switching grouping
        // reveals the tasks in a tag, or the tags on a task.
        let source = sessions.filter { filter?.grouping == grouping || (filter?.matches($0.task) ?? true) }
        return rows(grouping: grouping, source: source, search: search)
    }

    private func rows(grouping: StatisticsGrouping, source: [StatisticsSession], search: String) -> [StatisticsRow] {
        var durations: [StatisticsFilter: TimeInterval] = [:]
        var metadata: [StatisticsFilter: (String, TaskColor?)] = [:]
        for session in source {
            let task = session.task
            let keys: [StatisticsFilter] = grouping == .tasks ? [.task(task.id)] :
                task.tags.isEmpty ? [.untagged] : task.tags.map { .tag($0) }
            for key in keys {
                durations[key, default: 0] += session.duration
                switch key {
                case .task: metadata[key] = (task.name, task.color)
                case .tag(let tag): metadata[key] = (":" + tag, colors[key])
                case .untagged: metadata[key] = ("Untagged", nil)
                }
            }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return durations.compactMap { key, duration -> StatisticsRow? in
            guard let (name, color) = metadata[key], query.isEmpty || name.localizedStandardContains(query) else { return nil }
            return StatisticsRow(id: key, name: name, color: color, duration: duration)
        }.sorted {
            if $0.duration != $1.duration { return $0.duration > $1.duration }
            let order = $0.name.localizedStandardCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            return String(describing: $0.id) < String(describing: $1.id)
        }
    }
}
