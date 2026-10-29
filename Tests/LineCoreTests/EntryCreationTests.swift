import Foundation
import Testing
import LineCore

@MainActor
struct EntryCreationTests {
    @Test func drawingUsesChosenSnapWithoutRoundingNeighborBoundariesOrLiveTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base.addingTimeInterval(3_600.25)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        let five = try store.prepareEntry(from: base.addingTimeInterval(161), to: base.addingTimeInterval(1_379), snap: .fiveMinutes)
        #expect(five.start == base.addingTimeInterval(300))
        #expect(five.end == base.addingTimeInterval(1_500))
        let fifteen = try store.prepareEntry(from: base.addingTimeInterval(1_379), to: base.addingTimeInterval(161), snap: .quarterHour)
        #expect(fifteen.start == base)
        #expect(fifteen.end == base.addingTimeInterval(1_800))
        try store.startTask(named: "Existing")
        let bounded = try store.prepareEntry(from: base.addingTimeInterval(2_000), to: now.addingTimeInterval(60), snap: .quarterHour)
        #expect(bounded.end == base.addingTimeInterval(3_600.25))
        now += 12.5
        try store.stop()
        #expect(store.entries[0].duration(at: now) == 12.5)
        now = base.addingTimeInterval(5_000.25)
        let running = try store.prepareEntry(from: base.addingTimeInterval(4_600), to: now, snap: .quarterHour)
        #expect(running.start == base.addingTimeInterval(4_500))
        #expect(running.end == nil)
    }

    @Test func drawingStopsAtTheNearestEntryInEitherDirection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base.addingTimeInterval(600.25)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        try store.startTask(named: "Existing")
        let beforeRunning = try store.prepareEntry(from: base, to: now.addingTimeInterval(60), reachesNow: true)
        #expect(beforeRunning.end == base.addingTimeInterval(600.25))
        #expect(store.runningTask?.name == "Existing")
        now = base.addingTimeInterval(900.75)
        try store.stop()
        now = base.addingTimeInterval(3_600)
        let forward = try store.prepareEntry(from: base.addingTimeInterval(300), to: now, reachesNow: true)
        #expect(forward.start == base.addingTimeInterval(300))
        #expect(forward.end == base.addingTimeInterval(600.25))
        let backward = try store.prepareEntry(from: base.addingTimeInterval(1_200), to: base)
        #expect(backward.start == base.addingTimeInterval(900.75))
        #expect(backward.end == base.addingTimeInterval(1_200))
        try store.createEntry(named: "Before", selection: forward)
        try store.createEntry(named: "After", selection: backward)
        #expect(store.entries.count == 3)
        #expect(store.entries[0].end == store.entries[1].start)
        #expect(store.entries[1].end == store.entries[2].start)
        #expect(store.runningEntry == nil)
    }

    @Test func invalidSelectionsPreserveRecordsWhileAdjacentIntervalsAreAllowed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let now = base.addingTimeInterval(3_600)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        let first = try store.prepareEntry(from: base.addingTimeInterval(600), to: base.addingTimeInterval(1_200))
        let stale = try store.prepareEntry(from: base.addingTimeInterval(900), to: base.addingTimeInterval(1_500))
        try store.createEntry(named: "Read", selection: first)
        #expect(throws: TrackingError.overlappingEntry) { try store.createEntry(named: "Stale", selection: stale) }
        #expect(throws: TrackingError.overlappingEntry) { try store.prepareEntry(from: base.addingTimeInterval(650), to: base.addingTimeInterval(900)) }
        #expect(throws: TrackingError.emptyInterval) { try store.prepareEntry(from: now.addingTimeInterval(1), to: now.addingTimeInterval(5)) }
        #expect(throws: TrackingError.emptyInterval) {
            try store.prepareEntry(from: now.addingTimeInterval(61), to: now.addingTimeInterval(65), snap: .fiveMinutes)
        }
        let future = try store.prepareEntry(from: now.addingTimeInterval(1), to: now.addingTimeInterval(601), snap: .fiveMinutes)
        #expect(future.end == now.addingTimeInterval(600))
        #expect(throws: TrackingError.emptyInterval) { try store.prepareEntry(from: base, to: base) }
        #expect(throws: TrackingError.emptyInterval) { try store.prepareEntry(from: base.addingTimeInterval(1), to: base.addingTimeInterval(2)) }
        let nearNow = try TrackingStore(url: directory.appendingPathComponent("near-now.json"), now: { base.addingTimeInterval(180.25) })
        #expect(throws: TrackingError.emptyInterval) {
            try nearNow.prepareEntry(from: base.addingTimeInterval(175), to: base.addingTimeInterval(180), snap: .fiveMinutes)
        }
        #expect(throws: TrackingError.emptyTaskName) { try store.createEntry(named: " \n ", selection: stale) }
        #expect(store.entries.count == 1 && store.tasks.count == 1)
        let adjacent = try store.prepareEntry(from: base, to: base.addingTimeInterval(600))
        try store.createEntry(named: "Read", selection: adjacent)
        #expect(store.entries[0].end == store.entries[1].start)
        #expect(store.entries(overlapping: DateInterval(start: base, duration: 600), now: now).count == 1)
    }

    @Test func historicalInsertionPreservesRunningCheckpointAndFailedSaveCreatesNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("data")
        let moved = directory.appendingPathComponent("saved")
        let url = parent.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base.addingTimeInterval(3_600.25)
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Live")
        now += 5
        try store.checkpoint()
        now += 20
        let past = try store.prepareEntry(from: base, to: base.addingTimeInterval(600))
        try store.createEntry(named: "Past", selection: past)
        let draft = try store.prepareEntry(from: base.addingTimeInterval(600), to: base.addingTimeInterval(900))
        let before = store.entries
        try FileManager.default.moveItem(at: parent, to: moved)
        try Data("not a directory".utf8).write(to: parent)
        #expect(throws: (any Error).self) { try store.createEntry(named: "Unsaved", selection: draft) }
        #expect(store.entries == before && store.tasks.count == 2)
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: moved, to: parent)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries.count == 2)
        #expect(reopened.entries.last?.end == base.addingTimeInterval(3_605.25))
    }

    @Test func commitRechecksOverlapWhenATaskStartsDuringSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base.addingTimeInterval(600)
        let url = directory.appendingPathComponent("tracking.json")
        let store = try TrackingStore(url: url, now: { now })
        let draft = try store.prepareEntry(from: base, to: now.addingTimeInterval(60), reachesNow: true)
        now += 60
        try store.startTask(named: "Other work")
        let before = store.entries
        #expect(throws: TrackingError.overlappingEntry) { try store.createEntry(named: "Draft", selection: draft) }
        #expect(store.entries == before)
        #expect(store.tasks.count == 1)
        #expect(store.runningTask?.name == "Other work")
    }

    @Test func drawingThroughNowIncludesTaskPickerTimeAndRecoversAtCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base.addingTimeInterval(125.25)
        let store = try TrackingStore(url: url, now: { now })
        let selection = try store.prepareEntry(from: base.addingTimeInterval(10), to: now)
        #expect(selection.start == base)
        #expect(selection.end == nil)
        #expect(store.entries.isEmpty && store.tasks.isEmpty)
        now += 90.5
        try store.createEntry(named: "Build", selection: selection)
        #expect(store.runningEntry?.start == base)
        #expect(store.runningEntry?.duration(at: now) == 215.75)
        now += 3_600
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.runningEntry == nil)
        #expect(reopened.entries.first?.end == base.addingTimeInterval(215.75))
    }

    @Test func reverseHistoricalSelectionSnapsReusesTaskAndSurvivesReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base.addingTimeInterval(3_600.25)
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Read")
        now += 12.5
        try store.stop()
        let task = try #require(store.tasks.first)
        let selection = try store.prepareEntry(from: base.addingTimeInterval(1_219), to: base.addingTimeInterval(311))
        #expect(selection.start == base.addingTimeInterval(300))
        #expect(selection.end == base.addingTimeInterval(1_200))
        #expect(store.entries.count == 1)
        try store.createEntry(named: " read ", selection: selection)
        #expect(store.entries.count == 2)
        #expect(store.entries[0].duration(at: now) == 900)
        #expect(store.entries[0].taskID == task.id)
        #expect(store.entries[1].duration(at: now) == 12.5)
        #expect(store.tasks == [task])
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries == store.entries)
        #expect(reopened.tasks == store.tasks)
    }
}
