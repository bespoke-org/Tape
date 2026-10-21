import Foundation

public enum TimeFormat: String, Codable, CaseIterable, Sendable {
    case system
    case twelveHour
    case twentyFourHour

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .system
    }

    public func string(from date: Date, includeDate: Bool = false,
                       calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String {
        if self == .system {
            return date.formatted(Date.FormatStyle(date: includeDate ? .abbreviated : .omitted, time: .shortened,
                                                  locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        }
        let pattern: Date.FormatString = self == .twelveHour
            ? "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))"
            : "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
        let time = date.formatted(Date.VerbatimFormatStyle(format: pattern, locale: locale,
                                                         timeZone: calendar.timeZone, calendar: calendar))
        guard includeDate else { return time }
        let day = date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted,
                                                locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        return "\(day), \(time)"
    }
}
