#if DEBUG
import Foundation
import LineCore
import Testing
@testable import Line

@MainActor
struct CreationDismissalTests {
    private func withModel(_ body: (AppModel, TrackingStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storeURL: directory.appendingPathComponent("data/tracking.json"))
        try body(model, #require(model.store))
    }

    private func draw(_ model: AppModel, from: Double = 0.1, to: Double = 0.2,
                      overwriting: Bool = false) throws {
        try #require(model.beginDrawing(at: from, overwriting: overwriting))
        model.finishDrawing(at: to, tolerance: 0.001)
        try #require(model.entrySelection != nil)
    }

    @Test func dismissalSavesDrawnRangeAndTagsExactlyOnce() throws {
        try withModel { model, store in
            try draw(model)
            let selection = try #require(model.entrySelection)
            model.creationName = "  Building Tape :coding  "
            #expect(model.finishCreation())
            #expect(model.finishCreation())
            let entry = try #require(store.entries.first)
            #expect(store.entries.count == 1)
            #expect(entry.start == selection.start && entry.end == selection.end)
            #expect(store.tasks.first?.name == "Building Tape")
            #expect(store.tasks.first?.tags == ["coding"])
            #expect(model.creationName == nil && model.entrySelection == nil)
            #expect(try TrackingStore(url: model.dataURL).entries == store.entries)
        }
    }

    @Test func startAndSwitchBeginAtDismissal() throws {
        try withModel { model, store in
            for name in ["First", "Second"] {
                try #require(model.beginCreation())
                model.creationName = name
                let beforeSave = Date.now
                #expect(model.finishCreation())
                #expect(store.runningTask?.name == name)
                #expect(try #require(store.runningEntry).start >= beforeSave)
            }
            #expect(store.entries.count == 2)
            #expect(store.entries[0].end == store.entries[1].start)
        }
    }

    @Test func drawnRunningEntryRetainsItsStart() throws {
        try withModel { model, store in
            try draw(model, from: 0.4, to: 0.6)
            let selection = try #require(model.entrySelection)
            #expect(try #require(selection.end) > .now)
            model.creationName = "Already working"
            #expect(model.finishCreation())
            #expect(store.runningEntry?.start == selection.start)
            #expect(store.activePlan?.end == selection.end)
        }
    }

    @Test(arguments: [1.0, 8.0, 24.0], [-8.0, 8.0, 24.0])
    func drawingPreviewAndSaveAgreeNearNow(hours: Double, offset: Double) throws {
        try withModel { model, store in
            model.timeline = TimelineViewport(span: hours * 3_600)
            let tolerance = 12.0 / 600
            let end = 0.5 + offset / 600
            try #require(model.beginDrawing(at: 0.25, overwriting: false))
            model.updateDrawing(to: end, tolerance: tolerance)
            let preview = try #require(model.drawnRange)
            let shouldSnap = abs(offset) < 12
            if shouldSnap {
                #expect(abs(preview.end.timeIntervalSinceNow) < 1)
            } else {
                #expect(preview.end > .now)
            }
            model.finishDrawing(at: end, tolerance: tolerance)
            let selection = try #require(model.entrySelection)
            #expect((selection.end == nil) == shouldSnap)
            #expect(model.submitCreation(named: "Near Now"))
            #expect(store.runningEntry != nil)
            #expect((store.activePlan == nil) == shouldSnap)
        }
    }

    @Test(arguments: ["", "  \n ", ":coding"])
    func emptyNamesAreDiscarded(name: String) throws {
        try withModel { model, store in
            try draw(model)
            model.creationName = name
            #expect(model.finishCreation())
            #expect(store.entries.isEmpty && store.tasks.isEmpty)
            #expect(model.creationName == nil && model.entrySelection == nil)
        }
    }

    @Test func explicitCancellationDiscardsNamedDraft() throws {
        try withModel { model, store in
            try draw(model)
            model.creationName = "Discard me"
            model.cancelEntry()
            #expect(model.finishCreation())
            #expect(store.entries.isEmpty && store.tasks.isEmpty)
        }
    }

    @Test func overwritesStillRequireExplicitSubmission() throws {
        try withModel { model, store in
            try draw(model)
            try #require(model.submitCreation(named: "Original"))
            let original = store.entries
            try draw(model, overwriting: true)
            model.creationName = "Do not overwrite on dismissal"
            #expect(model.finishCreation())
            #expect(store.entries == original)
            try draw(model, overwriting: true)
            #expect(model.submitCreation(named: "Replacement"))
            #expect(store.tasks.map(\.name) == ["Replacement"])
        }
    }

    @Test func selectingAnotherEntrySavesBeforeChangingSelection() throws {
        try withModel { model, store in
            try draw(model)
            try #require(model.submitCreation(named: "Original"))
            let original = try #require(store.entries.first)
            try draw(model, from: 0.3, to: 0.4)
            model.creationName = "New entry"
            model.selectEntry(at: 0.15, minimumWidth: 0.001)
            #expect(store.entries.count == 2)
            #expect(model.editingEntryID == original.id)
            #expect(model.creationName == nil)
        }
    }

    @Test(arguments: [false, true])
    func failedSaveKeepsDraftAndBlocksNavigation(drawn: Bool) throws {
        try withModel { model, store in
            try draw(model)
            try #require(model.submitCreation(named: "Original"))
            let original = store.entries
            if drawn { try draw(model, from: 0.3, to: 0.4) }
            else { try #require(model.beginCreation()) }
            model.creationName = "Keep this draft :coding"
            let selection = model.entrySelection
            let directory = model.dataURL.deletingLastPathComponent()
            let backup = directory.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: directory, to: backup)
            try Data("Blocks directory creation".utf8).write(to: directory)
            #expect(!model.finishCreation())
            model.editEntry(id: original[0].id)
            #expect(!model.beginCreation())
            #expect(!model.beginDrawing(at: 0.05, overwriting: false))
            #expect(model.creationName == "Keep this draft :coding")
            #expect(model.entrySelection == selection && model.editingEntryID == nil)
            #expect(model.entryError != nil || model.errorMessage != nil)
            #expect(store.entries == original)
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.moveItem(at: backup, to: directory)
            #expect(model.finishCreation())
            #expect(store.entries.count == 2)
            #expect(model.creationName == nil)
        }
    }
}
#endif
