import Foundation
import Testing
import LineCore

@MainActor
struct TrackingStoreTests {
    @Test func visibleRangeIncludesSpanningEntriesButExcludesTouchingEndpoints() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        try store.startTask(named: "First")
        now += 60
        try store.startTask(named: "Second")
        now += 60
        try store.startTask(named: "Third")
        now += 60
        let range = DateInterval(start: base.addingTimeInterval(60), duration: 60)
        let visible = store.entries(overlapping: range, now: now)
        #expect(visible.count == 1)
        #expect(store.task(id: visible.first!.taskID)?.name == "Second")
        #expect(store.entries(overlapping: DateInterval(start: base.addingTimeInterval(130), duration: 10), now: now).count == 1)
        #expect(store.entries(overlapping: DateInterval(start: now, duration: 60), now: now).isEmpty)
    }
    @Test func zoomSurvivesReopeningOldStoresWithoutChangingRecoveryTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        try Data(#"{"version":1,"tasks":[],"entries":[]}"#.utf8).write(to: url)
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        #expect(store.timelineSpan == 14_400)
        try store.startTask(named: "Read")
        now += 5
        try store.checkpoint()
        now += 10
        try store.setTimelineSpan(7_200)
        now += 3_600
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.timelineSpan == 7_200)
        #expect(reopened.entries.first?.duration(at: now) == 5)
        #expect(reopened.runningTask == nil)
    }
    @Test func recoveryDropsAnEntryThatNeverReachedItsFirstCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Read")
        now += 3_600
        let recovered = try TrackingStore(url: url, now: { now })
        #expect(recovered.entries.isEmpty)
        #expect(recovered.tasks.count == 1)
        #expect(recovered.runningTask == nil)
    }

    @Test func runningEntryGrowsThenStopsAtItsActualTimestamp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_800_000_000.25)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        try store.startTask(named: "Build Line")
        now += 12.5
        #expect(store.runningEntry?.duration(at: now) == 12.5)
        now += 47.25
        #expect(store.runningEntry?.duration(at: now) == 59.75)
        try store.stop()
        now += 120
        #expect(store.entries.first?.duration(at: now) == 59.75)
        #expect(store.entries.first?.end == Date(timeIntervalSince1970: 1_800_000_060))
    }

    @Test func refusesUnknownStoreVersionWithoutOverwritingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        let original = Data(#"{"version":99,"tasks":[],"entries":[]}"#.utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) { try TrackingStore(url: url) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func failedSavePreservesPreviouslySavedAndVisibleWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("data")
        let moved = directory.appendingPathComponent("saved-data")
        let url = parent.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Read")
        now += 5
        try store.checkpoint()
        let before = store.entries
        try FileManager.default.moveItem(at: parent, to: moved)
        try Data("not a directory".utf8).write(to: parent)
        now += 10
        #expect(throws: (any Error).self) { try store.startTask(named: "Build Line") }
        #expect(store.entries == before)
        #expect(store.tasks.count == 1)
        #expect(store.runningTask?.name == "Read")
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: moved, to: parent)
        let recovered = try TrackingStore(url: url, now: { now })
        #expect(recovered.entries.first?.end == Date(timeIntervalSince1970: 1_800_000_005))
        #expect(recovered.tasks.count == 1)
    }

    @Test func rejectsClockReversalWithoutOverlappingEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Build Line")
        now += 10
        try store.checkpoint()
        now -= 20
        #expect(throws: (any Error).self) { try store.checkpoint() }
        #expect(throws: (any Error).self) { try store.startTask(named: "Read") }
        #expect(throws: (any Error).self) { try store.stop() }
        #expect(store.tasks.count == 1)
        #expect(store.entries.count == 1)
        let recovered = try TrackingStore(url: url, now: { now })
        #expect(recovered.entries.first?.end == Date(timeIntervalSince1970: 1_800_000_010))
    }

    @Test func recoveryStopsAtCheckpointAndNeverCountsTheAbsence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Build Line")
        now += 5
        try store.checkpoint()
        now += 3_600

        let recovered = try TrackingStore(url: url, now: { now })
        #expect(recovered.runningEntry == nil)
        #expect(recovered.entries.count == 1)
        #expect(recovered.entries.first?.end == Date(timeIntervalSince1970: 1_800_000_005))
        #expect(recovered.entries.first?.duration(at: now) == 5)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries == recovered.entries)
        #expect(reopened.runningTask == nil)
    }

    @Test func rejectsEmptyTaskWithoutChangingRunningWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"))
        try store.startTask(named: "Read")
        let before = store.entries
        #expect(throws: (any Error).self) { try store.startTask(named: " \n\t ") }
        #expect(store.entries == before)
        #expect(store.tasks.count == 1)
    }

    @Test func tracksAndReusesTasksAcrossSwitchesAndRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })

        try store.startTask(named: "  Build Line  ")
        let firstTask = try #require(store.runningTask)
        #expect(firstTask.name == "Build Line")
        now += 60
        try store.startTask(named: "BUILD LINE")
        #expect(store.tasks.count == 1)
        #expect(store.entries.count == 1)

        now += 60
        try store.startTask(named: "Read")
        #expect(store.entries.count == 2)
        #expect(store.entries[0].end == Date(timeIntervalSince1970: 1_800_000_120))
        #expect(store.entries[1].start == store.entries[0].end)
        now += 30
        try store.stop()
        #expect(store.runningTask == nil)
        #expect(store.entries[1].end == Date(timeIntervalSince1970: 1_800_000_150))

        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.tasks == store.tasks)
        #expect(reopened.entries == store.entries)
        #expect(reopened.runningTask == nil)
        now += 86_400
        try reopened.startTask(named: "build line")
        #expect(reopened.runningTask?.id == firstTask.id)
        #expect(reopened.runningTask?.color == firstTask.color)
        #expect(reopened.entries.count == 3)
    }
}
