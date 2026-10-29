import Foundation
import Testing
@testable import LineCore

@MainActor
struct PlanningTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }
    private func fixture(_ body: (TrackingStore, TrackingSchedule, Clock, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let url = directory.appendingPathComponent("tracking.json")
        let store = try TrackingStore(url: url, now: { clock.now })
        let schedule = TrackingSchedule(store: store, now: { clock.now })
        try body(store, schedule, clock, url)
    }
    @discardableResult private func plan(_ store: TrackingStore, from: Date, to: Date, name: String = "Coding", overwrite: Bool = false) throws -> PlannedEntry {
        let selection = try store.prepareEntry(from: from, to: to, overwriting: overwrite)
        try store.createEntry(named: name, selection: selection)
        return try #require(store.plans.last)
    }

    @Test func plansPersistWithoutCountingAsTrackedTime() throws {
        try fixture { store, _, clock, url in
            let start = clock.now + 600
            let planned = try plan(store, from: start, to: start + 3_600, name: "Code :work")
            #expect(store.entries.isEmpty && store.runningEntry == nil)
            #expect(store.tasks.first?.tags == ["work"])
            let report = StatisticsReport(tasks: store.tasks, entries: store.entries,
                                          interval: DateInterval(start: clock.now, duration: 86_400), now: clock.now)
            #expect(report.total == 0)
            let reopened = try TrackingStore(url: url, now: { clock.now })
            #expect(reopened.plans == [planned] && reopened.tasks == store.tasks)
            #expect(reopened.plannedSegments(in: DateInterval(start: clock.now, duration: 86_400), at: clock.now).first?.label == "Planned")
        }
    }

    @Test func beforeStartCountdownSwitchesAndStopsAtExactBoundaries() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            try store.startTask(named: "Previous")
            let planned = try plan(store, from: base + 60, to: base + 180)
            clock.now = base + 50
            try scheduler.poll(available: true)
            #expect(scheduler.notice == nil)
            clock.now = base + 51
            try scheduler.poll(available: true)
            #expect(scheduler.notice?.action == .start)
            #expect(scheduler.notice?.remainingSeconds(at: clock.now) == 9)
            clock.now = base + 60.2
            try scheduler.poll(available: true)
            #expect(store.runningTask?.name == "Coding")
            #expect(store.entries[0].end == base + 60 && store.runningEntry?.start == base + 60)
            clock.now = base + 171
            try scheduler.poll(available: true)
            #expect(scheduler.notice?.action == .stop)
            clock.now = base + 180.2
            try scheduler.poll(available: true)
            #expect(store.runningEntry == nil && store.entries.last?.end == planned.end)
            #expect(store.plans.first?.state == .completed)
        }
    }

    @Test func startNowSkipStopNowAndKeepTracking() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            let planned = try plan(store, from: base + 60, to: base + 180)
            clock.now = base + 51
            try scheduler.poll(available: true)
            try scheduler.accept(available: true)
            #expect(store.runningEntry?.start == clock.now && store.activePlan?.end == planned.end)
            clock.now = base + 171
            try scheduler.poll(available: true)
            try scheduler.reject()
            #expect(store.runningEntry != nil && store.activePlan == nil)
            clock.now = base + 190
            try scheduler.poll(available: true)
            #expect(store.runningTask?.name == "Coding")
            let second = try plan(store, from: base + 240, to: base + 300, name: "Meeting")
            clock.now = base + 231
            try scheduler.poll(available: true)
            try scheduler.reject()
            clock.now = base + 250
            try scheduler.poll(available: true)
            #expect(store.runningTask?.name == "Coding")
            #expect(store.plans.first(where: { $0.id == second.id })?.state == .skipped)
            let third = try plan(store, from: base + 360, to: base + 420, name: "Review")
            clock.now = base + 351
            try scheduler.poll(available: true)
            try scheduler.accept(available: true)
            clock.now = base + 411
            try scheduler.poll(available: true)
            try scheduler.accept(available: true)
            #expect(store.runningEntry == nil && store.entries.last?.end == clock.now)
            #expect(store.plans.first(where: { $0.id == third.id })?.state == .skipped)
        }
    }

    @Test func lateReturnNeverBackfillsAndExpiredOrTooShortPlansAreMissed() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            try plan(store, from: base + 60, to: base + 180)
            clock.now = base + 51
            try scheduler.poll(available: false)
            #expect(scheduler.notice == nil)
            clock.now = base + 90
            try scheduler.poll(available: true)
            #expect(scheduler.notice?.deadline == base + 99)
            clock.now = base + 99
            try scheduler.poll(available: true)
            #expect(store.runningEntry?.start == base + 99)
            clock.now = base + 181
            try scheduler.poll(available: true)
            try plan(store, from: base + 240, to: base + 300, name: "Too late")
            clock.now = base + 295
            try scheduler.poll(available: true)
            #expect(store.plans.last?.state == .missed && scheduler.notice == nil)
            try plan(store, from: base + 360, to: base + 420, name: "Expired")
            clock.now = base + 430
            try scheduler.poll(available: true)
            #expect(store.plans.last?.state == .missed && store.entries.count == 1)
        }
    }

    @Test func lockAndWakeKeepEndpointAndNeverIncludeShortBreak() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            let interruption = TrackingInterruption(store: store, now: { clock.now })
            let planned = try plan(store, from: base - 60, to: base + 300)
            clock.now = base + 30
            try interruption.handle(.locked)
            scheduler.suspend()
            #expect(store.runningEntry == nil && store.plans.first?.state == .paused)
            #expect(interruption.interruptedTask == nil)
            clock.now = base + 60
            try interruption.handle(.unlocked)
            try scheduler.poll(available: interruption.isAvailable)
            #expect(scheduler.notice?.deadline == base + 69)
            clock.now = base + 69
            try scheduler.poll(available: true)
            #expect(store.entries.count == 2 && store.entries[0].end == base + 30)
            #expect(store.runningEntry?.start == base + 69 && store.activePlan?.end == planned.end)
        }
    }

    @Test func manualSwitchOrStopCancelsOnlyThatPlan() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            try plan(store, from: base - 60, to: base + 120)
            clock.now += 10
            try store.startTask(named: "Manual")
            #expect(store.plans.first?.state == .skipped)
            clock.now = base + 121
            try scheduler.poll(available: true)
            #expect(store.runningTask?.name == "Manual")
            try store.stop()
            try plan(store, from: base + 180, to: base + 240, name: "Later")
            clock.now = base + 171
            try scheduler.poll(available: true)
            try scheduler.accept(available: true)
            clock.now += 1
            try store.stop()
            clock.now = base + 190
            try scheduler.poll(available: true)
            #expect(store.runningEntry == nil && store.plans.last?.state == .skipped)
        }
    }

    @Test func sameTaskStaysContinuousAndResumePreferenceDoesNotDisablePlans() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            try store.setAutomaticResumeEnabled(false)
            try store.startTask(named: "Coding")
            let id = store.runningEntry?.id
            try plan(store, from: base + 60, to: base + 180)
            clock.now = base + 51
            try scheduler.poll(available: true)
            #expect(scheduler.notice == nil)
            clock.now = base + 60
            try scheduler.poll(available: true)
            #expect(store.runningEntry?.id == id && store.entries.count == 1)
            #expect(store.activePlan != nil)
            clock.now = base + 171
            try scheduler.poll(available: true)
            #expect(scheduler.notice?.action == .stop)
        }
    }

    @Test func restartRecoversOnlyCheckpointAndOffersRemainingPlan() throws {
        try fixture { store, _, clock, url in
            let base = clock.now
            try plan(store, from: base - 60, to: base + 300)
            clock.now = base + 30
            try store.checkpoint()
            clock.now = base + 90
            let reopened = try TrackingStore(url: url, now: { clock.now })
            #expect(reopened.entries.first?.end == base + 30)
            #expect(reopened.plans.first?.state == .paused)
            let scheduler = TrackingSchedule(store: reopened, now: { clock.now })
            try scheduler.poll(available: true)
            #expect(scheduler.notice?.deadline == base + 99)
        }
    }

    @Test func ordinaryDrawingClampsAndCommandDrawingSplitsPlans() throws {
        try fixture { store, _, clock, _ in
            let base = clock.now
            try plan(store, from: base + 120, to: base + 480)
            let bounded = try store.prepareEntry(from: base + 60, to: base + 180)
            #expect(bounded.end == base + 120)
            #expect(throws: TrackingError.overlappingEntry) { try store.prepareEntry(from: base + 180, to: base + 300) }
            try plan(store, from: base + 240, to: base + 360, name: "Meeting", overwrite: true)
            #expect(store.entries.isEmpty && store.plans.count == 3)
            #expect(store.plans.contains { $0.start == base + 120 && $0.end == base + 240 })
            #expect(store.plans.contains { $0.start == base + 360 && $0.end == base + 480 })
        }
    }

    @Test func plannedEditingResizesIntoPastReassignsAndDeletesWithoutLosingHistory() throws {
        try fixture { store, _, clock, _ in
            let base = clock.now
            let planned = try plan(store, from: base + 120, to: base + 300)
            try store.reassignEntry(id: planned.id, taskName: "Meeting :work")
            #expect(store.task(id: store.plans[0].taskID)?.name == "Meeting")
            try store.resizeEntry(id: planned.id, edge: .start, to: base - 60)
            #expect(store.runningEntry?.start == base - 60 && store.activePlan?.end == base + 300)
            try store.resizeEntry(id: planned.id, edge: .end, to: base + 600)
            #expect(store.activePlan?.end == base + 600)
            try store.deleteEntry(id: planned.id)
            #expect(store.plans.isEmpty && store.runningEntry != nil)
        }
    }

    @Test func missedSegmentsStayGrayWhileRecordedPortionsAreExcluded() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            try plan(store, from: base + 60, to: base + 180)
            clock.now = base + 90
            try scheduler.poll(available: true)
            clock.now = base + 99
            try scheduler.poll(available: true)
            clock.now = base + 120
            let segments = store.plannedSegments(in: DateInterval(start: base, duration: 300), at: clock.now)
            #expect(segments.count == 2)
            #expect(segments.first?.label == "Missed" && segments.first?.interval.end == base + 99)
            #expect(segments.last?.label == "Planned" && segments.last?.interval.start == base + 120)
        }
    }

    @Test func failedScheduledStartAndStopPreserveStateAndRetry() throws {
        try fixture { store, scheduler, clock, url in
            let base = clock.now
            try plan(store, from: base + 60, to: base + 180)
            clock.now = base + 51
            try scheduler.poll(available: true)
            let saved = try Data(contentsOf: url)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            clock.now = base + 60
            #expect(throws: (any Error).self) { try scheduler.poll(available: true) }
            #expect(store.entries.isEmpty && scheduler.notice != nil && store.plans.first?.state == .scheduled)
            try FileManager.default.removeItem(at: url)
            try saved.write(to: url)
            try scheduler.poll(available: true)
            #expect(store.runningEntry?.start == base + 60)
        }
    }
    @Test func adjacentPlansSwitchWithoutGapsAndSameTaskKeepsEntry() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            try plan(store, from: base - 60, to: base + 120)
            let firstID = store.runningEntry?.id
            try plan(store, from: base + 120, to: base + 240)
            try plan(store, from: base + 240, to: base + 360, name: "Meeting")
            clock.now = base + 111
            try scheduler.poll(available: true)
            #expect(scheduler.notice == nil)
            clock.now = base + 120.2
            try scheduler.poll(available: true)
            #expect(store.runningEntry?.id == firstID && store.entries.count == 1)
            clock.now = base + 231
            try scheduler.poll(available: true)
            #expect(scheduler.notice?.action == .start)
            clock.now = base + 240.2
            try scheduler.poll(available: true)
            #expect(store.runningTask?.name == "Meeting")
            #expect(store.entries[0].end == base + 240 && store.entries[1].start == base + 240)
        }
    }

    @Test func changingPausedEndpointDoesNotBackfillAndStalePopupCannotAct() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            let planned = try plan(store, from: base - 60, to: base + 300)
            clock.now = base + 30
            try store.stop(preservingPlan: true)
            let entries = store.entries
            clock.now = base + 90
            try store.resizeEntry(id: planned.id, edge: .end, to: base + 600)
            #expect(store.entries == entries && store.plans[0].state == .paused)
            try scheduler.poll(available: true)
            #expect(scheduler.notice != nil)
            try store.reassignEntry(id: planned.id, taskName: "Changed")
            try scheduler.reject()
            #expect(store.plans[0].state == .paused)
            try scheduler.poll(available: true)
            #expect(scheduler.notice?.taskID == store.plans[0].taskID)
        }
    }

    @Test func overwriteResizingActivePlanKeepsRecordedIntervalsValid() throws {
        try fixture { store, _, clock, _ in
            let base = clock.now
            try store.createEntry(named: "Earlier", selection: store.prepareEntry(from: base - 300, to: base - 120))
            let planned = try plan(store, from: base - 60, to: base + 300)
            try store.resizeEntry(id: planned.id, edge: .start, to: base - 240, overwriting: true)
            #expect(store.entries[0].end == base - 240)
            #expect(store.runningEntry?.start == base - 240)
            #expect(store.entries.count == 2 && store.activePlan != nil)
        }
    }

    @Test func staleCrossNowDraftCannotCreateASecondRunningEntry() throws {
        try fixture { store, _, clock, _ in
            let base = clock.now
            let selection = try store.prepareEntry(from: base - 60, to: base + 300)
            try store.startTask(named: "Other")
            #expect(throws: TrackingError.overlappingEntry) { try store.createEntry(named: "Draft", selection: selection) }
            #expect(store.entries.count == 1 && store.plans.isEmpty)
        }
    }

    @Test func failedStopRetainsAutomationAndRetriesOriginalEndpoint() throws {
        try fixture { store, scheduler, clock, url in
            let base = clock.now
            try plan(store, from: base - 60, to: base + 120)
            clock.now = base + 111
            try scheduler.poll(available: true)
            let saved = try Data(contentsOf: url)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            clock.now = base + 120
            #expect(throws: (any Error).self) { try scheduler.poll(available: true) }
            #expect(store.activePlan != nil && store.runningEntry != nil)
            try FileManager.default.removeItem(at: url)
            try saved.write(to: url)
            clock.now = base + 125
            try scheduler.poll(available: true)
            #expect(store.runningEntry == nil && store.entries.last?.end == base + 120)
        }
    }

    @Test func futureDraftThatBecomesDueWhileTypingDoesNotBackfill() throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            let selection = try store.prepareEntry(from: base + 60, to: base + 300)
            #expect(selection.startsInFuture)
            clock.now = base + 90
            try store.createEntry(named: "Typed slowly", selection: selection)
            #expect(store.entries.isEmpty && store.plans[0].state == .scheduled)
            try scheduler.poll(available: true)
            #expect(scheduler.notice?.deadline == base + 99)
            clock.now = base + 99
            try scheduler.poll(available: true)
            #expect(store.runningEntry?.start == base + 99)
        }
    }

    @Test func expiredDraftStaysMissedAndCanBeRescheduledWithoutRecording() throws {
        try fixture { store, scheduler, clock, url in
            let base = clock.now
            let selection = try store.prepareEntry(from: base + 60, to: base + 120)
            clock.now = base + 180
            try store.createEntry(named: "Missed draft", selection: selection)
            let id = store.plans[0].id
            #expect(store.plans[0].state == .missed && store.entries.isEmpty)
            try store.reschedulePlan(id: id, start: base + 240, end: base + 300)
            #expect(store.plans[0].state == .scheduled && store.entries.isEmpty)
            #expect(throws: TrackingError.pastPlanStart) { try store.reschedulePlan(id: id, start: base, end: base + 300) }
            try scheduler.poll(available: true)
            #expect(scheduler.notice == nil)
            let data = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            #expect(data["version"] as? Int == 2)
        }
    }

    @Test func futureSnapCannotAccidentallyStartTrackingInThePast() throws {
        try fixture { store, _, clock, _ in
            let base = clock.now
            clock.now += 20
            let selection = try store.prepareEntry(from: base + 21, to: base + 90)
            #expect(selection.startsInFuture && selection.start >= clock.now)
            clock.now += 5
            try store.createEntry(named: "Still planned", selection: selection)
            #expect(store.runningEntry == nil && store.entries.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func resizingRecordedEndIntoFuturePreservesIdentityAndStopsLater(wasRunning: Bool) throws {
        try fixture { store, scheduler, clock, _ in
            let base = clock.now
            try store.startTask(named: "Existing")
            let id = store.runningEntry!.id
            clock.now = base + 60
            if !wasRunning { try store.stop() }
            clock.now = base + 120
            let preview = try store.prepareResize(id: id, edge: .end, to: base + 600)
            #expect(preview.end == base + 600 && store.plans.isEmpty)
            try store.resizeEntry(id: id, edge: .end, to: base + 600)
            #expect(store.runningEntry?.id == id && store.runningEntry?.start == base)
            #expect(store.entries.count == 1 && store.activePlan?.end == base + 600)
            clock.now = base + 600
            try scheduler.poll(available: true)
            #expect(store.runningEntry == nil && store.entries[0].end == base + 600)
        }
    }

    @Test func nowSnapRemovesEndpointFromRecordOrPlannedHandle() throws {
        try fixture { store, _, clock, _ in
            let base = clock.now
            try store.startTask(named: "Existing")
            let id = store.runningEntry!.id
            clock.now = base + 120
            try store.resizeEntry(id: id, edge: .end, to: base + 600)
            try store.resizeEntry(id: id, edge: .end, to: base + 660)
            #expect(store.plans.count == 1 && store.activePlan?.end == base + 660)
            let planID = store.activePlan!.id
            #expect(try store.prepareResize(id: planID, edge: .end, to: clock.now + 1, reachesNow: true).end == nil)
            try store.resizeEntry(id: planID, edge: .end, to: clock.now + 1, reachesNow: true)
            #expect(store.runningEntry?.id == id && store.activePlan == nil)
            try store.resizeEntry(id: id, edge: .end, to: base + 720)
            #expect(try store.prepareResize(id: id, edge: .end, to: clock.now - 1, reachesNow: true).end == nil)
            try store.resizeEntry(id: id, edge: .end, to: clock.now - 1, reachesNow: true)
            #expect(store.runningEntry?.id == id && store.activePlan == nil)
        }
    }

    @Test func futureResizeClampsAtPlansAndCommandReplacesThem() throws {
        try fixture { store, _, clock, _ in
            let base = clock.now
            try store.startTask(named: "Current")
            let id = store.runningEntry!.id
            clock.now = base + 120
            try plan(store, from: base + 600, to: base + 900, name: "Later")
            #expect(try store.prepareResize(id: id, edge: .end, to: base + 720).end == base + 600)
            try store.resizeEntry(id: id, edge: .end, to: base + 720)
            #expect(store.activePlan?.end == base + 600)
            try store.resizeEntry(id: id, edge: .end, to: base + 780, overwriting: true)
            #expect(store.activePlan?.end == base + 780 && store.entries.count == 1)
            #expect(store.plans.contains { $0.start == base + 780 && $0.end == base + 900 && $0.state == .scheduled })
        }
    }

    @Test func commandFutureResizeReplacesRunningNeighborWithoutFutureRecords() throws {
        try fixture { store, _, clock, _ in
            let base = clock.now
            try store.startTask(named: "First")
            let firstID = store.runningEntry!.id
            clock.now = base + 60
            try store.startTask(named: "Second")
            clock.now = base + 120
            #expect(try store.prepareResize(id: firstID, edge: .end, to: base + 600).end == base + 60)
            try store.resizeEntry(id: firstID, edge: .end, to: base + 600, overwriting: true)
            #expect(store.entries.count == 1 && store.runningEntry?.id == firstID)
            #expect(store.activePlan?.end == base + 600)
            #expect(store.entries.allSatisfy { $0.start <= clock.now && ($0.end ?? clock.now) <= clock.now })
        }
    }

    @Test func failedFutureResizeDoesNotReopenEntryOrCreatePlan() throws {
        try fixture { store, _, clock, url in
            let base = clock.now
            try store.startTask(named: "Existing")
            clock.now = base + 60
            try store.stop()
            let original = store.entries
            let data = try Data(contentsOf: url)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            clock.now = base + 120
            #expect(throws: (any Error).self) { try store.resizeEntry(id: original[0].id, edge: .end, to: base + 600) }
            #expect(store.entries == original && store.plans.isEmpty)
            try FileManager.default.removeItem(at: url)
            try data.write(to: url)
        }
    }

}
