#if DEBUG
import Foundation
import LineCore
import Testing
@testable import Line

@MainActor
struct PlanningModelTests {
    @Test func solidAndDashedPartsSelectAndResizeOneEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storeURL: directory.appendingPathComponent("tracking.json"))
        let store = try #require(model.store)
        let now = Date.now
        model.timeline.pauseFollowing(at: now)
        try store.createEntry(named: "One entry", selection: EntrySelection(start: now - 1_800, end: now + 1_800))
        let id = try #require(store.runningEntry?.id)
        for date in [now - 900, now + 900] {
            model.selectEntry(at: model.timeline.fraction(for: date, now: now), minimumWidth: 0)
            #expect(model.editingEntryID == id)
            model.cancelEntry()
        }
        #expect(model.resizeEdge(at: model.timeline.fraction(for: now, now: now), tolerance: 0.001) == nil)
        #expect(model.resizeEdge(at: model.timeline.fraction(for: now + 1_800, now: now), tolerance: 0.001) == .end)
        model.selectEntry(at: model.timeline.fraction(for: now + 900, now: now), minimumWidth: 0)
        #expect(model.deleteEntry(id: id))
        #expect(store.entries.isEmpty && store.runningEntry == nil)
        try store.startTask(named: "Just started")
        model.selectEntry(at: model.timeline.fraction(for: Date.now + 1, now: .now), minimumWidth: 2.0 / 580)
        #expect(model.editingEntryID == nil)
    }

    @Test(arguments: [false, true])
    func retryAfterFailedLockRetainsOriginalBoundary(checkpoint: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let model = AppModel(storeURL: url)
        let store = try #require(model.store)
        let now = Date.now
        try store.createEntry(named: "Scheduled", selection: EntrySelection(start: now - 60, end: now + 300))
        let saved = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let beforeLock = Date.now
        model.handleSystemEvent(.locked)
        let afterLock = Date.now
        #expect(model.errorMessage != nil && store.runningEntry != nil)
        try FileManager.default.removeItem(at: url)
        try saved.write(to: url)
        if checkpoint { model.checkpoint() } else { model.pollSchedule() }
        #expect(store.runningEntry == nil && store.entries.first?.state == .paused)
        let end = try #require(store.entries.first?.recorded.last?.end)
        #expect(end >= beforeLock && end <= afterLock)
    }
}
#endif
