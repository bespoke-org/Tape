import Foundation

/// A statistics day is named for the calendar date on which it starts.
/// Boundaries use local wall time, so a day can be shorter or longer during DST.
public struct StatisticsDayBoundary: Sendable {
    public let hour: Int

    public init(hour: Int = 0) {
        self.hour = min(max(hour, 0), 23)
    }

    public func start(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        // Missing hours advance to the next valid time; repeated hours use the
        // first occurrence so adjacent days always share exactly one boundary.
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: date),
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
    }

    public func date(containing instant: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let date = calendar.startOfDay(for: instant)
        return instant < start(on: date, calendar: calendar)
            ? calendar.date(byAdding: .day, value: -1, to: date)!
            : date
    }

    public func interval(containing instant: Date, calendar: Calendar = .autoupdatingCurrent) -> DateInterval {
        let date = date(containing: instant, calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 1, to: date)!
        return DateInterval(start: start(on: date, calendar: calendar), end: start(on: next, calendar: calendar))
    }

    /// Interior three-hour marks follow the wall clock across midnight and DST.
    public func ticks(in interval: DateInterval, calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        let date = date(containing: interval.start, calendar: calendar)
        return stride(from: 3, through: 21, by: 3).compactMap { offset in
            let hours = hour + offset
            let tickDate = calendar.date(byAdding: .day, value: hours / 24, to: date)!
            guard let tick = calendar.date(bySettingHour: hours % 24, minute: 0, second: 0, of: tickDate,
                                           matchingPolicy: .nextTime, repeatedTimePolicy: .first),
                  tick > interval.start, tick < interval.end else { return nil }
            return tick
        }
    }
}
