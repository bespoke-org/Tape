import Foundation
import Testing
@testable import LineCore

@MainActor
struct UnifiedEntryTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(_ body: (TrackingStore, URL, Clock) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(now: base)
        let url = directory.appendingPathComponent("tracking.json")
        try body(TrackingStore(url: url, now: { clock.now }), url, clock)
    }

    @Test func pauseResumeEditAndDeleteKeepOneEntryAndExcludeGaps() throws {
        try fixture { store, url, clock in
            try store.createEntry(named: "Build :coding", selection: EntrySelection(start: base - 60, end: base + 600))
            let id = try #require(store.runningEntry?.id)
            clock.now += 60
            try store.stop(preservingPlan: true)
            clock.now += 120
            try store.startScheduledEntry(id: id)
            clock.now += 60
            #expect(store.entries.count == 1 && store.runningEntry?.id == id)
            #expect(store.entries[0].recorded.count == 2)
            #expect(store.entries[0].duration(at: clock.now) == 180)
            let range = DateInterval(start: base - 120, end: base + 900)
            let segments = store.timelineSegments(in: range, at: clock.now)
            #expect(Set(segments.map { $0.entry.id }) == [id])
            #expect(segments.filter { $0.kind == .untracked }.map(\.interval.duration) == [120])
            #expect(segments.filter { $0.kind == .planned }.map(\.interval.duration) == [360])
            let recorded = store.entries[0].recorded
            try store.reassignEntry(id: id, taskName: "Review :work")
            #expect(store.entries[0].recorded == recorded && store.runningTask?.name == "Review")
            let report = StatisticsReport(tasks: store.tasks, entries: store.entries, interval: range, now: clock.now)
            #expect(report.total == 180 && report.sessions.count == 2)
            #expect(report.rows(grouping: .tags).map(\.name) == [":work"])
            #expect(throws: TrackingError.entryHasRecordedTime) {
                try store.rescheduleEntry(id: id, start: base + 1_200, end: base + 1_800)
            }
            try store.deleteEntry(id: id)
            #expect(store.entries.isEmpty && store.tasks.isEmpty && store.runningEntry == nil)
            #expect(try TrackingStore(url: url, now: { clock.now }).entries.isEmpty)
        }
    }

    @Test func resizingStartOfRunningEntryCorrectsRecordedTime() throws {
        try fixture { store, _, clock in
            try store.createEntry(named: "Build", selection: EntrySelection(start: base - 60, end: base + 600))
            let id = store.entries[0].id
            try store.resizeEntry(id: id, edge: .start, to: base - 120)
            #expect(store.entries[0].recorded.count == 1)
            #expect(store.entries[0].duration(at: clock.now) == 120)
            try store.resizeEntry(id: id, edge: .end, to: base + 900)
            #expect(store.entries[0].duration(at: clock.now) == 120)
            clock.now += 60
            try store.finishScheduledEntry(id: id)
            #expect(store.entries.count == 1 && store.entries[0].duration(at: clock.now) == 180)
            try store.updateEntry(id: id, taskID: store.entries[0].taskID, start: base - 180, end: clock.now)
            #expect(store.entries[0].recorded.count == 1 && store.entries[0].duration(at: clock.now) == 240)
        }
    }

    @Test func overwriteFutureMiddleKeepsBothRemainingReservations() throws {
        try fixture { store, _, _ in
            try store.createEntry(named: "Build", selection: EntrySelection(start: base + 60, end: base + 600))
            try store.createEntry(named: "Read", selection: EntrySelection(start: base + 180, end: base + 300, overwritesExisting: true))
            #expect(store.entries.count == 3)
            #expect(store.entries.allSatisfy { $0.state == .scheduled && $0.recorded.isEmpty })
            #expect(store.scheduledEntries.count == 3)
        }
    }

    @Test func resizingPausedEntryPreservesWorkInsideItsGap() throws {
        try fixture { store, _, clock in
            try store.createEntry(named: "Build", selection: EntrySelection(start: base - 60, end: base + 600))
            let id = store.entries[0].id
            try store.stop(preservingPlan: true)
            clock.now += 60
            try store.startTask(named: "Other")
            clock.now += 60
            try store.stop()
            let other = store.entries[1]
            try store.resizeEntry(id: id, edge: .end, to: base + 900)
            #expect(store.entries[0].state == .paused && store.entries[1] == other)
            #expect(store.entries[0].duration(at: clock.now) == 60)
            #expect(store.runningEntry == nil)
        }
    }

    @Test func failedMigrationPreservesOriginalAndBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        let taskID = UUID(), duplicateID = UUID()
        var old = TrackingSnapshot()
        old.version = 2
        old.plans = [LegacyPlannedEntry(id: duplicateID, taskID: taskID, start: base, end: base + 60, state: .scheduled),
                     LegacyPlannedEntry(id: duplicateID, taskID: taskID, start: base + 120, end: base + 180, state: .scheduled)]
        let data = try JSONEncoder().encode(old)
        try data.write(to: url)
        for _ in 0..<2 {
            #expect(throws: TrackingError.unsupportedStoreVersion) { try TrackingStore(url: url) }
            #expect(try Data(contentsOf: url) == data)
            #expect(try Data(contentsOf: url.appendingPathExtension("before-unified-entries-v2.json")) == data)
        }
    }

    @Test(arguments: [LegacyPlanState.active, .paused, .completed, .missed, .skipped])
    func migratesVersionTwoWithoutLosingHistoryOrCountingGaps(state: LegacyPlanState) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tracking.json")
        let task = TrackedTask(id: UUID(), name: "Build", color: .green, tags: ["coding"])
        let firstID = UUID(), runningID = UUID(), planID = UUID()
        let planEnd = base + 600
        let linked = state == .active
        var original = TrackingSnapshot()
        original.version = 2
        original.tasks = [task]
        original.defaultZoomHours = 12
        original.statisticsDayStartHour = 4
        original.entries = [TimeEntry(id: firstID, taskID: task.id, start: base, end: base + 60),
                            TimeEntry(id: runningID, taskID: task.id, start: base + 120, end: linked ? nil : base + 180)]
        original.plans = [LegacyPlannedEntry(id: planID, taskID: task.id, start: base, end: planEnd,
                                            state: state, runningEntryID: linked ? runningID : nil)]
        original.checkpoint = linked ? base + 180 : nil
        // Match the old on-disk format, which had neither state nor recorded on entries.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["entries"] = (json["entries"] as! [[String: Any]]).map { value in
            value.filter { $0.key != "recorded" && $0.key != "state" }
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: url)
        let store = try TrackingStore(url: url, now: { base + 240 })
        #expect(store.entries.count == 1)
        let entry = try #require(store.entries.first)
        #expect(entry.id == (linked ? runningID : planID))
        #expect(entry.start == base && entry.end == planEnd)
        #expect(entry.recorded.count == 2 && entry.duration(at: base + 240) == 120)
        #expect(entry.state == (linked ? .paused : EntryState(rawValue: state.rawValue)))
        #expect(store.defaultZoomHours == 12 && store.statisticsDayStartHour == 4 && store.tasks == [task])
        let backup = url.appendingPathExtension("before-unified-entries-v2.json")
        #expect(try Data(contentsOf: backup) == data)
        let persisted = try Data(contentsOf: url)
        let converted = try #require(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        #expect(converted["version"] as? Int == 3 && converted["plans"] == nil)
        let reopened = try TrackingStore(url: url, now: { base + 300 })
        #expect(reopened.entries == store.entries)
        #expect(try Data(contentsOf: url) == persisted)
        #expect(try Data(contentsOf: backup) == data)
    }

    @Test func migrationPartitionsOverlappingHistoryWithoutChangingTotal() throws {
        let taskID = UUID(), recordID = UUID()
        var old = TrackingSnapshot()
        old.version = 2
        old.entries = [TimeEntry(id: recordID, taskID: taskID, start: base - 60, end: base + 900)]
        old.plans = [LegacyPlannedEntry(id: UUID(), taskID: taskID, start: base, end: base + 300, state: .completed),
                     LegacyPlannedEntry(id: UUID(), taskID: taskID, start: base + 180, end: base + 600, state: .missed)]
        let unified = try old.unifyingEntries()
        #expect(unified.entries.reduce(0) { $0 + $1.duration(at: base + 1_000) } == 960)
        #expect(unified.entries.first?.id == recordID)
        let parts = unified.entries.flatMap(\.recorded).sorted { $0.start < $1.start }
        #expect(Set(parts.map(\.id)).count == parts.count)
        for (a, b) in zip(parts, parts.dropFirst()) { #expect(a.end == b.start) }
    }

    private final class Clock {
        var now: Date
        init(now: Date) { self.now = now }
    }
}
