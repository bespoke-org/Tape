import Foundation
import Testing
@testable import LineCore

@MainActor
struct TaskOrderTests {
    @Test func sortsByLatestEntryCountOrNaturalNameWithAlphabeticalTies() {
        let tasks = ["Unused", "Task 10", "Task 2", "Recent"].map {
            TrackedTask(id: UUID(), name: $0, color: .blue)
        }
        func entry(_ task: Int, _ start: Double) -> TimeEntry {
            TimeEntry(id: UUID(), taskID: tasks[task].id, start: Date(timeIntervalSince1970: start), end: nil)
        }
        // Deliberately unordered input; both numbered tasks have equal counts and latest dates.
        let entries = [entry(1, 20), entry(3, 30), entry(2, 20), entry(1, 10), entry(2, 10)]
        #expect(TaskOrder.recentlyUsed.sorted(tasks, entries: entries).map(\.name) == ["Recent", "Task 2", "Task 10", "Unused"])
        #expect(TaskOrder.mostUsed.sorted(tasks, entries: entries).map(\.name) == ["Task 2", "Task 10", "Recent", "Unused"])
        #expect(TaskOrder.alphabetical.sorted(tasks, entries: entries).map(\.name) == ["Recent", "Task 2", "Task 10", "Unused"])
    }

    @Test func suggestionsFollowRecordedTimeAndEditsAndFilterWithoutChangingOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { base + 1_000 })
        func add(_ name: String, at offset: Double) throws {
            try store.createEntry(named: name, selection: store.prepareEntry(from: base + offset, to: base + offset + 60))
        }
        try add("Task 2", at: 120)
        try add("Task 10", at: 240)
        try add("Other", at: 360)
        try add("Task 2", at: 0) // Newly entered older history does not outrank recent entries.
        #expect(store.taskSuggestions(matching: "").map(\.name) == ["Other", "Task 10", "Task 2"])
        #expect(store.taskSuggestions(matching: "  TASK  ").map(\.name) == ["Task 10", "Task 2"])
        try store.setTaskOrder(.mostUsed)
        #expect(store.taskSuggestions(matching: "").map(\.name) == ["Task 2", "Other", "Task 10"])
        try store.setTaskOrder(.alphabetical)
        #expect(store.taskSuggestions(matching: "task").map(\.name) == ["Task 2", "Task 10"])
        try store.setTaskOrder(.recentlyUsed)
        let latest = try #require(store.entries.last)
        try store.reassignEntry(id: latest.id, taskName: "Task 2")
        #expect(store.taskSuggestions(matching: "").map(\.name) == ["Task 2", "Task 10"])
        try store.deleteEntry(id: latest.id)
        #expect(store.taskSuggestions(matching: "").map(\.name) == ["Task 10", "Task 2"])
        try store.startTask(named: "Task 2")
        #expect(store.taskSuggestions(matching: "").first?.name == "Task 2")
    }

    @Test(arguments: TaskOrder.allCases)
    func settingPersistsWithoutChangingTracking(order: TaskOrder) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        #expect(store.taskOrder == .recentlyUsed)
        try store.startTask(named: "Keep tracking")
        now += 60
        try store.checkpoint()
        let entries = store.entries
        let tasks = store.tasks
        try store.setTaskOrder(order)
        #expect(store.entries == entries && store.tasks == tasks)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.taskOrder == order)
        #expect(reopened.entries.first?.duration(at: now) == 60)
    }

    @Test(arguments: ["", #", "taskOrder":"futureOrder""#])
    func missingOrUnknownOrderDefaultsToRecencyWithoutRewriting(field: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        let data = Data((#"{"version":1,"tasks":[],"entries":[]"# + field + "}").utf8)
        try data.write(to: url)
        #expect(try TrackingStore(url: url).taskOrder == .recentlyUsed)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func failedSaveKeepsPreviousChoiceAndTracking() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let store = try TrackingStore(url: url)
        try store.startTask(named: "Keep tracking")
        try store.setTaskOrder(.alphabetical)
        let entries = store.entries
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.setTaskOrder(.mostUsed) }
        #expect(store.taskOrder == .alphabetical && store.entries == entries)
    }
}
