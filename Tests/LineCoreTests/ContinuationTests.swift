import Foundation
import Testing
import LineCore

@MainActor
struct ContinuationTests {
    @Test(arguments: [0, 30, 45, 60, 600, 3600], [-1.0, 0.0, 1.0])
    func configuredShortBreakThresholdUsesStrictBoundary(seconds: Int, offset: Double) throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.store.setShortBreakSeconds(seconds)
        let gap = max(0, Double(seconds) + offset)
        try fixture.offer(breakSeconds: gap)
        let original = try #require(fixture.store.entries.first)
        let returnedAt = fixture.clock.now
        fixture.advance(9)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        let merges = gap < Double(seconds)
        #expect(fixture.store.entries.count == (merges ? 1 : 2))
        #expect(fixture.store.runningEntry?.start == (merges ? original.start : returnedAt))
    }

    @Test func thresholdChangeDoesNotAlterAnExistingOffer() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer(breakSeconds: 60)
        let originalID = fixture.store.entries.first?.id
        try fixture.store.setShortBreakSeconds(0)
        fixture.advance(1)
        try fixture.interruptions.acceptContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry?.id == originalID)
        fixture.advance(60)
        try fixture.interruptions.handle(.locked)
        fixture.advance(1)
        try fixture.interruptions.handle(.unlocked)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        fixture.advance(9)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.entries.count == 2)
    }

    @Test func disablingResumeStillStopsAndDoesNotReviveOldOffers() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.interruptions.setAutomaticResumeEnabled(false)
        try fixture.offer()
        #expect(fixture.store.runningEntry == nil)
        #expect(fixture.store.entries.first?.end != nil)
        #expect(fixture.interruptions.pendingContinuation == nil)
        #expect(!fixture.interruptions.needsContinuationPolling)
        try fixture.interruptions.setAutomaticResumeEnabled(true)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.interruptions.pendingContinuation == nil)
        try fixture.offer()
        #expect(fixture.interruptions.pendingContinuation != nil)
        fixture.interruptions.setContinuationHovered(true)
        try fixture.interruptions.setAutomaticResumeEnabled(false)
        try fixture.interruptions.setAutomaticResumeEnabled(true)
        fixture.advance(100)
        try fixture.interruptions.acceptContinuation(sessionIsUsable: true)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.interruptions.pendingContinuation == nil)
        #expect(fixture.store.runningEntry == nil)
    }

    @Test func failedDisablePreservesPendingContinuation() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer()
        let pending = fixture.interruptions.pendingContinuation
        let url = fixture.directory.appendingPathComponent("data/tracking.json")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try fixture.interruptions.setAutomaticResumeEnabled(false) }
        #expect(fixture.store.automaticResumeEnabled)
        #expect(fixture.interruptions.pendingContinuation == pending)
    }

    @Test func disabledResumeStillRetriesFailedStopAtOriginalTime() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.interruptions.setAutomaticResumeEnabled(false)
        try fixture.store.startTask(named: "Build")
        fixture.advance(60)
        let stopTime = fixture.clock.now
        let url = fixture.directory.appendingPathComponent("data/tracking.json")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try fixture.interruptions.handle(.locked) }
        fixture.advance(600)
        #expect(throws: (any Error).self) { try fixture.interruptions.handle(.unlocked) }
        #expect(fixture.interruptions.needsContinuationPolling)
        try FileManager.default.removeItem(at: url)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.entries.first?.end == stopTime)
        #expect(fixture.store.runningEntry == nil && fixture.interruptions.pendingContinuation == nil)
        #expect(!fixture.interruptions.needsContinuationPolling)
    }

    @Test(arguments: [1, 9, 60])
    func configuredCountdownResumesAtItsDeadline(seconds: Int) throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.store.setResumeCountdownSeconds(seconds)
        try fixture.offer()
        let returnedAt = fixture.clock.now
        #expect(fixture.interruptions.remainingSeconds == seconds)
        fixture.advance(Double(seconds) - 0.25)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry == nil)
        fixture.advance(0.25)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry?.start == returnedAt)
        #expect(fixture.interruptions.pendingContinuation == nil)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.entries.count == 2)
    }

    @Test func changedDurationAppliesToNextOfferAndPreservesPausedCountdown() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.store.setResumeCountdownSeconds(15)
        try fixture.offer()
        fixture.advance(2)
        fixture.interruptions.setContinuationHovered(true)
        try fixture.store.setResumeCountdownSeconds(30)
        fixture.advance(100)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.interruptions.remainingSeconds == 13)
        fixture.interruptions.setContinuationHovered(false)
        fixture.advance(12)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.interruptions.remainingSeconds == 1)
        #expect(fixture.store.runningEntry == nil)
        try fixture.interruptions.handle(.locked)
        fixture.advance(60)
        try fixture.interruptions.handle(.unlocked)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.interruptions.remainingSeconds == 30)
        fixture.advance(30)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry?.start == fixture.clock.now - 30)
    }

    @Test func hoveringPausesAndResumesTheExactRemainingTime() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer()
        let pending = try #require(fixture.interruptions.pendingContinuation)
        fixture.advance(2.25)
        fixture.interruptions.setContinuationHovered(true)
        fixture.advance(30)
        fixture.interruptions.setContinuationHovered(true)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry == nil)
        #expect(fixture.interruptions.remainingSeconds == 7)
        fixture.interruptions.setContinuationHovered(false)
        fixture.advance(6.5)
        fixture.interruptions.setContinuationHovered(false)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry == nil)
        #expect(fixture.interruptions.remainingSeconds == 1)
        fixture.advance(0.25)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry?.start == pending.returnedAt)
        #expect(fixture.interruptions.pendingContinuation == nil)
    }

    @Test(arguments: [299.0, 300.0, 301.0], [false, true])
    func shortBreakContinuesTheOriginalEntry(breakSeconds: Double, waitsForCountdown: Bool) throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.store.startTask(named: "Build")
        let original = try #require(fixture.store.runningEntry)
        fixture.advance(60)
        try fixture.interruptions.handle(.locked)
        fixture.advance(breakSeconds)
        try fixture.interruptions.handle(.unlocked)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        let returnedAt = fixture.clock.now
        fixture.advance(waitsForCountdown ? 10 : 1)
        if waitsForCountdown {
            try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        } else {
            try fixture.interruptions.acceptContinuation(sessionIsUsable: true)
        }
        let running = try #require(fixture.store.runningEntry)
        if breakSeconds < 300 {
            #expect(running.id == original.id)
            #expect(running.start == original.start)
            #expect(fixture.store.entries.count == 1)
        } else {
            #expect(running.id != original.id)
            #expect(running.start == returnedAt)
            #expect(fixture.store.entries.count == 2)
        }
        let reopened = try TrackingStore(url: fixture.directory.appendingPathComponent("data/tracking.json"),
                                         now: { fixture.clock.now + 100 })
        #expect(reopened.entries.last?.id == running.id)
        #expect(reopened.entries.last?.start == running.start)
        #expect(reopened.entries.last?.end == fixture.clock.now)
    }

    @Test func acceptingEarlyResumesFromReturnAndCannotCommitTwice() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer()
        let pending = try #require(fixture.interruptions.pendingContinuation)
        fixture.interruptions.setContinuationHovered(true)
        fixture.advance(2)
        try fixture.interruptions.acceptContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry?.start == pending.returnedAt)
        #expect(fixture.store.runningTask == pending.task)
        #expect(fixture.interruptions.pendingContinuation == nil)
        let accepted = fixture.store.entries
        try fixture.interruptions.acceptContinuation(sessionIsUsable: true)
        fixture.advance(10)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.entries == accepted)
    }

    @Test(arguments: [120.0, 600.0])
    func rejectionAndRestartDiscardProvisionalTime(breakSeconds: Double) throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer(breakSeconds: breakSeconds)
        let before = fixture.store.entries
        let reopened = try TrackingStore(url: fixture.directory.appendingPathComponent("data/tracking.json"),
                                         now: { fixture.clock.now })
        let restarted = TrackingInterruption(store: reopened)
        try restarted.handle(.unlocked)
        try restarted.pollContinuation(sessionIsUsable: true)
        #expect(restarted.pendingContinuation == nil && reopened.entries == before)
        fixture.interruptions.setContinuationHovered(true)
        fixture.advance(10)
        fixture.interruptions.cancelContinuation()
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        try fixture.interruptions.handle(.locked)
        try fixture.interruptions.handle(.unlocked)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.entries == before)
        #expect(fixture.interruptions.pendingContinuation == nil)
    }

    @Test func unavailableSessionDiscardsCountdownAndWallClockDoesNotExpireIt() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer()
        let initial = try #require(fixture.interruptions.pendingContinuation)
        fixture.clock.now += 3_600
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry == nil && fixture.interruptions.remainingSeconds == 9)
        fixture.interruptions.setContinuationHovered(true)
        fixture.advance(10)
        try fixture.interruptions.pollContinuation(sessionIsUsable: false)
        #expect(fixture.store.runningEntry == nil && fixture.interruptions.pendingContinuation == nil)
        fixture.advance(100)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        let fresh = try #require(fixture.interruptions.pendingContinuation)
        #expect(fresh.id != initial.id && fresh.returnedAt == fixture.clock.now)
        #expect(fixture.interruptions.remainingSeconds == 9)
        fixture.advance(10)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.runningEntry?.start == fresh.returnedAt)
    }

    @Test func completionRechecksOverlapsAndDoesNotReplaceManualWork() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer()
        fixture.advance(2)
        try fixture.store.startTask(named: "Manual task")
        let before = fixture.store.entries
        fixture.advance(10)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.entries == before && fixture.store.runningTask?.name == "Manual task")
        #expect(fixture.interruptions.pendingContinuation == nil)
        try fixture.interruptions.handle(.locked)
        fixture.advance(100)
        try fixture.interruptions.handle(.unlocked)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        fixture.advance(2)
        try fixture.store.startTask(named: "Conflict")
        fixture.advance(2)
        try fixture.store.stop()
        let conflict = fixture.store.entries
        fixture.advance(10)
        #expect(throws: TrackingError.overlappingEntry) {
            try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        }
        #expect(fixture.store.entries == conflict && fixture.interruptions.pendingContinuation == nil)
    }

    @Test(arguments: [120.0, 600.0])
    func failedCompletionAndClockReversalDoNotRetryLater(breakSeconds: Double) throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer(breakSeconds: breakSeconds)
        let before = fixture.store.entries
        let parent = fixture.directory.appendingPathComponent("data")
        let moved = fixture.directory.appendingPathComponent("saved-data")
        try FileManager.default.moveItem(at: parent, to: moved)
        try Data("not a directory".utf8).write(to: parent)
        fixture.advance(10)
        #expect(throws: (any Error).self) { try fixture.interruptions.pollContinuation(sessionIsUsable: true) }
        #expect(fixture.store.entries == before && fixture.interruptions.pendingContinuation == nil)
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: moved, to: parent)
        fixture.advance(100)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.entries == before)
        try fixture.offer(breakSeconds: breakSeconds)
        let saved = fixture.store.entries
        fixture.clock.now -= 20
        fixture.clock.uptime += 10
        #expect(throws: (any Error).self) { try fixture.interruptions.pollContinuation(sessionIsUsable: true) }
        #expect(fixture.store.entries == saved && fixture.interruptions.pendingContinuation == nil)
    }

    @Test func relockingDuringCountdownDiscardsItAndOffersAFreshCountdown() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer()
        let first = try #require(fixture.interruptions.pendingContinuation)
        fixture.interruptions.setContinuationHovered(true)
        fixture.advance(4)
        try fixture.interruptions.handle(.locked)
        #expect(fixture.interruptions.pendingContinuation == nil)
        fixture.advance(100)
        try fixture.interruptions.handle(.willSleep)
        try fixture.interruptions.handle(.didWake)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.interruptions.pendingContinuation == nil)
        try fixture.interruptions.handle(.unlocked)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        let second = try #require(fixture.interruptions.pendingContinuation)
        #expect(second.id != first.id && second.returnedAt == fixture.clock.now)
        #expect(second.task == first.task)
        fixture.advance(10)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        #expect(fixture.store.entries.count == 2)
        #expect(fixture.store.runningEntry?.start == second.returnedAt)
    }

    @Test func countdownIncludesReturnTimeAndCompletesOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        var uptime = 100.0
        let store = try TrackingStore(url: url, now: { now })
        let interruptions = TrackingInterruption(store: store, now: { now }, uptime: { uptime })
        try store.startTask(named: "Build")
        let task = try #require(store.runningTask)
        now += 60
        try interruptions.handle(.locked)
        now += 600
        try interruptions.handle(.unlocked)
        try interruptions.pollContinuation(sessionIsUsable: true)
        let pending = try #require(interruptions.pendingContinuation)
        #expect(pending.returnedAt == base + 660)
        #expect(interruptions.remainingSeconds == 9)
        #expect(store.runningEntry == nil)
        now += 8
        uptime += 8
        try interruptions.handle(.unlocked)
        try interruptions.pollContinuation(sessionIsUsable: true)
        #expect(interruptions.pendingContinuation?.id == pending.id)
        #expect(store.entries.count == 1 && store.runningEntry == nil)
        now += 1
        uptime += 1
        try interruptions.pollContinuation(sessionIsUsable: true)
        #expect(store.runningTask == task)
        #expect(store.runningEntry?.start == base + 660)
        #expect(store.entries.count == 2)
        #expect(interruptions.pendingContinuation == nil)
        try interruptions.pollContinuation(sessionIsUsable: true)
        #expect(store.entries.count == 2)
        let reopened = try TrackingStore(url: url, now: { now + 100 })
        #expect(reopened.runningEntry == nil)
        #expect(reopened.entries.last?.start == base + 660)
        #expect(reopened.entries.last?.end == base + 669)
    }
}

@MainActor
private final class ContinuationFixture {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var uptime = 100.0
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let clock = Clock()
    let store: TrackingStore
    let interruptions: TrackingInterruption

    init() throws {
        let clock = self.clock
        store = try TrackingStore(url: directory.appendingPathComponent("data/tracking.json"), now: { clock.now })
        interruptions = TrackingInterruption(store: store, now: { clock.now }, uptime: { clock.uptime })
    }

    func advance(_ seconds: Double) {
        clock.now += seconds
        clock.uptime += seconds
    }

    func offer(breakSeconds: Double = 600) throws {
        try store.startTask(named: "Build")
        advance(60)
        try interruptions.handle(.locked)
        advance(breakSeconds)
        try interruptions.handle(.unlocked)
        try interruptions.pollContinuation(sessionIsUsable: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
