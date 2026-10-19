import Foundation
import Testing
import LineCore

@MainActor
struct EntryOverwriteTests {
    @Test func overwriteBridgesSameTaskNeighborsWithoutMergingUnrelatedHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { base + 3_600 })
        for (start, end) in [(0.0, 60.0), (60, 120), (600, 900), (900, 1_200), (1_800, 2_100), (2_100, 2_400), (2_460, 2_520)] {
            try store.createEntry(named: "Build", selection: store.prepareEntry(from: base + start, to: base + end))
        }
        try store.createEntry(named: "Read", selection: store.prepareEntry(from: base + 2_400, to: base + 2_460))
        let before = store.entries
        #expect(before.count == 8) // Ordinary creation retains separate entries.
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base + 1_200, to: base + 1_800, overwriting: true))
        #expect(store.entries.count == 5)
        #expect(store.entries[2].start == base + 600 && store.entries[2].end == base + 2_400)
        #expect(Array(store.entries.prefix(2)) == Array(before.prefix(2)))
        #expect(Array(store.entries.suffix(2)) == Array(before.suffix(2)))
    }

    @Test(arguments: [false, true])
    func sameTaskOverwriteKeepsOneRunningEntryAndRecoversAtCheckpoint(throughNow: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 300
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Build")
        let task = try #require(store.runningTask)
        now = base + 900
        let draft = try store.prepareEntry(from: base + 420, to: throughNow ? now : base + 600, overwriting: true)
        now += 90.25 // Include time spent choosing the same task.
        try store.createEntry(named: "Build", selection: draft)
        #expect(store.entries.count == 1)
        #expect(store.runningEntry?.start == base + 300 && store.runningTask == task)
        now += 3_600
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries.count == 1 && reopened.runningEntry == nil)
        #expect(reopened.entries[0].start == base + 300 && reopened.entries[0].end == base + 990.25)
    }

    @Test func mergingIntoATouchingRunningEntryPreservesItsSavedCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 1_800
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Build")
        now += 5
        try store.checkpoint()
        now = base + 2_000
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base + 1_200, to: base + 1_800, overwriting: true))
        #expect(store.entries.count == 1 && store.runningEntry?.start == base + 1_200)
        now += 3_600
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries.count == 1 && reopened.entries[0].end == base + 1_805)
    }

    @Test func sameTaskOverwriteMergesInsideExtensionsAndTouchingIntervals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { base + 3_600 })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base + 600, to: base + 1_200))
        let task = try #require(store.tasks.first)
        for (from, to, expectedStart, expectedEnd) in [
            (780.0, 960.0, 600.0, 1_200.0), // Inside: keep the original interval.
            (900, 1_500, 600, 1_500),       // Extend the right edge.
            (600, 300, 300, 1_500),        // Extend left with a reverse drag.
            (1_500, 1_800, 300, 1_800),    // Touch the right edge.
            (300, 0, 0, 1_800)            // Touch the left edge.
        ] {
            let draft = try store.prepareEntry(from: base + from, to: base + to, overwriting: true)
            try store.createEntry(named: " build ", selection: draft)
            try #require(store.entries.count == 1)
            #expect(store.entries[0].start == base + expectedStart)
            #expect(store.entries[0].end == base + expectedEnd)
            #expect(store.entries[0].taskID == task.id && store.tasks == [task])
        }
        let reopened = try TrackingStore(url: url)
        #expect(reopened.entries == store.entries && reopened.tasks == [task])
    }

    @Test func overwriteKeepsTasksUsedElsewhereOrChosenForTheReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { base + 3_600 })
        try store.createEntry(named: "Original", selection: store.prepareEntry(from: base, to: base + 600))
        try store.createEntry(named: "Original", selection: store.prepareEntry(from: base + 1_200, to: base + 1_800))
        let original = try #require(store.tasks.first)
        try store.createEntry(named: "Replacement", selection: store.prepareEntry(from: base, to: base + 600, overwriting: true))
        #expect(store.task(id: original.id) == original)
        try store.createEntry(named: " original ", selection: store.prepareEntry(from: base + 1_200, to: base + 1_800, overwriting: true))
        #expect(store.task(id: original.id) == original)
        #expect(store.entries.last?.taskID == original.id)
        #expect(store.tasks.count == 2)
    }

    @Test func invalidDraftsAndFailedOverwriteLeaveStoredAndRunningStateIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("data")
        let moved = directory.appendingPathComponent("saved")
        let url = parent.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Live")
        now = base + 180
        try store.checkpoint()
        now = base + 300
        let draft = try store.prepareEntry(from: base, to: now, overwriting: true)
        let entries = store.entries
        let tasks = store.tasks
        #expect(throws: TrackingError.emptyInterval) {
            try store.prepareEntry(from: base + 61, to: base + 62, overwriting: true)
        }
        #expect(throws: TrackingError.futureInterval) {
            try store.prepareEntry(from: now + 60, to: now + 120, overwriting: true)
        }
        #expect(throws: TrackingError.emptyTaskName) { try store.createEntry(named: " ", selection: draft) }
        now = base + 100
        #expect(throws: TrackingError.clockMovedBackwards) { try store.createEntry(named: "Correction", selection: draft) }
        now = base + 300
        try FileManager.default.moveItem(at: parent, to: moved)
        try Data("not a directory".utf8).write(to: parent)
        #expect(throws: (any Error).self) { try store.createEntry(named: "Correction", selection: draft) }
        #expect(store.entries == entries && store.tasks == tasks && store.runningTask?.name == "Live")
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: moved, to: parent)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries.count == 1 && reopened.tasks == tasks)
        #expect(reopened.entries[0].start == base && reopened.entries[0].end == base + 180)
    }

    @Test func throughNowOverwriteRechecksCurrentEntriesAndIncludesPickerTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Original")
        now = base + 600.25
        let draft = try store.prepareEntry(from: base + 120, to: now, overwriting: true)
        #expect(draft.end == nil)
        now += 90.5
        try store.startTask(named: "Intervening")
        now += 30
        try store.createEntry(named: "Replacement", selection: draft)
        #expect(store.entries.count == 2 && store.tasks.count == 2)
        #expect(!store.tasks.contains { $0.name == "Intervening" })
        #expect(store.entries[0].start == base && store.entries[0].end == base + 120)
        #expect(store.runningEntry?.start == base + 120 && store.runningTask?.name == "Replacement")
        #expect(store.runningEntry?.duration(at: now) == 600.75)
        now += 1_000
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries.last?.end == base + 720.75)
        #expect(reopened.runningEntry == nil)
    }

    @Test func reverseOverwriteDeletesOnlyTasksWhoseLastEntryDisappears() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 0.25
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        try store.startTask(named: "First")
        now = base + 600
        try store.startTask(named: "Middle")
        now = base + 1_200
        try store.startTask(named: "Last")
        now = base + 1_800.75
        try store.stop()
        now = base + 3_600
        let before = store.entries
        let draft = try store.prepareEntry(from: base + 1_479, to: base + 311, snap: .fiveMinutes, overwriting: true)
        #expect(draft.start == base + 300 && draft.end == base + 1_500)
        try store.createEntry(named: "Replacement", selection: draft)
        #expect(store.entries.map(\.start) == [base + 0.25, base + 300, base + 1_500])
        #expect(store.entries.map(\.end) == [base + 300, base + 1_500, base + 1_800.75])
        #expect(store.entries[0].id == before[0].id && store.entries[2].id == before[2].id)
        #expect(!store.entries.contains { $0.id == before[1].id })
        #expect(store.tasks.count == 3 && store.task(id: before[1].taskID) == nil)
        #expect(store.task(id: before[0].taskID) != nil && store.task(id: before[2].taskID) != nil)
        let neighbors = [store.entries[0], store.entries[2]]
        let replacementTask = store.entries[1].taskID
        // Replacing the same interval again must leave touching neighbors exactly intact.
        try store.createEntry(named: " replacement ", selection: draft)
        #expect([store.entries[0], store.entries[2]] == neighbors)
        #expect(store.entries[1].taskID == replacementTask && store.tasks.count == 3)
        let reopened = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        #expect(reopened.tasks == store.tasks && reopened.entries == store.entries)
    }

    @Test(arguments: [false, true])
    func historicalOverwriteKeepsRunningTailAndAdvancesItsRecoveryPoint(splitMiddle: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Live")
        now += 5
        try store.checkpoint()
        now = base + 180
        let draft = try store.prepareEntry(from: splitMiddle ? base + 60 : base, to: base + 120, overwriting: true)
        try store.createEntry(named: "Correction", selection: draft)
        #expect(store.runningTask?.name == "Live")
        #expect(store.runningEntry?.start == base + 120)
        now += 1_000
        let reopened = try TrackingStore(url: url, now: { now })
        if splitMiddle {
            #expect(reopened.entries.map(\.start) == [base, base + 60, base + 120])
            #expect(reopened.entries.map(\.end) == [base + 60, base + 120, base + 180])
            #expect(reopened.entries[0].taskID == reopened.entries[2].taskID)
        } else {
            #expect(reopened.entries.map(\.start) == [base, base + 120])
            #expect(reopened.entries.map(\.end) == [base + 120, base + 180])
        }
        #expect(reopened.runningEntry == nil)
    }

    @Test func overwritingTheMiddlePreservesBothSidesAndReopens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let now = base.addingTimeInterval(7_200)
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Original", selection: store.prepareEntry(from: base, to: base + 3_600))
        let original = try #require(store.entries.first)

        let selection = try store.prepareEntry(from: base + 1_200, to: base + 2_400, overwriting: true)
        #expect(selection.overwritesExisting)
        #expect(store.entries == [original])
        try store.createEntry(named: "Replacement", selection: selection)

        #expect(store.entries.map(\.start) == [base, base + 1_200, base + 2_400])
        #expect(store.entries.map(\.end) == [base + 1_200, base + 2_400, base + 3_600])
        #expect(store.entries.map { store.task(id: $0.taskID)?.name } == ["Original", "Replacement", "Original"])
        #expect(Set(store.entries.map(\.id)).count == 3)
        #expect(store.entries[0].id == original.id)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries == store.entries && reopened.tasks == store.tasks)
    }
}
