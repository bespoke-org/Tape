#if DEBUG
import Foundation
import LineCore
import Testing
@testable import Line

@MainActor
struct PlanningModelTests {
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
        #expect(store.runningEntry == nil && store.plans.first?.state == .paused)
        let end = try #require(store.entries.first?.end)
        #expect(end >= beforeLock && end <= afterLock)
    }
}
#endif
