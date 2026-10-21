import Foundation
import Testing
import LineCore

@MainActor
struct TrackingStoreTests {
    @Test(arguments: ["cyan", "indigo", "mint"])
    func removedShadesLoadWithoutLosingRecordedTime(legacyColor: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        let taskID = UUID()
        let entryID = UUID()
        let data = """
        {"version":1,"tasks":[{"id":"\(taskID)","name":"Saved work","color":"\(legacyColor)"}],
        "entries":[{"id":"\(entryID)","taskID":"\(taskID)","start":0,"end":60}]}
        """
        try Data(data.utf8).write(to: url)
        let store = try TrackingStore(url: url)
        #expect(store.tasks.count == 1)
        #expect(store.task(id: taskID)?.color == (legacyColor == "indigo" ? .blue : .teal))
        #expect(store.entries.count == 1 && store.entries[0].id == entryID)
        #expect(store.entries[0].duration(at: .now) == 60)
        // A later write must keep the replacement shade readable on reopening.
        try store.setTaskColor(id: taskID, color: store.tasks[0].color)
        let reopened = try TrackingStore(url: url)
        #expect(reopened.tasks == store.tasks && reopened.entries == store.entries)
    }

    @Test func switchingAwayFromZeroDurationTaskReusesItsFreedColor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: directory.appendingPathComponent("tracking.json"), now: { now })
        for index in 0..<(TaskColor.allCases.count - 1) {
            try store.startTask(named: "Saved \(index)")
            now += 60
            try store.stop()
        }
        try store.startTask(named: "Discarded")
        let freedColor = try #require(store.runningTask).color
        try store.startTask(named: "Replacement")
        #expect(store.tasks.count == TaskColor.allCases.count)
        #expect(store.runningTask?.color == freedColor)
        #expect(Set(store.tasks.map(\.color)).count == TaskColor.allCases.count)
    }

    @Test func newTasksUseEveryColorBeforeRepeatingAndKeepAssignedColors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var now = base + 7_200
        let store = try TrackingStore(url: url, now: { now })
        for index in 0..<TaskColor.allCases.count {
            if index.isMultiple(of: 2) {
                try store.startTask(named: "Task \(index)")
                now += 60
                try store.stop()
            } else {
                let start = base + Double(index) * 120
                try store.createEntry(named: "Task \(index)", selection: store.prepareEntry(from: start, to: start + 60))
            }
        }
        let assigned = store.tasks
        let colors = Set(assigned.map(\.color))
        #expect(assigned.count == TaskColor.allCases.count && colors == Set(TaskColor.allCases))
        try store.startTask(named: "task 0")
        now += 60
        try store.stop()
        #expect(store.tasks == assigned)
        try store.startTask(named: "Overflow")
        #expect(colors.contains(try #require(store.runningTask).color))
        now += 60
        try store.stop()
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.tasks == store.tasks)
    }

    @Test func loadingRemovesPreviouslyUnusedTasksAndPreservesRecordedWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        try Data(#"""
        {"version":1,"timelineSpan":7200,"tasks":[
          {"id":"00000000-0000-0000-0000-000000000001","name":"Removed work","color":"blue"},
          {"id":"00000000-0000-0000-0000-000000000002","name":"Keep","color":"green"}
        ],"entries":[
          {"id":"00000000-0000-0000-0000-000000000003","taskID":"00000000-0000-0000-0000-000000000002","start":0,"end":60}
        ]}
        """#.utf8).write(to: url)
        let store = try TrackingStore(url: url)
        #expect(store.tasks.map(\.name) == ["Keep"])
        #expect(store.tasks.first?.color == .green)
        #expect(store.entries.count == 1 && store.entries.first?.duration(at: .now) == 60)
        #expect(store.defaultZoomHours == 8)
        let reopened = try TrackingStore(url: url)
        #expect(reopened.tasks == store.tasks && reopened.entries == store.entries)
    }

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
    @Test func defaultZoomSurvivesReopeningOldStoresWithoutChangingRecoveryTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        try Data(#"{"version":1,"tasks":[],"entries":[]}"#.utf8).write(to: url)
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        #expect(store.defaultZoomHours == 8)
        try store.startTask(named: "Read")
        now += 5
        try store.checkpoint()
        now += 10
        try store.setDefaultZoomHours(2)
        now += 3_600
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.defaultZoomHours == 2)
        #expect(reopened.entries.first?.duration(at: now) == 5)
        #expect(reopened.runningTask == nil)
    }

    @Test func defaultZoomBoundsPersistWithoutChangingRecordedWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        try store.startTask(named: "Keep this work")
        now += 60
        try store.stop()
        let entries = store.entries
        let tasks = store.tasks
        for (requested, expected) in [(Int.min, 1), (2, 2), (3, 2), (6, 4), (7, 8), (10, 8), (12, 12), (14, 12), (16, 16), (18, 16), (20, 16), (21, 24), (Int.max, 24)] {
            try store.setDefaultZoomHours(requested)
            let reopened = try TrackingStore(url: url, now: { now })
            #expect(reopened.defaultZoomHours == expected)
            #expect(reopened.entries == entries && reopened.tasks == tasks)
        }
    }

    @Test func legacyZoomUsesNearestPresetWithoutRewritingRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        let data = Data(#"{"version":1,"tasks":[],"entries":[],"defaultZoomHours":7}"#.utf8)
        try data.write(to: url)
        let store = try TrackingStore(url: url)
        #expect(store.defaultZoomHours == 8)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func resumePreferencesPersistWithoutChangingTrackingAndRecoverOnSaveFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        #expect(store.automaticResumeEnabled && store.shortBreakSeconds == 300)
        try store.startTask(named: "Keep tracking")
        now += 5
        try store.checkpoint()
        let entries = store.entries
        now += 100
        try store.setAutomaticResumeEnabled(false)
        try store.setShortBreakSeconds(30)
        #expect(store.entries == entries)
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(!reopened.automaticResumeEnabled && reopened.shortBreakSeconds == 30)
        #expect(reopened.entries.first?.duration(at: now) == 5)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.setAutomaticResumeEnabled(true) }
        #expect(throws: (any Error).self) { try store.setShortBreakSeconds(0) }
        #expect(!store.automaticResumeEnabled && store.shortBreakSeconds == 30)
        #expect(store.entries == entries)
    }

    @Test func legacyResumePreferencesAndBoundedThreshold() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        for (field, expected) in [("", 300), (#", "shortBreakMinutes":7"#, 420), (#", "shortBreakMinutes":-1"#, 0), (#", "shortBreakMinutes":100"#, 3600), (#", "shortBreakMinutes":5, "shortBreakSeconds":30"#, 30)] {
            let data = Data((#"{"version":1,"tasks":[],"entries":[]"# + field + "}").utf8)
            try data.write(to: url)
            let store = try TrackingStore(url: url)
            #expect(store.automaticResumeEnabled && store.shortBreakSeconds == expected)
            #expect(try Data(contentsOf: url) == data)
            try store.setShortBreakSeconds(Int.min)
            #expect(store.shortBreakSeconds == 0)
            try store.setShortBreakSeconds(Int.max)
            #expect(store.shortBreakSeconds == 3600)
        }
    }

    @Test(arguments: [1, 9, 60])
    func resumeCountdownPersistsWithoutChangingTrackingOrRecovery(seconds: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        #expect(store.resumeCountdownSeconds == 9)
        try store.startTask(named: "Keep tracking")
        now += 5
        try store.checkpoint()
        try store.setTimeFormat(.twelveHour)
        let entries = store.entries
        now += 10
        try store.setResumeCountdownSeconds(seconds)
        #expect(store.entries == entries)
        let reopened = try TrackingStore(url: url, now: { now + 3_600 })
        #expect(reopened.resumeCountdownSeconds == seconds)
        #expect(reopened.timeFormat == .twelveHour && reopened.defaultZoomHours == 8)
        #expect(reopened.entries.first?.duration(at: now) == 5)
    }

    @Test func resumeCountdownDefaultsAndBoundsDoNotRewriteOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        for (field, expected) in [("", 9), (#", "resumeCountdownSeconds":-1"#, 1),
                                   (#", "resumeCountdownSeconds":100"#, 60)] {
            let data = Data((#"{"version":1,"tasks":[],"entries":[]"# + field + "}").utf8)
            try data.write(to: url)
            let store = try TrackingStore(url: url)
            #expect(store.resumeCountdownSeconds == expected)
            #expect(try Data(contentsOf: url) == data)
            try store.setResumeCountdownSeconds(Int.min)
            #expect(store.resumeCountdownSeconds == 1)
            try store.setResumeCountdownSeconds(Int.max)
            #expect(store.resumeCountdownSeconds == 60)
            #expect(try TrackingStore(url: url).resumeCountdownSeconds == 60)
        }
    }

    @Test func failedResumeCountdownSaveKeepsPreviousChoiceAndRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let store = try TrackingStore(url: url)
        try store.startTask(named: "Keep tracking")
        try store.setResumeCountdownSeconds(15)
        let entries = store.entries
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.setResumeCountdownSeconds(30) }
        #expect(store.resumeCountdownSeconds == 15)
        #expect(store.entries == entries && store.runningTask?.name == "Keep tracking")
    }

    @Test(arguments: TimeFormat.allCases)
    func timeFormatPersistsWithoutChangingTrackingOrRecovery(format: TimeFormat) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try TrackingStore(url: url, now: { now })
        #expect(store.timeFormat == .system)
        try store.startTask(named: "Keep tracking")
        now += 5
        try store.checkpoint()
        let entries = store.entries
        let tasks = store.tasks
        now += 10
        try store.setTimeFormat(format)
        #expect(store.entries == entries && store.tasks == tasks)
        #expect(store.defaultZoomHours == 8)
        now += 3_600
        let reopened = try TrackingStore(url: url, now: { now })
        #expect(reopened.timeFormat == format)
        #expect(reopened.entries.first?.duration(at: now) == 5)
    }

    @Test(arguments: ["", #", "timeFormat":"futureFormat""#])
    func missingOrUnknownTimeFormatDefaultsToSystem(field: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        let data = Data((#"{"version":1,"tasks":[],"entries":[]"# + field + "}").utf8)
        try data.write(to: url)
        #expect(try TrackingStore(url: url).timeFormat == .system)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func failedTimeFormatSaveKeepsPreviousChoiceAndRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let store = try TrackingStore(url: url)
        try store.startTask(named: "Keep tracking")
        try store.setTimeFormat(.twelveHour)
        let entries = store.entries
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.setTimeFormat(.twentyFourHour) }
        #expect(store.timeFormat == .twelveHour)
        #expect(store.entries == entries && store.runningTask?.name == "Keep tracking")
    }

    @Test func failedDefaultZoomSaveKeepsPreviousSettingAndRunningEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracking.json")
        let store = try TrackingStore(url: url)
        try store.startTask(named: "Keep tracking")
        try store.setDefaultZoomHours(4)
        let entries = store.entries
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.setDefaultZoomHours(12) }
        #expect(store.defaultZoomHours == 4)
        #expect(store.entries == entries && store.runningTask?.name == "Keep tracking")
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
        #expect(recovered.tasks.isEmpty)
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
