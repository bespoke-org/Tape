import Foundation
import Testing
import LineCore

@MainActor
struct TrackingInterruptionTests {
    @Test(arguments: [false, true])
    func lockAndSleepMustBothEndBeforeReturn(sleepFirst: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        let interruptions = TrackingInterruption(store: store, now: { now })
        try store.startTask(named: "Build")
        let task = store.runningTask
        now += 60
        let first: SystemActivityEvent = sleepFirst ? .willSleep : .locked
        let second: SystemActivityEvent = sleepFirst ? .locked : .willSleep
        try interruptions.handle(first)
        now += 60
        try interruptions.handle(first)
        try interruptions.handle(second)
        try interruptions.handle(second)
        #expect(store.entries.count == 1 && store.entries[0].end == base + 60)
        #expect(interruptions.interruptedTask == task)
        now += 3_600
        // Test both wake-while-locked and unlock-before-wake.
        try interruptions.handle(sleepFirst ? .didWake : .unlocked)
        try interruptions.handle(sleepFirst ? .didWake : .unlocked)
        #expect(!interruptions.isAvailable)
        try interruptions.handle(sleepFirst ? .unlocked : .didWake)
        #expect(interruptions.isAvailable)
        #expect(store.runningEntry == nil && store.entries[0].end == base + 60)
    }

    @Test func idleAndAlreadyStoppedTasksDoNotBecomeContinuationCandidates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        let interruptions = TrackingInterruption(store: store, now: { now })
        try interruptions.handle(.locked)
        try interruptions.handle(.unlocked)
        #expect(store.entries.isEmpty && interruptions.interruptedTask == nil)
        try store.startTask(named: "Build")
        now += 60
        try interruptions.handle(.willSleep)
        try interruptions.handle(.didWake)
        #expect(interruptions.interruptedTask != nil)
        // A later idle interruption must not resume a task left over from the last break.
        try interruptions.handle(.locked)
        #expect(interruptions.interruptedTask == nil)
        try interruptions.handle(.unlocked)
        #expect(store.entries.count == 1 && store.runningEntry == nil)
    }

    @Test func failedStopRetriesTheOriginalBoundaryAfterReturning() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("data")
        let moved = directory.appendingPathComponent("saved-data")
        let url = parent.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: url, now: { now })
        let interruptions = TrackingInterruption(store: store, now: { now })
        try store.startTask(named: "Build")
        let original = store.entries
        now = base + 5
        try store.checkpoint()
        try FileManager.default.moveItem(at: parent, to: moved)
        try Data("not a directory".utf8).write(to: parent)
        now = base + 10
        #expect(throws: (any Error).self) { try interruptions.handle(.willSleep) }
        #expect(store.entries == original)
        now = base + 3_600
        #expect(throws: (any Error).self) { try interruptions.handle(.didWake) }
        #expect(!interruptions.isAvailable)
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: moved, to: parent)
        try interruptions.retryStop()
        #expect(interruptions.isAvailable)
        #expect(store.runningEntry == nil)
        #expect(store.entries[0].end == base + 10)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries == store.entries)
    }

    @Test func lockStopsAtTheInterruptionAndUnlockDoesNotResume() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: url, now: { now })
        let interruptions = TrackingInterruption(store: store, now: { now })
        try store.startTask(named: "Build")
        let task = try #require(store.runningTask)
        now = base + 42.5
        try interruptions.handle(.locked)
        #expect(store.runningEntry == nil)
        #expect(store.entries[0].end == base + 42.5)
        #expect(interruptions.interruptedTask == task)
        #expect(!interruptions.isAvailable)
        now = base + 3_600
        try interruptions.handle(.unlocked)
        #expect(interruptions.isAvailable)
        #expect(store.entries.count == 1 && store.runningEntry == nil)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries == store.entries)
        #expect(TrackingInterruption(store: reopened).interruptedTask == nil)
    }
}
