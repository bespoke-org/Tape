import Foundation
import Testing
import LineCore

struct TimelineViewportTests {
    @Test func multiDayTicksKeepHoursAndIdentifyMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z"))
        let viewport = TimelineViewport(span: 2 * 86_400)
        let ticks = viewport.ticks(at: now, width: 580, calendar: calendar)
        let labels = ticks.map { TimelineViewport.tickLabel(for: $0, calendar: calendar, locale: Locale(identifier: "en_US")) }
        #expect(labels[0] != labels[1])
        #expect(labels[0].contains(":"))
        let midnight = try #require(ticks.firstIndex { calendar.component(.hour, from: $0) == 0 })
        #expect(labels[midnight].contains("Oct"))
        #expect(!labels[midnight].contains(":"))
    }

    @Test func tickDensityAdaptsAndLocalDaysRespectDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-03-08T12:00:00Z"))
        let close = TimelineViewport(span: 3_600)
        let closeTicks = close.ticks(at: now, width: 580, calendar: calendar)
        #expect(closeTicks.count >= 3 && closeTicks.count <= 9)
        #expect(closeTicks.allSatisfy { close.range(at: now).contains($0) })
        let days = TimelineViewport(span: 5 * 86_400)
        let ticks = days.ticks(at: now, width: 580, calendar: calendar)
        #expect(ticks.count >= 4 && ticks.count <= 7)
        #expect(ticks.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        #expect(zip(ticks, ticks.dropFirst()).contains { $1.timeIntervalSince($0) == 23 * 3_600 })
        let broad = TimelineViewport(span: 90 * 86_400)
        #expect(broad.ticks(at: now, width: 580, calendar: calendar).count <= 9)
    }
    @Test func pinchPreservesThePointUnderThePointerWhileBrowsing() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var viewport = TimelineViewport()
        viewport.scroll(points: 300, width: 600, now: now)
        let anchor = now.addingTimeInterval(-10_800)
        viewport.zoom(factor: 2, anchorFraction: 0.25, now: now)
        #expect(viewport.span == 7_200)
        #expect(viewport.date(at: 0.25, now: now) == anchor)
        #expect(viewport.fraction(for: anchor, now: now) == 0.25)
        viewport.followNow()
        viewport.zoom(factor: 2, anchorFraction: 0.1, now: now)
        #expect(viewport.span == 3_600)
        #expect(viewport.fraction(for: now, now: now) == 0.5)
        viewport.zoom(factor: .nan, anchorFraction: 0.5, now: now)
        #expect(viewport.span == 3_600)
        viewport.zoom(factor: 1e20, anchorFraction: 0.5, now: now)
        #expect(viewport.span > 0)
        viewport.zoom(factor: 1e-20, anchorFraction: 0.5, now: now)
        #expect(viewport.span.isFinite)
    }
    @Test func scrollingFreezesTheViewedTimeUntilReturningToNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var viewport = TimelineViewport()
        #expect(viewport.range(at: now).start == now.addingTimeInterval(-7_200))
        viewport.scroll(points: 300, width: 600, now: now)
        #expect(!viewport.isFollowingNow)
        #expect(viewport.range(at: now).end == now)
        #expect(viewport.range(at: now.addingTimeInterval(60)) == viewport.range(at: now))
        viewport.followNow()
        #expect(viewport.isFollowingNow)
        #expect(viewport.range(at: now.addingTimeInterval(60)).start == now.addingTimeInterval(-7_140))
    }
}
