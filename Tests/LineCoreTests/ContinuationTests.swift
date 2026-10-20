import Foundation
import Testing
import LineCore

@MainActor
struct ContinuationTests {
    @Test func rejectionAndRestartDiscardProvisionalTime() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer()
        let before = fixture.store.entries
        let reopened = try TrackingStore(url: fixture.directory.appendingPathComponent("data/tracking.json"),
                                         now: { fixture.clock.now })
        let restarted = TrackingInterruption(store: reopened)
        try restarted.handle(.unlocked)
        try restarted.pollContinuation(sessionIsUsable: true)
        #expect(restarted.pendingContinuation == nil && reopened.entries == before)
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
        #expect(fixture.store.runningEntry == nil && fixture.interruptions.remainingSeconds == 10)
        fixture.advance(10)
        try fixture.interruptions.pollContinuation(sessionIsUsable: false)
        #expect(fixture.store.runningEntry == nil && fixture.interruptions.pendingContinuation == nil)
        fixture.advance(100)
        try fixture.interruptions.pollContinuation(sessionIsUsable: true)
        let fresh = try #require(fixture.interruptions.pendingContinuation)
        #expect(fresh.id != initial.id && fresh.returnedAt == fixture.clock.now)
        #expect(fixture.interruptions.remainingSeconds == 10)
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

    @Test func failedCompletionAndClockReversalDoNotRetryLater() throws {
        let fixture = try ContinuationFixture()
        defer { fixture.cleanup() }
        try fixture.offer()
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
        try fixture.offer()
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
        #expect(interruptions.remainingSeconds == 10)
        #expect(store.runningEntry == nil)
        now += 9
        uptime += 9
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
        #expect(reopened.entries.last?.end == base + 670)
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

    func offer() throws {
        try store.startTask(named: "Build")
        advance(60)
        try interruptions.handle(.locked)
        advance(600)
        try interruptions.handle(.unlocked)
        try interruptions.pollContinuation(sessionIsUsable: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
