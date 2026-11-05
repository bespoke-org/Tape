import Foundation
import Testing
@testable import LineCore

@MainActor
struct CalendarTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    func fixture(_ body: (TrackingStore, TrackingSchedule, Clock, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let clock = Clock()
        let store = try TrackingStore(url: url, now: { clock.now })
        try store.setCalendarsEnabled(true)
        try store.setCalendarSelected("work", selected: true)
        store.calendarAccessAvailable = true
        try body(store, TrackingSchedule(store: store, now: { clock.now }), clock, url)
    }
    func event(_ clock: Clock, key: String = "first", title: String = "Meeting", from: Double = 60, to: Double = 600,
               series: String? = nil, eligible: Bool = true, excluded: Bool = false) -> CalendarEvent {
        CalendarEvent(key: key, seriesKey: series, calendarID: "work", calendarTitle: "Work", title: title,
                      start: clock.now + from, end: clock.now + to, eligibleForAutomaticTracking: eligible, excluded: excluded)
    }
    func sync(_ events: [CalendarEvent], store: TrackingStore, clock: Clock) throws {
        try store.reconcileCalendars(events, in: DateInterval(start: clock.now - 86_400, end: clock.now + 30 * 86_400), calendarIDs: ["work"])
    }

    @Test func displayOnlyDoesNotCreateTasksHistoryOrStatistics() throws {
        try fixture { store, schedule, clock, _ in
            try store.setAutomaticCalendarTracking(false)
            try sync([event(clock)], store: store, clock: clock)
            #expect(!store.automaticCalendarTracking && store.entries.isEmpty && store.tasks.isEmpty)
            #expect(store.timelineEntries(at: clock.now).count == 1 && store.scheduledEntries.isEmpty)
            clock.now += 60
            try schedule.poll(available: true)
            #expect(store.runningEntry == nil && schedule.notice == nil)
            let report = StatisticsReport(tasks: store.tasks, entries: store.entries,
                interval: DateInterval(start: clock.now - 600, end: clock.now + 600), now: clock.now)
            #expect(report.total == 0)
            clock.now += 600
            #expect(store.timelineEntries(at: clock.now).isEmpty)
        }
    }

    @Test func colorsReuseTasksAndSurviveRefreshAndRestart() throws {
        try fixture { store, _, clock, url in
            try store.createEntry(named: "Meeting", selection: EntrySelection(start: clock.now - 600, end: clock.now - 300))
            let color = store.tasks[0].color
            let events = [event(clock, title: "MEETING"), event(clock, key: "second", title: "New meeting")]
            try sync(events, store: store, clock: clock)
            let first = store.calendarOccurrences[0]
            #expect(store.task(id: first.id)?.color == color)
            let original = store.calendarOccurrences
            try sync(events.reversed(), store: store, clock: clock)
            #expect(store.calendarOccurrences == original)
            let reopened = try TrackingStore(url: url, now: { clock.now })
            #expect(reopened.calendarOccurrences == original && reopened.tasks.count == 1)
        }
    }

    @Test func automaticStartAndStopUseOneIdentityAndRecordedIntervals() throws {
        try fixture { store, schedule, clock, _ in
            let base = clock.now
            try sync([event(clock)], store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            #expect(store.automaticCalendarTracking)
            clock.now = base + 51
            try schedule.poll(available: true)
            #expect(schedule.notice?.entryID == id && store.entries.isEmpty)
            clock.now = base + 60
            try schedule.poll(available: true)
            #expect(store.runningEntry?.id == id && store.entries.count == 1)
            #expect(store.timelineEntries(at: clock.now).count == 1)
            clock.now = base + 120
            try store.stop(preservingPlan: true)
            clock.now = base + 180
            try schedule.poll(available: true)
            clock.now = base + 189
            try schedule.poll(available: true)
            #expect(store.runningEntry?.recorded.count == 2 && store.runningEntry?.id == id)
            clock.now = base + 600
            try schedule.poll(available: true)
            #expect(store.entries[0].duration(at: clock.now) == 471)
            #expect(store.runningEntry == nil)
        }
    }

    @Test func lateAndManualStartsNeverBackfill() throws {
        try fixture { store, schedule, clock, _ in
            let base = clock.now
            try sync([event(clock, from: -300)], store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            try store.setAutomaticCalendarTracking(true)
            try schedule.poll(available: true)
            #expect(schedule.notice?.deadline == base + 9)
            clock.now += 9
            try schedule.poll(available: true)
            #expect(store.entries[0].recorded.first?.start == base + 9)
            try store.stop()
            try sync([event(clock, key: "other", from: -600)], store: store, clock: clock)
            let other = try #require(store.calendarOccurrences.first { $0.id != id })
            try store.trackCalendarOccurrence(id: other.id)
            #expect(store.runningEntry?.recorded.first?.start == clock.now)
        }
    }

    @Test func changesFollowFutureButPreserveStartedTaskAndCompletedHistory() throws {
        try fixture { store, schedule, clock, _ in
            let base = clock.now
            var meeting = event(clock)
            try sync([meeting], store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            try store.trackCalendarOccurrence(id: id)
            meeting.title = "New name"; meeting.start = base + 120; meeting.end = base + 900
            try sync([meeting], store: store, clock: clock)
            #expect(store.entries[0].start == base + 120 && store.task(id: store.entries[0].taskID)?.name == "New name")
            clock.now = base + 120
            try store.startScheduledEntry(id: id)
            meeting.title = "Changed again"; meeting.end = base + 1_200
            clock.now += 60
            try sync([meeting], store: store, clock: clock)
            #expect(store.runningTask?.name == "New name" && store.runningEntry?.end == base + 1_200)
            try store.stop()
            let finished = store.entries
            meeting.start = base + 1_500; meeting.end = base + 1_800
            try sync([meeting], store: store, clock: clock)
            try schedule.poll(available: true)
            #expect(store.entries == finished && store.runningEntry == nil)
        }
    }

    @Test func cancellationAndSkipPreserveRecordedWorkAndStayHidden() throws {
        try fixture { store, _, clock, url in
            let meeting = event(clock, from: -60)
            try sync([meeting], store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            try store.trackCalendarOccurrence(id: id)
            clock.now += 60
            try store.suppressCalendarOccurrence(id: id)
            #expect(store.runningEntry == nil && store.entries[0].duration(at: clock.now) == 60)
            try sync([meeting], store: store, clock: clock)
            #expect(store.timelineEntries(at: clock.now).count == 1 && store.scheduledEntries.isEmpty)
            let reopened = try TrackingStore(url: url, now: { clock.now })
            reopened.calendarAccessAvailable = true
            #expect(reopened.calendarOccurrences[0].suppressed)
        }
    }

    @Test func tentativeEventsStayVisibleAndExcludedEventsDoNot() throws {
        try fixture { store, schedule, clock, _ in
            try sync([event(clock, eligible: false), event(clock, key: "excluded", excluded: true)], store: store, clock: clock)
            try store.setAutomaticCalendarTracking(true)
            #expect(store.timelineEntries(at: clock.now).count == 1 && store.scheduledEntries.isEmpty)
            clock.now += 60
            try schedule.poll(available: true)
            #expect(schedule.notice == nil)
            try store.trackCalendarOccurrence(id: store.calendarOccurrences[0].id)
            #expect(store.runningEntry != nil)
        }
    }

    @Test func conflictingCalendarsRequireChoiceAndManualPlansWin() throws {
        try fixture { store, schedule, clock, _ in
            let base = clock.now
            try sync([event(clock), event(clock, key: "second", title: "Other", from: 60, to: 300)], store: store, clock: clock)
            try store.setAutomaticCalendarTracking(true)
            clock.now += 51
            try schedule.poll(available: true)
            #expect(schedule.calendarConflict.count == 2 && schedule.notice == nil)
            clock.now += 20
            try schedule.poll(available: true)
            #expect(store.runningEntry == nil && schedule.calendarConflict.count == 2)
            let chosen = schedule.calendarConflict[0].id
            try schedule.chooseCalendar(id: chosen, available: true)
            clock.now += 9
            try schedule.poll(available: true)
            #expect(store.runningEntry?.id == chosen)
            #expect(store.calendarOccurrences.first { $0.id != chosen }?.preventsAutomaticStart == true)
            try store.stop()
            let later = event(clock, key: "later", from: 60, to: 300)
            try sync([later], store: store, clock: clock)
            try store.createEntry(named: "My plan", selection: EntrySelection(start: clock.now + 60, end: clock.now + 300))
            clock.now += 60
            try schedule.poll(available: true)
            #expect(schedule.calendarConflict.isEmpty && schedule.notice?.taskID == store.tasks.first { $0.name == "My plan" }?.id)
            #expect(clock.now > base)
        }
    }

    @Test func seriesAssignmentSuppressionAndDetachmentSurviveSync() throws {
        try fixture { store, _, clock, _ in
            var events = [event(clock, series: "series"), event(clock, key: "second", from: 900, to: 1_200, series: "series")]
            try sync(events, store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            try store.assignCalendarTask(id: id, input: "Team :meeting", scope: .series)
            #expect(store.calendarOccurrences.allSatisfy { $0.taskInput == "Team :meeting" })
            try store.disconnectAndResizeCalendarEntry(id: id, edge: .end, to: clock.now + 720, reachesNow: false, overwriting: false)
            #expect(store.entries.count == 1 && store.entries[0].id == id && store.calendarOccurrence(id: id)?.detached == true)
            events[0].end = clock.now + 300
            try sync(events, store: store, clock: clock)
            #expect(store.entries[0].end == clock.now + 720 && store.timelineEntries(at: clock.now).count == 2)
            let second = store.calendarOccurrences[1].id
            try store.suppressCalendarOccurrence(id: second, scope: .series)
            events.append(event(clock, key: "third", from: 1_800, to: 2_400, series: "series"))
            try sync(events, store: store, clock: clock)
            #expect(store.timelineEntries(at: clock.now).count == 1)
        }
    }

    @Test func disablingAutomaticTrackingKeepsCurrentAndExplicitStops() throws {
        try fixture { store, schedule, clock, _ in
            let base = clock.now
            try sync([event(clock, from: -60, to: 300), event(clock, key: "later", from: 600, to: 900)], store: store, clock: clock)
            try store.trackCalendarOccurrence(id: store.calendarOccurrences[0].id)
            try store.setCalendarsEnabled(false)
            #expect(store.scheduledEntries.count == 1)
            clock.now = base + 300
            try schedule.poll(available: true)
            #expect(store.runningEntry == nil && store.entries[0].duration(at: clock.now) == 300)
        }
    }

    @Test func failedDisconnectPublishesNothingAndPreservesSourceLink() throws {
        try fixture { store, _, clock, url in
            try sync([event(clock)], store: store, clock: clock)
            let original = store.calendarOccurrences
            let data = try Data(contentsOf: url)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) {
                try store.disconnectAndResizeCalendarEntry(id: original[0].id, edge: .end, to: clock.now + 900, reachesNow: false, overwriting: false)
            }
            #expect(store.entries.isEmpty && store.calendarOccurrences == original)
            try FileManager.default.removeItem(at: url)
            try data.write(to: url)
        }
    }

    @Test func disappearanceAndCancellationPreserveRecordedTime() throws {
        try fixture { store, _, clock, _ in
            var meeting = event(clock)
            try sync([meeting], store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            try sync([], store: store, clock: clock)
            #expect(store.timelineEntries(at: clock.now).isEmpty)
            meeting.start += 120
            try sync([meeting], store: store, clock: clock)
            #expect(store.timelineEntries(at: clock.now).first?.id == id)
            clock.now = meeting.start
            try store.trackCalendarOccurrence(id: id)
            clock.now += 60
            meeting.excluded = true
            try sync([meeting], store: store, clock: clock)
            #expect(store.runningEntry == nil && store.entries[0].duration(at: clock.now) == 60)
            let completed = store.entries
            meeting.excluded = false
            meeting.end += 600
            try sync([meeting], store: store, clock: clock)
            #expect(store.entries == completed && store.scheduledEntries.isEmpty)
        }
    }

    @Test func shorteningRunningEventNeverErasesRecordedTime() throws {
        try fixture { store, _, clock, _ in
            var meeting = event(clock, from: -60)
            try sync([meeting], store: store, clock: clock)
            try store.trackCalendarOccurrence(id: store.calendarOccurrences[0].id)
            clock.now += 120
            meeting.end = clock.now - 60
            try sync([meeting], store: store, clock: clock)
            #expect(store.runningEntry == nil)
            #expect(store.entries[0].end == clock.now && store.entries[0].duration(at: clock.now) == 120)
        }
    }

    @Test func newConflictCancelsCountdownAndSurvivesRestart() throws {
        try fixture { store, schedule, clock, url in
            let first = event(clock)
            try sync([first], store: store, clock: clock)
            try store.setAutomaticCalendarTracking(true)
            clock.now += 51
            try schedule.poll(available: true)
            #expect(schedule.notice != nil)
            let second = event(clock, key: "second", from: 9)
            try sync([first, second], store: store, clock: clock)
            try schedule.poll(available: true)
            #expect(schedule.notice == nil && schedule.calendarConflict.count == 2)
            let reopened = try TrackingStore(url: url, now: { clock.now })
            reopened.calendarAccessAvailable = true
            let restarted = TrackingSchedule(store: reopened, now: { clock.now })
            clock.now += 20
            try restarted.poll(available: true)
            #expect(restarted.calendarConflict.count == 2 && reopened.runningEntry == nil)
        }
    }

    @Test func permissionLossHidesPassiveEventsButPreservesExplicitPlan() throws {
        try fixture { store, schedule, clock, _ in
            try sync([event(clock), event(clock, key: "later", from: 900, to: 1_200)], store: store, clock: clock)
            try store.setAutomaticCalendarTracking(true)
            let id = store.calendarOccurrences[0].id
            try store.trackCalendarOccurrence(id: id)
            store.calendarAccessAvailable = false
            #expect(store.timelineEntries(at: clock.now).map(\.id) == [id])
            #expect(store.scheduledEntries.map(\.id) == [id])
            clock.now += 51
            try schedule.poll(available: true)
            #expect(schedule.notice?.entryID == id)
        }
    }

    @Test func calendarMigrationBacksUpVersionThreeOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let clock = Clock()
        let store = try TrackingStore(url: url, now: { clock.now })
        try store.createEntry(named: "Existing", selection: EntrySelection(start: clock.now - 600, end: clock.now - 300))
        let original = try Data(contentsOf: url)
        let entries = store.entries
        try store.setCalendarsEnabled(true)
        let backup = url.appendingPathExtension("before-calendars-v3.json")
        #expect(try Data(contentsOf: backup) == original)
        #expect(store.snapshot.version == 4 && store.entries == entries)
        try store.setAutomaticCalendarTracking(true)
        #expect(try Data(contentsOf: backup) == original)
        let reopened = try TrackingStore(url: url, now: { clock.now })
        #expect(reopened.entries == entries && reopened.calendarsEnabled && reopened.automaticCalendarTracking)
    }

    @Test func overwrittenCalendarPlanDoesNotReappearOnRefresh() throws {
        try fixture { store, _, clock, _ in
            let meeting = event(clock)
            try sync([meeting], store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            try store.trackCalendarOccurrence(id: id)
            try store.createEntry(named: "Replacement", selection: EntrySelection(start: meeting.start, end: meeting.end, overwritesExisting: true, startsInFuture: true))
            try sync([meeting], store: store, clock: clock)
            #expect(store.timelineEntries(at: clock.now).count == 1)
            #expect(!store.isLinkedToCalendar(id: id))
        }
    }


    @Test func passiveColorPersistsWithoutCreatingHistoryAndBecomesTaskColor() throws {
        try fixture { store, _, clock, url in
            let events = [event(clock), event(clock, key: "second", title: "MEETING", from: 900, to: 1_200)]
            try sync(events, store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            try store.setCalendarColor(id: id, color: .orange)
            try sync(events, store: store, clock: clock)
            #expect(store.entries.isEmpty && store.tasks.isEmpty)
            #expect(store.calendarOccurrences.allSatisfy { store.task(id: $0.id)?.color == .orange })
            let reopened = try TrackingStore(url: url, now: { clock.now })
            #expect(reopened.task(id: id)?.color == .orange)
            try reopened.trackCalendarOccurrence(id: id)
            #expect(reopened.tasks[0].color == .orange)
            try reopened.setCalendarColor(id: id, color: .purple)
            #expect(reopened.tasks[0].color == .purple && reopened.entries.count == 1)
        }
    }

    @Test func calendarColorUsesExistingTaskWithoutChangingItsTagsOrTime() throws {
        try fixture { store, _, clock, _ in
            try store.createEntry(named: "Meeting :work", selection: EntrySelection(start: clock.now - 600, end: clock.now - 300))
            let history = store.entries
            try sync([event(clock, title: "MEETING")], store: store, clock: clock)
            let id = store.calendarOccurrences[0].id
            try store.setCalendarColor(id: id, color: .pink)
            #expect(store.tasks.count == 1 && store.tasks[0].color == .pink && store.tasks[0].tags == ["work"])
            #expect(store.entries == history && store.task(id: id)?.color == .pink)
        }
    }


    @Test func automaticCalendarTrackingDefaultsOnAndExplicitOptOutPersists() throws {
        try fixture { store, schedule, clock, url in
            try sync([event(clock)], store: store, clock: clock)
            #expect(store.automaticCalendarTracking && store.scheduledEntries.count == 1)
            #expect(store.entries.isEmpty && store.tasks.isEmpty)
            try store.setAutomaticCalendarTracking(false)
            let reopened = try TrackingStore(url: url, now: { clock.now })
            reopened.calendarAccessAvailable = true
            #expect(!reopened.automaticCalendarTracking && reopened.scheduledEntries.isEmpty)
            clock.now += 60
            try schedule.poll(available: true)
            #expect(schedule.notice == nil && store.runningEntry == nil)
        }
    }

}
