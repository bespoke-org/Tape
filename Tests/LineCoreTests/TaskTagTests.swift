import Foundation
import Testing
@testable import LineCore

@MainActor
struct TaskTagTests {
    @Test(arguments: [
        ("Building DayLine :dayline :coding :deepwork", "Building DayLine", ["dayline", "coding", "deepwork"]),
        (" :coding  DayTape ", "DayTape", ["coding"]),
        ("Build\t:coding\nDayTape :deepwork ", "Build DayTape", ["coding", "deepwork"]),
        ("Planning: :peka: https://example.com : :work", "Planning: :peka: https://example.com :", ["work"]),
        (":coding :deepwork", "", ["coding", "deepwork"]),
        ("Read :Универ :универ :Coding :coding", "Read", ["универ", "coding"]),
        ("Read :Straße :STRASSE :CAFÉ :cafe\u{301} :深度工作", "Read", ["strasse", "café", "深度工作"]),
        ("Build :project-2 :deep_work", "Build", ["project-2", "deep_work"])
    ])
    func parsing(text: String, name: String, tags: [String]) {
        let parsed = TaskInput(text)
        #expect(parsed.name == name)
        #expect(parsed.tags == tags)
    }

    @Test func completionRespectsCaretUnicodeAndEmoji() throws {
        let text = "📚 :Ун meeting :coding"
        let caret = ("📚 :Ун" as NSString).length
        let token = try #require(TagCompletionToken(text: text, selection: NSRange(location: caret, length: 0)))
        #expect(token.prefix == "ун")
        #expect(TaskInput(token.removing(from: text)).name == "📚 meeting")
        #expect(TaskInput(token.removing(from: text)).tags == ["coding"])
        let result = token.replacing(in: text, with: "универ")
        #expect(result.text == "📚 :универ  meeting :coding")
        #expect(result.caret == ("📚 :универ " as NSString).length)
        for text in ["Name :peka:", "Name ", "https://example.com", "Planning:"] {
            #expect(TagCompletionToken(text: text, selection: NSRange(location: (text as NSString).length, length: 0)) == nil)
        }
        #expect(TagCompletionToken(text: "Name :", selection: NSRange(location: 6, length: 0))?.prefix == "")
        #expect(TagCompletionToken(text: ":coding", selection: NSRange(location: 0, length: 7)) == nil)
    }

    @Test func tagsPersistMergeAndKeepRunningEntryAndColor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Building DayLine :dayline :Coding")
        let entry = try #require(store.runningEntry)
        let task = try #require(store.runningTask)
        now += 60
        try store.startTask(named: "building dayline :deepwork :CODING")
        #expect(store.runningEntry == entry)
        #expect(store.runningTask?.id == task.id && store.runningTask?.color == task.color)
        #expect(store.runningTask?.tags == ["dayline", "coding", "deepwork"])
        try store.startTask(named: "Building DayLine")
        #expect(store.runningTask?.tags == ["dayline", "coding", "deepwork"])
        try store.setTaskColor(id: task.id, color: .pink)
        #expect(store.runningTask?.tags == ["dayline", "coding", "deepwork"])
        try store.stop()
        let reopened = try TrackingStore(url: url)
        #expect(reopened.tasks == store.tasks && reopened.entries == store.entries)
    }

    @Test func creationEditingSearchAndCleanupUseTaskTags() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { base + 1_000 })
        func add(_ text: String, _ offset: Double) throws {
            try store.createEntry(named: text, selection: store.prepareEntry(from: base + offset, to: base + offset + 60))
        }
        try add("DayTape :coding :Универ", 0)
        try add("Other :coding", 120)
        try add("DayTape :deepwork", 240)
        #expect(store.tasks.count == 2)
        #expect(store.taskSuggestions(matching: ":CODING").map(\.name) == ["DayTape", "Other"])
        #expect(store.taskSuggestions(matching: ":УНИВЕР :deepwork").map(\.name) == ["DayTape"])
        #expect(store.taskSuggestions(matching: "day :coding").map(\.name) == ["DayTape"])
        #expect(store.taskSuggestions(matching: ":nonexistent").isEmpty)
        let id = store.entries[0].id
        let records = store.entries
        try store.reassignEntry(id: id, taskName: "DayTape :research")
        #expect(store.entries == records)
        #expect(store.tags == ["coding", "research"])
        #expect(store.task(id: store.entries[2].taskID)?.tags == ["research"])
        try store.reassignEntry(id: id, taskName: "DayTape")
        #expect(store.tags == ["coding"])
        let otherID = store.entries[1].id
        try store.deleteEntry(id: otherID)
        #expect(store.tags.isEmpty)
        #expect(store.taskSuggestions(matching: ":coding").isEmpty)
    }

    @Test func invalidAndFailedChangesPreserveSavedTagsAndEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let store = try TrackingStore(url: url)
        try store.startTask(named: "Work :coding")
        let tasks = store.tasks
        let entries = store.entries
        #expect(throws: TrackingError.emptyTaskName) { try store.startTask(named: ":coding") }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.startTask(named: "Work :new") }
        #expect(throws: (any Error).self) { try store.reassignEntry(id: entries[0].id, taskName: "Work") }
        #expect(throws: (any Error).self) { try store.setTaskColor(id: tasks[0].id, color: .pink) }
        #expect(store.tasks == tasks && store.entries == entries && store.tags == ["coding"])
    }

    @Test func legacyTasksLoadWithoutRewritingNamesOrRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        let taskID = UUID()
        let data = Data("""
        {"version":1,"tasks":[{"id":"\(taskID)","name":"Old :peka:","color":"blue"}],
        "entries":[{"id":"\(UUID())","taskID":"\(taskID)","start":0,"end":60}]}
        """.utf8)
        try data.write(to: url)
        let store = try TrackingStore(url: url)
        #expect(store.tasks[0].name == "Old :peka:" && store.tags.isEmpty)
        #expect(try Data(contentsOf: url) == data)
    }
}
