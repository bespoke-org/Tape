#if DEBUG
import AppKit
import LineCore
import Testing
@testable import Line

@MainActor
struct SmokeReadinessTests {
    @Test func overwriteDrawingStartsOutsideResizeHandlesAtEverySnapPhase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storeURL: directory.appendingPathComponent("tracking.json"))
        let store = try #require(model.store)
        // The real reverse overwrite ends at 0.44 and snaps to five-minute boundaries.
        // Cover every second of that grid with the popover's 580-point timeline.
        for phase in 0..<300 {
            for entry in store.entries { try store.deleteEntry(id: entry.id) }
            let instant = Date(timeIntervalSince1970: 1_700_000_000 + Double(phase))
            model.timeline = TimelineViewport()
            model.timeline.pauseFollowing(at: instant)
            try store.createEntry(named: "Replacement", selection: store.prepareEntry(
                from: model.timeline.date(at: 0.44, now: instant),
                to: model.timeline.date(at: 0.10, now: instant),
                snap: model.timeline.entrySnap, overwriting: true))

            try #require(model.resizeEdge(at: SmokeCheck.overwriteThroughNowStart, tolerance: 5.0 / 580) == nil,
                         "The overwrite smoke drag hits a resize handle at snap phase \(phase)")
        }
    }

    @Test func waitsForControlThatAppearsAfterTheOldSettleDelay() async throws {
        let root = SmokeAccessibilityRoot()
        let reveal = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(750))
            root.ready = true
        }
        defer { reveal.cancel() }

        try await SmokeCheck.pressAccessibleControl(named: "Switch task", in: root, timeout: .seconds(2))

        #expect(root.control.pressCount == 1)
    }

    @Test func missingControlFailsWithinItsDeadline() async {
        let root = SmokeAccessibilityRoot()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await SmokeCheck.pressAccessibleControl(named: "Switch task", in: root, timeout: .milliseconds(100))
            Issue.record("A missing control must fail")
        } catch {
            #expect(error.localizedDescription.contains("Switch task"))
        }
        #expect(start.duration(to: clock.now) < .seconds(2))
        #expect(root.control.pressCount == 0)
    }

    @Test func failedPressIsNotRetried() async {
        let root = SmokeAccessibilityRoot()
        root.ready = true
        root.control.pressSucceeds = false
        do {
            try await SmokeCheck.pressAccessibleControl(named: "Switch task", in: root)
            Issue.record("An inoperable control must fail")
        } catch {
            #expect(error.localizedDescription.contains("must be operable"))
        }
        #expect(root.control.pressCount == 1)
    }
}

@MainActor
private final class SmokeAccessibilityRoot: NSView {
    let control = SmokeAccessibilityControl()
    var ready = false

    override func accessibilityChildren() -> [Any]? { ready ? [control] : [] }
}

// Like SwiftUI, this node implements public selectors without declaring the protocol.
@MainActor
private final class SmokeAccessibilityControl: NSObject {
    var pressCount = 0
    var pressSucceeds = true

    @objc func accessibilityLabel() -> String { "Switch task" }
    @objc func accessibilityRole() -> String { NSAccessibility.Role.button.rawValue }
    @objc func accessibilityPerformPress() -> Bool {
        pressCount += 1
        return pressSucceeds
    }
}
#endif
