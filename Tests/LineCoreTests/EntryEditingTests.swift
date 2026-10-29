import Foundation
import Testing
import LineCore

@MainActor
struct EntryEditingTests {
    @Test func resizingRunningStartKeepsTrackingAndClampsToPreviousEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 1_800
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Earlier", selection: store.prepareEntry(from: base, to: base + 600))
        try store.startTask(named: "Build")
        let original = try #require(store.runningEntry)
        now = base + 3_600
        try store.resizeEntry(id: original.id, edge: .start, to: base + 300)
        #expect(store.runningEntry?.start == base + 600)
        #expect(store.runningEntry?.id == original.id && store.runningEntry?.taskID == original.taskID)
        try store.resizeEntry(id: original.id, edge: .start, to: base + 2_430)
        #expect(store.runningEntry?.start == base + 2_460)
        let reopened = try TrackingStore(url: url, now: { now + 300 })
        #expect(reopened.entries.last?.start == base + 2_460)
        #expect(reopened.entries.last?.end == base + 3_600)
    }

    @Test func resizingRunningEndAtNowKeepsTrackingAndIntoPastStopsIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Build")
        let original = try #require(store.runningEntry)
        now = base + 3_600.25
        try store.resizeEntry(id: original.id, edge: .end, to: now + 60)
        #expect(store.runningEntry == original)
        try store.resizeEntry(id: original.id, edge: .end, to: now - 1, reachesNow: true)
        #expect(store.runningEntry == original)
        #expect(throws: TrackingError.emptyInterval) { try store.resizeEntry(id: original.id, edge: .end, to: base) }
        #expect(store.runningEntry == original)
        let preview = try store.prepareResize(id: original.id, edge: .end, to: base + 1_230)
        #expect(preview.end == base + 1_260 && store.runningEntry == original)
        try store.resizeEntry(id: original.id, edge: .end, to: base + 1_230)
        #expect(store.runningEntry == nil)
        #expect(store.entries[0].id == original.id && store.entries[0].start == base)
        #expect(store.entries[0].end == base + 1_260)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries == store.entries && reopened.runningEntry == nil)
        // The backdated end, not a stale running checkpoint, is now the latest tracked instant.
        now = base + 1_800
        try reopened.startTask(named: "Read")
        #expect(reopened.runningTask?.name == "Read")
    }

    @Test(arguments: [false, true])
    func resizingToNowContinuesTheSameEntryAndPersistsRecovery(nearMarker: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 7_200.25
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        let original = store.entries[0]
        try store.resizeEntry(id: original.id, edge: .end, to: nearMarker ? now - 1 : now, reachesNow: nearMarker)
        #expect(store.runningEntry?.id == original.id)
        #expect(store.runningEntry?.start == original.start)
        #expect(store.runningEntry?.taskID == original.taskID)
        #expect(store.entries.count == 1)
        let recovered = try TrackingStore(url: url, now: { now + 300 })
        #expect(recovered.entries[0].end == base + 7_200.25)
        now += 60
        try store.checkpoint()
        let reopened = try TrackingStore(url: url, now: { now + 300 })
        #expect(reopened.entries[0].end == base + 7_260.25)
        #expect(reopened.entries[0].id == original.id)
    }

    @Test(arguments: [false, true])
    func resizeToNowStopsAtNeighborsAddedAfterPreview(runningNeighbor: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let now = base + 7_200.25
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        let original = store.entries[0]
        #expect(try store.prepareResize(id: original.id, edge: .end, to: now).end == nil)
        if runningNeighbor {
            try store.startTask(named: "Other")
        } else {
            try store.createEntry(named: "Other", selection: store.prepareEntry(from: base + 1_200, to: base + 1_800))
        }
        let neighbor = store.entries[1]
        try store.resizeEntry(id: original.id, edge: .end, to: now + 60, reachesNow: true)
        #expect(store.entries[0].end == neighbor.start)
        #expect(store.entries[1] == neighbor)
        #expect(store.runningEntry?.id == (runningNeighbor ? neighbor.id : nil))
        try store.resizeEntry(id: original.id, edge: .start, to: base + 60, reachesNow: true)
        #expect(store.entries[0].start == base + 60 && store.entries[0].end == neighbor.start)
    }

    @Test func failedResizeToNowLeavesTheEntryCompleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("data")
        let saved = directory.appendingPathComponent("saved")
        let url = parent.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let now = base + 7_200
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        let original = store.entries[0]
        try FileManager.default.moveItem(at: parent, to: saved)
        try Data("not a directory".utf8).write(to: parent)
        #expect(throws: (any Error).self) { try store.resizeEntry(id: original.id, edge: .end, to: now) }
        #expect(store.entries == [original] && store.runningEntry == nil)
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: saved, to: parent)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries == [original])
    }

    @Test func reassigningByNameCreatesOrReusesTasksWithoutChangingTimeOrOtherEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 7_200
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base + 900, to: base + 1_200))
        let original = store.entries[0]
        let untouched = store.entries[1]
        try store.reassignEntry(id: original.id, taskName: "  Read  ")
        #expect(store.entries[0].id == original.id)
        #expect(store.entries[0].start == original.start && store.entries[0].end == original.end)
        #expect(store.task(id: store.entries[0].taskID)?.name == "Read")
        #expect(store.entries[1] == untouched && store.task(id: untouched.taskID)?.name == "Build")
        try store.reassignEntry(id: original.id, taskName: "bUiLd")
        #expect(store.entries[0] == original && store.tasks.count == 1)
        #expect(throws: TrackingError.emptyTaskName) { try store.reassignEntry(id: original.id, taskName: " ") }
        #expect(throws: TrackingError.missingEntry) { try store.reassignEntry(id: UUID(), taskName: "Missing") }
        #expect(store.tasks.count == 1)
        try store.startTask(named: "Build")
        let running = try #require(store.runningEntry)
        try store.reassignEntry(id: running.id, taskName: "Read")
        #expect(store.runningEntry?.id == running.id && store.runningEntry?.start == running.start)
        #expect(store.runningTask?.name == "Read")
        now += 60
        try store.checkpoint()
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.entries[0] == original && reopened.entries[1] == untouched)
        #expect(reopened.entries.last?.end == now)
        #expect(reopened.tasks == store.tasks)
    }

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

    @Test func recoloringPreservesNamesAndEntriesAndSurvivesReopening() throws {
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
        try store.setTaskColor(id: build, color: .teal)
        #expect(store.entries == before)
        #expect(store.task(id: build)?.name == "Build")
        #expect(store.task(id: build)?.color == .teal)
        #expect(throws: TrackingError.missingTask) { try store.setTaskColor(id: UUID(), color: .red) }
        #expect(store.task(id: build)?.name == "Build")
        #expect(store.task(id: build)?.color == .teal)
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
        #expect(atNow.end == nil)
        try store.updateEntry(id: entry.id, taskID: entry.taskID, start: left.start, end: left.end)
        #expect(store.entries[0].end == store.entries[1].start)
        try store.startTask(named: "Live")
        let live = try #require(store.runningEntry)
        now += 60
        #expect(try store.prepareResize(id: live.id, edge: .end, to: now + 30).end == base + 3_720)
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

    @Test func failedCorrectionsRecolorsAndDeletionNeverPublishOrLoseData() throws {
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
        #expect(throws: (any Error).self) { try store.setTaskColor(id: entry.taskID, color: .red) }
        #expect(throws: (any Error).self) { try store.deleteEntry(id: entry.id) }
        #expect(throws: (any Error).self) { try store.reassignEntry(id: entry.id, taskName: "New task") }
        #expect(throws: (any Error).self) { try store.resizeEntry(id: entry.id, edge: .end, to: base + 30) }
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
