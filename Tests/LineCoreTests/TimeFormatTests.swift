import Foundation
import Testing
import LineCore

struct TimeFormatTests {
    private func calendar(timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    @Test(arguments: [
        (0, 0, "12:00 AM", "00:00"),
        (12, 0, "12:00 PM", "12:00"),
        (13, 5, "1:05 PM", "13:05"),
        (23, 59, "11:59 PM", "23:59")
    ])
    func explicitFormatsHandleMidnightNoonAndMinutes(hour: Int, minute: Int, twelve: String, twentyFour: String) throws {
        let calendar = calendar()
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute)))
        // Explicit choices must win over the locale's preferred hour cycle.
        #expect(TimeFormat.twelveHour.string(from: date, calendar: calendar, locale: Locale(identifier: "en_US@hours=h23")) == twelve)
        #expect(TimeFormat.twentyFourHour.string(from: date, calendar: calendar, locale: Locale(identifier: "en_US@hours=h12")) == twentyFour)
    }

    @Test(arguments: ["en_US", "en_GB", "ru_RU", "en_US@hours=h23"])
    func systemMatchesFoundationFormatting(localeID: String) {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = calendar()
        let locale = Locale(identifier: localeID)
        for includeDate in [false, true] {
            let expected = date.formatted(Date.FormatStyle(date: includeDate ? .abbreviated : .omitted, time: .shortened,
                                                           locale: locale, calendar: calendar, timeZone: calendar.timeZone))
            #expect(TimeFormat.system.string(from: date, includeDate: includeDate, calendar: calendar, locale: locale) == expected)
        }
    }

    @Test func explicitFormatsKeepTimeZoneAndMidnightDateMarkers() throws {
        let calendar = calendar(timeZone: TimeZone(secondsFromGMT: 4 * 3_600)!)
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-21T20:00:00Z"))
        let locale = Locale(identifier: "en_US")
        #expect(TimeFormat.twentyFourHour.string(from: date, calendar: calendar, locale: locale) == "00:00")
        #expect(TimeFormat.twelveHour.string(from: date, calendar: calendar, locale: locale) == "12:00 AM")
        let midnightLabel = TimelineViewport.tickLabel(for: date, calendar: calendar, locale: locale)
        #expect(midnightLabel.contains("22"))
        for format in TimeFormat.allCases {
            #expect(TimelineViewport.tickLabel(for: date, calendar: calendar, locale: locale, timeFormat: format) == midnightLabel)
        }
        let afternoon = date.addingTimeInterval(13 * 3_600 + 5 * 60)
        #expect(TimelineViewport.tickLabel(for: afternoon, calendar: calendar, locale: locale, timeFormat: .twelveHour) == "1:05 PM")
        #expect(TimelineViewport.tickLabel(for: afternoon, calendar: calendar, locale: locale, timeFormat: .twentyFourHour) == "13:05")
        #expect(TimeFormat.twentyFourHour.string(from: afternoon, includeDate: true, calendar: calendar, locale: locale).contains("Oct 22, 2026, 13:05"))
    }
}
