import Foundation
import Testing
import LineCore

@MainActor
struct EntryEditingTests {
    @Test func correctionsReassignOneEntryPreserveIdentityAndSurviveReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let now = base.addingTimeInterval(7_200)
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base + 900, to: base + 1_200))
        try store.createEntry(named: "Read", selection: store.prepareEntry(from: base + 1_800, to: base + 2_400))
        let original = store.entries[0]
        let build = store.entries[1].taskID
        let read = store.entries[2].taskID
        try store.updateEntry(id: original.id, taskID: read, start: base + 60, end: base + 720)
        #expect(store.entries[0].id == original.id)
        #expect(store.entries[0].taskID == read)
        #expect(store.entries[0].start == base + 60)
        #expect(store.entries[0].end == base + 720)
        #expect(store.entries[1].taskID == build)
        #expect(store.task(id: build)?.name == "Build")
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries == store.entries)
        #expect(reopened.tasks == store.tasks)
    }

    @Test func taskChangesApplyEverywhereAndRejectDuplicateNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let now = base + 7_200
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base + 900, to: base + 1_200))
        try store.startTask(named: "Read")
        let build = store.entries[0].taskID
        let before = store.entries
        try store.updateTask(id: build, name: "  Write  ", color: .mint)
        #expect(store.entries == before)
        #expect(store.task(id: build)?.name == "Write")
        #expect(store.task(id: build)?.color == .mint)
        #expect(throws: TrackingError.duplicateTaskName) { try store.updateTask(id: build, name: " read ", color: .red) }
        #expect(throws: TrackingError.emptyTaskName) { try store.updateTask(id: build, name: " ", color: .red) }
        #expect(store.task(id: build)?.name == "Write")
        #expect(store.task(id: build)?.color == .mint)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.task(id: build) == store.task(id: build))
    }

    @Test func deletingRunningEntryStopsItAndOnlyPrunesTasksWithoutEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let now = base + 7_200
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        let past = store.entries[0]
        try store.startTask(named: "Build")
        let running = try #require(store.runningEntry)
        try store.deleteEntry(id: running.id)
        #expect(store.runningEntry == nil)
        #expect(store.entries == [past])
        #expect(store.tasks.count == 1)
        try store.deleteEntry(id: past.id)
        #expect(store.entries.isEmpty && store.tasks.isEmpty)
        #expect(throws: TrackingError.missingEntry) { try store.deleteEntry(id: past.id) }
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries.isEmpty && reopened.tasks.isEmpty)
    }

    @Test func resizeSnapsAndStopsAtExactNeighborsWithoutChangingRunningTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 600.25
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        try store.startTask(named: "Neighbor")
        now = base + 900.75
        try store.stop()
        now = base + 3_600.25
        try store.createEntry(named: "Edit", selection: store.prepareEntry(from: base + 1_200, to: base + 1_800))
        let entry = store.entries[1]
        let left = try store.prepareResize(id: entry.id, edge: .start, to: base + 700)
        #expect(left.start == base + 900.75)
        #expect(left.end == base + 1_800)
        let right = try store.prepareResize(id: entry.id, edge: .end, to: base + 1_949)
        #expect(right.start == entry.start)
        #expect(right.end == base + 1_920)
        let atNow = try store.prepareResize(id: entry.id, edge: .end, to: now + 1)
        #expect(atNow.end == now)
        try store.updateEntry(id: entry.id, taskID: entry.taskID, start: left.start, end: left.end)
        #expect(store.entries[0].end == store.entries[1].start)
        try store.startTask(named: "Live")
        let live = try #require(store.runningEntry)
        #expect(throws: TrackingError.trackingStateChanged) { try store.prepareResize(id: live.id, edge: .end, to: now + 30) }
        #expect(store.runningEntry == live)
    }

    @Test func invalidAndStaleEditsLeaveEntriesAndTasksUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let now = base + 7_200
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        try store.createEntry(named: "Read", selection: store.prepareEntry(from: base + 900, to: base + 1_200))
        let first = store.entries[0]
        let entries = store.entries
        let tasks = store.tasks
        #expect(throws: TrackingError.overlappingEntry) { try store.updateEntry(id: first.id, taskID: first.taskID, start: base, end: base + 1_000) }
        #expect(throws: TrackingError.emptyInterval) { try store.updateEntry(id: first.id, taskID: first.taskID, start: base, end: base) }
        #expect(throws: TrackingError.emptyInterval) { try store.updateEntry(id: first.id, taskID: first.taskID, start: Date(timeIntervalSince1970: .nan), end: base) }
        #expect(throws: TrackingError.futureInterval) { try store.updateEntry(id: first.id, taskID: first.taskID, start: now, end: now + 60) }
        #expect(throws: TrackingError.trackingStateChanged) { try store.updateEntry(id: first.id, taskID: first.taskID, start: base, end: nil) }
        #expect(throws: TrackingError.missingEntry) { try store.updateEntry(id: UUID(), taskID: first.taskID, start: base, end: base + 600) }
        #expect(throws: TrackingError.missingTask) { try store.updateEntry(id: first.id, taskID: UUID(), start: base, end: base + 600) }
        #expect(store.entries == entries && store.tasks == tasks)
        try store.updateEntry(id: first.id, taskID: first.taskID, start: base, end: base + 900)
        #expect(store.entries[0].end == store.entries[1].start)
    }

    @Test func correctingRunningStartAndTaskKeepsTrackingAndRecoversBeyondNewStart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 3_600
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Read", selection: store.prepareEntry(from: base, to: base + 600))
        let read = store.entries[0].taskID
        try store.startTask(named: "Build")
        let running = try #require(store.runningEntry)
        now += 120
        #expect(throws: TrackingError.trackingStateChanged) { try store.updateEntry(id: running.id, taskID: read, start: running.start, end: now) }
        #expect(store.runningEntry == running)
        try store.updateEntry(id: running.id, taskID: read, start: base + 3_660, end: nil)
        #expect(store.runningEntry?.id == running.id)
        #expect(store.runningEntry?.start == base + 3_660)
        #expect(store.runningTask?.id == read)
        #expect(store.tasks.count == 1)
        let reopened = try TrackingStore(url: url, now: { now + 600 })
        #expect(reopened.entries.last?.end == base + 3_720)
        #expect(reopened.entries.last?.duration(at: now) == 60)
        try store.stop()
        #expect(throws: TrackingError.trackingStateChanged) { try store.updateEntry(id: running.id, taskID: read, start: base + 3_660, end: nil) }
    }

    @Test func failedCorrectionsRenamesAndDeletionNeverPublishOrLoseData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("data")
        let saved = directory.appendingPathComponent("saved")
        let url = parent.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Build")
        now += 60
        try store.checkpoint()
        let entry = try #require(store.runningEntry)
        let tasks = store.tasks
        try FileManager.default.moveItem(at: parent, to: saved)
        try Data("not a directory".utf8).write(to: parent)
        #expect(throws: (any Error).self) { try store.updateEntry(id: entry.id, taskID: entry.taskID, start: base + 30, end: nil) }
        #expect(throws: (any Error).self) { try store.updateTask(id: entry.taskID, name: "Read", color: .red) }
        #expect(throws: (any Error).self) { try store.deleteEntry(id: entry.id) }
        #expect(store.entries == [entry] && store.tasks == tasks)
        #expect(store.runningEntry == entry)
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: saved, to: parent)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries.first?.start == base)
        #expect(reopened.entries.first?.end == base + 60)
        #expect(reopened.tasks == tasks)
    }

    @Test func editingAcrossMidnightAndRepeatedLocalHourPreservesAbsoluteInstants() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parse = ISO8601DateFormatter()
        let start = try #require(parse.date(from: "2026-11-01T23:30:00Z"))
        let end = try #require(parse.date(from: "2026-11-02T00:30:00Z"))
        let first = try #require(parse.date(from: "2026-11-01T01:30:00-04:00"))
        let second = try #require(parse.date(from: "2026-11-01T01:30:00-05:00"))
        let now = end + 7_200
        let url = directory.appendingPathComponent("tracking.json")
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Read", selection: store.prepareEntry(from: start, to: end))
        let entry = store.entries[0]
        #expect(entry.duration(at: now) == 3_600)
        try store.updateEntry(id: entry.id, taskID: entry.taskID, start: first, end: second)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries[0].start == first)
        #expect(reopened.entries[0].end == second)
        #expect(reopened.entries[0].duration(at: now) == 3_600)
    }
}
