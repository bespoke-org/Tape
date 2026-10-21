import Foundation
import Testing
@testable import LineCore

struct StatisticsTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func entry(_ task: TrackedTask, _ start: Date, _ end: Date?) -> TimeEntry {
        TimeEntry(id: UUID(), taskID: task.id, start: start, end: end)
    }

    @Test func calendarPeriodsIncludeYearAndLeapMonthBoundaries() {
        let week = StatisticsPeriod.week.interval(containing: date(2026, 1, 1), calendar: calendar)
        #expect(week.start == date(2025, 12, 29))
        #expect(week.end == date(2026, 1, 5))
        let month = StatisticsPeriod.month.interval(containing: date(2024, 2, 29), calendar: calendar)
        #expect(month.start == date(2024, 2, 1))
        #expect(month.end == date(2024, 3, 1))
    }

    @Test(arguments: [(3, 8, 23.0), (11, 1, 25.0)])
    func countsElapsedTimeAcrossDaylightSaving(change: (Int, Int, Double)) {
        let (month, day, hours) = change
        let task = TrackedTask(id: UUID(), name: "All day", color: .blue)
        let range = StatisticsPeriod.day.interval(containing: date(2026, month, day), calendar: calendar)
        let report = StatisticsReport(tasks: [task], entries: [entry(task, range.start, range.end)],
                                      interval: range, now: range.end, calendar: calendar)
        #expect(report.total == hours * 3_600)
        #expect(report.days.count == 1)
        #expect(report.days[0].total == report.total)
    }

    @Test func clipsCrossMidnightSessionsAndRunningTimeToPeriodAndNow() {
        let task = TrackedTask(id: UUID(), name: "Work", color: .blue)
        let range = DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 23))
        let now = date(2026, 10, 21, 3)
        let entries = [entry(task, date(2026, 10, 19, 23), date(2026, 10, 20, 1)),
                       entry(task, date(2026, 10, 20, 23), nil),
                       entry(task, date(2026, 10, 22), date(2026, 10, 23))]
        let report = StatisticsReport(tasks: [task], entries: entries, interval: range, now: now, calendar: calendar)
        #expect(report.total == 5 * 3_600)
        #expect(report.days.map(\.total) == [7_200.0, 10_800.0, 0.0])
        #expect(report.sessions.count == 2)
        #expect(report.sessions.first?.interval.start == range.start)
        #expect(report.sessions.last?.interval.end == now)
        let later = StatisticsReport(tasks: [task], entries: entries, interval: range, now: now + 60, calendar: calendar)
        #expect(later.total == report.total + 60)
        let bounded = StatisticsReport(tasks: [task], entries: [entry(task, range.start - 60, range.end + 60)],
                                       interval: range, now: range.end + 100, calendar: calendar)
        #expect(bounded.total == range.duration)
    }

    @Test func tagOverlapDoesNotDoubleCountTotalsAndCrossGroupingDrillsIntoSelection() {
        let build = TrackedTask(id: UUID(), name: "Build", color: .blue, tags: ["dayline", "coding"])
        let meeting = TrackedTask(id: UUID(), name: "Meeting", color: .orange, tags: ["dayline", "meeting"])
        let reading = TrackedTask(id: UUID(), name: "Reading", color: .green)
        let start = date(2026, 10, 20)
        let range = StatisticsPeriod.day.interval(containing: start, calendar: calendar)
        let entries = [entry(build, start, start + 7_200), entry(meeting, start + 7_200, start + 10_800),
                       entry(reading, start + 10_800, start + 14_400)]
        func report(_ filter: StatisticsFilter? = nil) -> StatisticsReport {
            StatisticsReport(tasks: [build, meeting, reading], entries: entries, interval: range,
                             now: range.end, filter: filter, calendar: calendar)
        }
        #expect(report().total == 14_400)
        #expect(report().rows(grouping: .tags).reduce(0) { $0 + $1.duration } == 25_200)
        #expect(report(.tag("dayline")).selectedTotal == 10_800)
        #expect(report(.tag("dayline")).days[0].selected == 10_800)
        #expect(report(.tag("dayline")).rows(grouping: .tasks).map(\.name) == ["Build", "Meeting"])
        #expect(report(.tag("dayline")).rows(grouping: .tags).count == 4)
        #expect(report(.task(build.id)).rows(grouping: .tags).map(\.name) == [":coding", ":dayline"])
        #expect(report(.untagged).rows(grouping: .tasks).map(\.name) == ["Reading"])
        #expect(report(.tag("gone")).selectedTotal == 0)
        #expect(report().rows(grouping: .tasks, search: "BUILD").map(\.id) == [.task(build.id)])
    }

    @Test func tagColorsFollowEarliestEntryAcrossPeriodsFiltersAndMetadataChanges() {
        let first = TrackedTask(id: UUID(), name: "First", color: .orange, tags: ["shared", "original"])
        let later = TrackedTask(id: UUID(), name: "Later", color: .purple, tags: ["shared", "new"])
        let start = date(2026, 10, 20)
        let range = StatisticsPeriod.day.interval(containing: start, calendar: calendar)
        // Input and task order deliberately differ from chronological order.
        let entries = [entry(later, start, start + 3_600), entry(first, start - 86_400, start - 82_800)]
        func report(_ tasks: [TrackedTask], filter: StatisticsFilter? = nil) -> StatisticsReport {
            StatisticsReport(tasks: tasks, entries: entries, interval: range, now: range.end,
                             filter: filter, calendar: calendar)
        }
        let filtered = report([later, first], filter: .task(later.id))
        #expect(filtered.rows(grouping: .tags).first(where: { $0.id == .tag("shared") })?.color == .orange)
        #expect(filtered.color(for: .tag("new")) == .purple)
        #expect(filtered.color(for: .task(later.id)) == .purple)
        #expect(filtered.color(for: .untagged) == nil)
        #expect(report([first, later]).color(for: .tag("shared")) == .orange)
        let recolored = TrackedTask(id: first.id, name: first.name, color: .green, tags: first.tags)
        #expect(report([later, recolored]).color(for: .tag("shared")) == .green)
        let untagged = TrackedTask(id: first.id, name: first.name, color: .orange)
        #expect(report([later, untagged]).color(for: .tag("shared")) == .purple)
        #expect(report([later]).color(for: .tag("shared")) == .purple)
    }

    @Test func stackedBarsPreserveTotalsAndShowFullSelectedTagTime() {
        let build = TrackedTask(id: UUID(), name: "Build", color: .blue, tags: ["project", "coding"])
        let meeting = TrackedTask(id: UUID(), name: "Meeting", color: .orange, tags: ["project"])
        let reading = TrackedTask(id: UUID(), name: "Reading", color: .green)
        let start = date(2026, 10, 20)
        let range = StatisticsPeriod.day.interval(containing: start, calendar: calendar)
        let entries = [entry(build, start - 3_600, start + 7_200),
                       entry(meeting, start + 7_200, start + 10_800),
                       entry(reading, start + 10_800, start + 14_400)]
        func report(_ filter: StatisticsFilter? = nil) -> StatisticsReport {
            StatisticsReport(tasks: [build, meeting, reading], entries: entries, interval: range,
                             now: range.end, filter: filter, calendar: calendar)
        }
        let all = report()
        let tags = all.segments(in: range, grouping: .tags)
        #expect(tags.reduce(0) { $0 + $1.duration } == all.total)
        #expect(tags.first(where: { $0.id == .tag("project") })?.duration == 7_200)
        #expect(tags.first(where: { $0.id == .tag("coding") })?.duration == 3_600)
        #expect(tags.first(where: { $0.id == .untagged })?.duration == 3_600)
        let tasks = all.segments(in: range, grouping: .tasks)
        #expect(tasks.reduce(0) { $0 + $1.duration } == all.total)
        #expect(tasks.first(where: { $0.id == .task(build.id) })?.duration == 7_200)
        let selected = report(.tag("project"))
        let selectedTags = selected.segments(in: range, grouping: .tags)
        #expect(selectedTags.count == 1)
        #expect(selectedTags.first?.duration == 10_800)
        #expect(selected.segments(in: range, grouping: .tasks).map(\.name) == ["Build", "Meeting"])
        #expect(selected.segments(in: range, grouping: .tasks).reduce(0) { $0 + $1.duration } == selected.selectedTotal)
        let taskTags = report(.task(build.id)).segments(in: range, grouping: .tags)
        #expect(taskTags.count == 2 && taskTags.allSatisfy { $0.duration == 3_600 })
        #expect(all.rows(grouping: .tags).first(where: { $0.id == .tag("project") })?.duration == 10_800)
        #expect(all.segments(in: DateInterval(start: range.end, duration: 3_600), grouping: .tags).isEmpty)
    }

    @Test func emptyDataAndCurrentTagMetadata() {
        let start = date(2026, 10, 20)
        let range = StatisticsPeriod.month.interval(containing: start, calendar: calendar)
        let empty = StatisticsReport(tasks: [], entries: [], interval: range, now: start, calendar: calendar)
        #expect(empty.days.count == 31)
        #expect(empty.total == 0 && empty.rows(grouping: .tags).isEmpty)
        let task = TrackedTask(id: UUID(), name: "Study", color: .blue, tags: ["Универ"])
        let session = entry(task, start, start + 3_600)
        let report = StatisticsReport(tasks: [task], entries: [session], interval: range, now: range.end, calendar: calendar)
        #expect(report.rows(grouping: .tags, search: "УНИВЕР").first?.name == ":универ")
        let changed = TrackedTask(id: task.id, name: task.name, color: .red, tags: [])
        let updated = StatisticsReport(tasks: [changed], entries: [session], interval: range, now: range.end, calendar: calendar)
        #expect(updated.rows(grouping: .tags).first?.id == .untagged)
        #expect(updated.rows(grouping: .tasks).first?.color == .red)
        #expect(updated.total == report.total)
    }
}
