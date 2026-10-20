import Foundation
import Testing
import LineCore

@MainActor
struct ResizeOverwriteTests {
    @Test(arguments: [EntryEdge.start, .end])
    func resizingAcrossNeighborsTrimsDeletesAndKeepsTheResizedEntry(edge: EntryEdge) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { base + 3_600 })
        for (name, start, end) in [("Left", 0.0, 600.0), ("Middle", 900.0, 1_200.0), ("Right", 1_500.0, 2_100.0)] {
            try store.createEntry(named: name, selection: store.prepareEntry(from: base + start, to: base + end))
        }
        let before = store.entries
        let entry = edge == .start ? before[2] : before[0]
        let task = store.task(id: entry.taskID)
        let target = base + (edge == .start ? 300 : 1_800)
        let preview = try store.prepareResize(id: entry.id, edge: edge, to: target, overwriting: true)
        #expect(preview.start == (edge == .start ? target : entry.start))
        #expect(preview.end == (edge == .end ? target : entry.end))
        #expect(store.entries == before)
        try store.resizeEntry(id: entry.id, edge: edge, to: target, overwriting: true)
        #expect(store.entries.map(\.start) == (edge == .start ? [base, base + 300] : [base, base + 1_800]))
        #expect(store.entries.map(\.end) == (edge == .start ? [base + 300, base + 2_100] : [base + 1_800, base + 2_100]))
        #expect(store.entries.contains { $0.id == entry.id && $0.taskID == entry.taskID })
        #expect(store.task(id: entry.taskID) == task)
        #expect(store.task(id: before[1].taskID) == nil)
        let reopened = try TrackingStore(url: url, now: { base + 4_000 })
        #expect(reopened.entries == store.entries && reopened.tasks == store.tasks)
    }
    @Test(arguments: [EntryEdge.start, .end])
    func resizeMergesConnectedSameTaskTimeWithoutChangingItsIdentity(edge: EntryEdge) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { base + 3_600 })
        for (name, start, end) in [("Build", 0.0, 300.0), ("Left", 300.0, 600.0), ("Build", 600.0, 900.0),
                                  ("Right", 900.0, 1_200.0), ("Build", 1_200.0, 1_500.0), ("Build", 1_800.0, 2_100.0)] {
            try store.createEntry(named: name, selection: store.prepareEntry(from: base + start, to: base + end))
        }
        let original = store.entries[2]
        let distant = store.entries[5]
        try store.resizeEntry(id: original.id, edge: edge, to: base + (edge == .start ? 120 : 1_380), overwriting: true)
        let merged = try #require(store.entries.first { $0.id == original.id })
        #expect(merged.taskID == original.taskID)
        #expect(merged.start == base + (edge == .start ? 0 : 600))
        #expect(merged.end == base + (edge == .start ? 900 : 1_500))
        #expect(store.entries.count == 4 && store.entries.last == distant)
    }

    @Test(arguments: ["tail", "now", "start"])
    func overwriteResizePreservesRunningTimeAndRecovery(mode: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 1_200
        let store = try TrackingStore(url: url, now: { now })
        try store.createEntry(named: "Earlier", selection: store.prepareEntry(from: base, to: base + 600))
        let earlier = store.entries[0]
        try store.startTask(named: "Live")
        let live = try #require(store.runningEntry)
        now = base + 1_800
        try store.checkpoint()
        now = base + 3_600
        switch mode {
        case "tail":
            try store.resizeEntry(id: earlier.id, edge: .end, to: base + 2_400, overwriting: true)
            #expect(store.entries[0].end == base + 2_400)
            #expect(store.runningEntry?.id == live.id && store.runningEntry?.start == base + 2_400)
        case "now":
            try store.resizeEntry(id: earlier.id, edge: .end, to: now - 1, reachesNow: true, overwriting: true)
            #expect(store.entries.count == 1 && store.tasks.count == 1)
            #expect(store.runningEntry?.id == earlier.id && store.runningEntry?.start == base)
        default:
            try store.resizeEntry(id: live.id, edge: .start, to: base + 300, overwriting: true)
            #expect(store.entries[0].end == base + 300)
            #expect(store.runningEntry?.id == live.id && store.runningEntry?.start == base + 300)
        }
        let running = try #require(store.runningEntry)
        let reopened = try TrackingStore(url: url, now: { now + 1_000 })
        #expect(reopened.entries.last?.id == running.id)
        #expect(reopened.entries.last?.start == running.start)
        #expect(reopened.entries.last?.end == base + 3_600)
        #expect(reopened.runningEntry == nil)
    }

    @Test func failedOverwriteResizeAndInvalidDragPreserveAllRecordedTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("data")
        let saved = directory.appendingPathComponent("saved")
        let url = parent.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { base + 3_600 })
        try store.createEntry(named: "Build", selection: store.prepareEntry(from: base, to: base + 600))
        let original = store.entries[0]
        // A neighbor added after the preview must be considered when committing.
        _ = try store.prepareResize(id: original.id, edge: .end, to: base + 1_500, overwriting: true)
        try store.createEntry(named: "Other", selection: store.prepareEntry(from: base + 900, to: base + 1_200))
        let entries = store.entries
        let tasks = store.tasks
        #expect(throws: TrackingError.emptyInterval) {
            try store.resizeEntry(id: original.id, edge: .end, to: base, overwriting: true)
        }
        try FileManager.default.moveItem(at: parent, to: saved)
        try Data("not a directory".utf8).write(to: parent)
        #expect(throws: (any Error).self) {
            try store.resizeEntry(id: original.id, edge: .end, to: base + 1_500, overwriting: true)
        }
        #expect(store.entries == entries && store.tasks == tasks)
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: saved, to: parent)
        let reopened = try TrackingStore(url: url, now: { base + 4_000 })
        #expect(reopened.entries == entries && reopened.tasks == tasks)
        try store.resizeEntry(id: original.id, edge: .end, to: base + 1_500, overwriting: true)
        #expect(store.entries.count == 1 && store.entries[0].id == original.id)
        #expect(store.entries[0].end == base + 1_500 && store.tasks.count == 1)
    }

}
