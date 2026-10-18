#if DEBUG
import AppKit
import LineCore

/// Bounded, opt-in verification of the actual packaged app, using an isolated data directory.
/// Drives its own native field editor without requiring system-wide Accessibility permission.
@MainActor
enum SmokeCheck {
    private static var initialContentGap: CGFloat?
    static func run(button: NSStatusBarButton, popover: NSPopover, model: AppModel, output: URL) async {
        initialContentGap = nil
        // Keep unrelated desktop clicks from dismissing this isolated test window.
        // Closing through the status item is still exercised below.
        let originalBehavior = popover.behavior
        popover.behavior = .applicationDefined
        defer { popover.behavior = originalBehavior }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try require(NSApp.activationPolicy() == .accessory, "App must have no Dock icon")
            try require(button.image != nil, "Status item must have an icon")
            if ProcessInfo.processInfo.environment["LINE_SMOKE_TIMELINE"] == "1" {
                try await checkTimeline(button: button, popover: popover, model: model)
                try Data("PASS: horizontal/Shift scroll, scoped input, pinch anchors, Now, saved zoom across reopen, stable popover.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            for name in ["Planning", "Writing", "Review", "Research"] {
                try require(model.start(name), "Seed reusable tasks")
                try require(model.stop(), "Stop seed entries")
            }
            let initialEntryCount = model.store!.entries.count
            try await settle()
            try clickStatusItem(button)
            try await settle()
            try require(popover.isShown, "Status item must open its popover")
            try requireAnchored(popover, to: button)
            try await requireStablePosition(popover)

            try requirePickerHidden(popover)
            try await openPicker(named: "Start task", in: popover)
            try requireAnchored(popover, to: button)
            try enterTaskName("Build Line", in: popover)
            try await settle()
            try require(model.store?.runningTask?.name == "Build Line", "Submitting the native text field must start tracking")
            try requirePickerHidden(popover)
            try requireAnchored(popover, to: button)
            let firstStart = model.store?.runningEntry?.start
            try await Task.sleep(for: .seconds(1))
            try require((model.store?.runningEntry?.duration(at: .now) ?? 0) >= 1, "Running entry must grow")

            try await openPicker(named: "Switch task", in: popover)
            try requireAnchored(popover, to: button)
            try enterTaskName("Read", in: popover)
            try await settle()
            try require(model.store?.runningTask?.name == "Read", "Submitting another name must switch tasks")
            try require(model.store?.entries.count == initialEntryCount + 2, "Switching must preserve the first entry")
            try require(model.store?.entries[initialEntryCount].start == firstStart, "Switching must preserve the original start")
            try require(model.store?.entries[initialEntryCount].end == model.store?.runningEntry?.start, "Switched entries must touch")
            try requirePickerHidden(popover)
            try requireAnchored(popover, to: button)
            try await openPicker(named: "Switch task", in: popover)
            try pressAccessibleButton(named: "Switch to Build Line", in: contentView(popover))
            try await settle()
            try require(model.store?.runningTask?.name == "Build Line", "Choosing an existing task must switch tracking")
            try requirePickerHidden(popover)
            try requireAnchored(popover, to: button)
            try await requireStablePosition(popover)
            try await openPicker(named: "Switch task", in: popover)
            try enterTaskName("No matching task", in: popover, submit: false)
            try await settle()
            try requireAnchored(popover, to: button)
            try enterTaskName("", in: popover, submit: false)
            try await settle()
            try requireAnchored(popover, to: button)
            let window = try contentView(popover).window!
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            window.sendEvent(escape)
            try await settle()
            try require(popover.isShown, "Escape in the picker must keep the timeline open")
            try requirePickerHidden(popover)
            try requireAnchored(popover, to: button)
            try clickStatusItem(button)
            try await settle()
            try require(!popover.isShown, "Status item must close its popover")
            try require(popover.contentViewController == nil, "Closing must remove the rendering schedule")
            try require(model.store?.runningTask?.name == "Build Line", "Closing must not stop tracking")
            try clickStatusItem(button)
            try await settle()
            try require(popover.isShown, "Popover must reopen")
            try requirePickerHidden(popover)
            try requireAnchored(popover, to: button)
            try await requireStablePosition(popover)

            // Native Stop is a SwiftUI button. Its public accessibility action stays within this process.
            let content = try contentView(popover)
            try pressAccessibleButton(named: "Stop", in: content)
            try await settle()
            try require(model.store?.runningTask == nil, "Stop button must end tracking")
            try await requireStablePosition(popover)
            try Data("PASS: native status item, no Dock policy, task picker reveal/focus/collapse/Escape, task field submission, start/switch/stop, live duration, close/reopen, popover anchoring through content resizing, stable resting position and height.\n".utf8)
                .write(to: output.appendingPathComponent("result.txt"))
            NSApp.terminate(nil)
        } catch {
            let message = "FAIL: \(error.localizedDescription)\n"
            try? Data(message.utf8).write(to: output.appendingPathComponent("result.txt"))
            fputs(message, stderr)
            exit(1)
        }
    }

    private static func settle() async throws {
        try await Task.sleep(for: .milliseconds(600))
    }

    private static func checkTimeline(button: NSStatusBarButton, popover: NSPopover, model: AppModel) async throws {
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try requireAnchored(popover, to: button)
        let content = try contentView(popover)
        guard let input = descendants(content).compactMap({ $0 as? TimelineInputView }).first,
              let window = input.window else {
            throw NSError(domain: "LineSmokeCheck", code: 9, userInfo: [NSLocalizedDescriptionKey: "Timeline input is missing"])
        }
        let initialSpan = model.store!.timelineSpan
        try require(model.timeline.span == initialSpan && model.timeline.isFollowingNow, "Opening must restore saved zoom and follow now")
        let location = input.convert(NSPoint(x: input.bounds.width / 4, y: input.bounds.height / 2), to: nil)
        let vertical = TimelineTestEvent(type: .scrollWheel, window: window, location: location, dy: 20)
        try require(!input.handle(vertical) && model.timeline.isFollowingNow, "Unmodified vertical scrolling must not browse")
        let horizontal = TimelineTestEvent(type: .scrollWheel, window: window, location: location, dx: input.bounds.width)
        try require(input.handle(horizontal) && !model.timeline.isFollowingNow, "Horizontal scrolling must enter browsing")
        try await settle()
        let range = model.timeline.range(at: .now)
        try require(range.end < .now, "Scrolling a width into history must move actual now offscreen")
        let shift = TimelineTestEvent(type: .scrollWheel, window: window, location: location, dy: -10, flags: .shift)
        try require(input.handle(shift), "Shift-wheel must browse")
        let shifted = model.timeline.range(at: .now)
        try require(shifted.start > range.start, "Opposite scroll must move toward the future")
        let outside = TimelineTestEvent(type: .scrollWheel, window: window, location: NSPoint(x: -100, y: -100), dx: 50)
        try require(!input.handle(outside) && model.timeline.range(at: .now) == shifted, "Input outside the timeline must not navigate")
        let anchor = model.timeline.date(at: 0.25, now: .now)
        _ = input.handle(TimelineTestEvent(type: .magnify, window: window, location: location, magnification: 0.5, phase: .began))
        _ = input.handle(TimelineTestEvent(type: .magnify, window: window, location: location, magnification: 0.5, phase: .changed))
        _ = input.handle(TimelineTestEvent(type: .magnify, window: window, location: location, phase: .ended))
        try require(model.timeline.span == initialSpan / 2, "Pinch increments must accumulate to a twofold zoom")
        try require(abs(model.timeline.date(at: 0.25, now: .now).timeIntervalSince(anchor)) < 0.001, "Pinch must preserve the time under the pointer")
        try require(model.store?.timelineSpan == initialSpan / 2, "Ending the pinch must persist zoom")
        let outsideReset = TimelineTestEvent(type: .smartMagnify, window: window, location: NSPoint(x: -100, y: -100))
        try require(!input.handle(outsideReset) && model.timeline.span == initialSpan / 2, "Smart zoom outside the timeline must be ignored")
        let center = model.timeline.date(at: 0.5, now: .now)
        let reset = TimelineTestEvent(type: .smartMagnify, window: window, location: location)
        try require(input.handle(reset), "Two-finger double-tap must be handled")
        try require(model.timeline.span == TimelineViewport.defaultSpan && model.store?.timelineSpan == TimelineViewport.defaultSpan, "Smart zoom must reset and save the four-hour scale")
        try require(!model.timeline.isFollowingNow && abs(model.timeline.date(at: 0.5, now: .now).timeIntervalSince(center)) < 0.001, "Resetting zoom must preserve the browsed center")
        _ = input.handle(reset)
        try require(model.timeline.span == TimelineViewport.defaultSpan && model.timeline.isFollowingNow, "A second double-tap must return to Now at the default scale")
        _ = input.handle(reset)
        try require(model.timeline.isFollowingNow, "Further double-taps at Now must keep following")
        // Leave a nondefault scale for the reopen and fresh-process persistence checks.
        _ = input.handle(TimelineTestEvent(type: .magnify, window: window, location: location,
                                         magnification: TimelineViewport.defaultSpan / (initialSpan / 2) - 1, phase: .began))
        _ = input.handle(TimelineTestEvent(type: .magnify, window: window, location: location, phase: .ended))
        _ = input.handle(horizontal)
        try await settle()
        try requireAnchored(popover, to: button)
        try await requireStablePosition(popover)
        try pressAccessibleButton(named: "Return to Now", in: contentView(popover))
        try await settle()
        try require(model.timeline.isFollowingNow, "Now must resume following")
        _ = input.handle(horizontal)
        try clickStatusItem(button)
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try require(model.timeline.isFollowingNow && model.timeline.span == initialSpan / 2, "Reopening must follow now at the saved scale")
        try requireAnchored(popover, to: button)
        try await requireStablePosition(popover)
    }

    private static func requireStablePosition(_ popover: NSPopover) async throws {
        var tops: [CGFloat] = []
        var heights: [CGFloat] = []
        for _ in 0..<50 {
            let view = try contentView(popover)
            guard let window = view.window else { throw NSError(domain: "LineSmokeCheck", code: 8) }
            tops.append(window.convertToScreen(view.convert(view.bounds, to: nil)).maxY)
            heights.append(view.bounds.height)
            try await Task.sleep(for: .milliseconds(20))
        }
        let movement = tops.max()! - tops.min()!
        try require(movement <= 0.25, "Idle popover must not shake; its content moved \(movement) points in one second")
        let resizing = heights.max()! - heights.min()!
        try require(resizing <= 0.25, "Idle popover must not resize repeatedly; its content height varied by \(resizing) points in one second")
    }

    private static func requirePickerHidden(_ popover: NSPopover) throws {
        let fields = descendants(try contentView(popover)).compactMap { $0 as? NSTextField }
        try require(!fields.contains(where: \.isEditable), "Task picker must be hidden by default and after selection or Escape")
    }

    private static func openPicker(named title: String, in popover: NSPopover) async throws {
        try pressAccessibleButton(named: title, in: contentView(popover))
        try await settle()
        let fields = descendants(try contentView(popover)).compactMap { $0 as? NSTextField }
        try require(fields.contains(where: { $0.isEditable && $0.currentEditor() != nil }), "Revealing the picker must focus its search field")
    }

    private static func requireAnchored(_ popover: NSPopover, to button: NSStatusBarButton) throws {
        guard let anchorWindow = button.window, let window = popover.contentViewController?.view.window else {
            throw NSError(domain: "LineSmokeCheck", code: 8, userInfo: [NSLocalizedDescriptionKey: "Popover or status item has no window"])
        }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let gap = anchor.minY - window.frame.maxY
        let view = popover.contentViewController!.view
        let content = window.convertToScreen(view.convert(view.bounds, to: nil))
        let contentGap = anchor.minY - content.maxY
        if let initialContentGap {
            try require(abs(contentGap - initialContentGap) <= 2, "Popover content must stay anchored; initial gap \(initialContentGap), current gap \(contentGap)")
        } else {
            initialContentGap = contentGap
        }
        try require(abs(gap) <= 12, "Popover must stay attached to its status item; vertical gap is \(gap) points (anchor: \(anchor), window: \(window.frame))")
    }

    private static func clickStatusItem(_ button: NSStatusBarButton) throws {
        guard let action = button.action else {
            throw NSError(domain: "LineSmokeCheck", code: 5, userInfo: [NSLocalizedDescriptionKey: "Status item has no action"])
        }
        try require(NSApp.sendAction(action, to: button.target, from: button), "Status item action must be delivered")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "LineSmokeCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private static func contentView(_ popover: NSPopover) throws -> NSView {
        guard let view = popover.contentViewController?.view else {
            throw NSError(domain: "LineSmokeCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Popover has no content"])
        }
        return view
    }

    private static func enterTaskName(_ name: String, in popover: NSPopover, submit: Bool = true) throws {
        let content = try contentView(popover)
        guard let field = descendants(content).compactMap({ $0 as? NSTextField }).first(where: \.isEditable),
              let window = field.window else {
            throw NSError(domain: "LineSmokeCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "Native task field is missing"])
        }
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else {
            throw NSError(domain: "LineSmokeCheck", code: 4, userInfo: [NSLocalizedDescriptionKey: "Task field did not receive focus"])
        }
        editor.selectAll(nil)
        editor.insertText(name, replacementRange: editor.selectedRange())
        guard submit else { return }
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) else { return }
        window.sendEvent(event)
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private static func pressAccessibleButton(named name: String, in root: NSView) throws {
        guard let object = accessibilityElement(named: name, in: root),
              attribute("accessibilityRole", of: object) as? String == NSAccessibility.Role.button.rawValue else {
            throw NSError(domain: "LineSmokeCheck", code: 6, userInfo: [NSLocalizedDescriptionKey: "Accessible \(name) button is missing"])
        }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector), let implementation = object.method(for: selector) else {
            throw NSError(domain: "LineSmokeCheck", code: 7, userInfo: [NSLocalizedDescriptionKey: "Accessible \(name) button has no press action"])
        }
        // SwiftUI nodes implement public accessibility methods without declaring the full protocol.
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let pressed = unsafeBitCast(implementation, to: Press.self)(object, selector)
        try require(pressed, "Accessible \(name) button must be operable")
    }

    private static func accessibilityElement(named name: String, in element: Any) -> NSObject? {
        guard let object = element as? NSObject else { return nil }
        if attribute("accessibilityLabel", of: object) as? String == name || attribute("accessibilityTitle", of: object) as? String == name {
            return object
        }
        for child in attribute("accessibilityChildren", of: object) as? [Any] ?? [] {
            if let found = accessibilityElement(named: name, in: child) { return found }
        }
        return nil
    }

    private static func attribute(_ name: String, of object: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
}

/// Deterministic AppKit inputs exercise the same handler as the local event monitor.
private final class TimelineTestEvent: NSEvent {
    private let kind: NSEvent.EventType
    private let target: NSWindow
    private let location: NSPoint
    private let dx: CGFloat
    private let dy: CGFloat
    private let flags: NSEvent.ModifierFlags
    private let amount: CGFloat
    private let gesturePhase: NSEvent.Phase

    init(type: NSEvent.EventType, window: NSWindow, location: NSPoint, dx: CGFloat = 0, dy: CGFloat = 0,
         flags: NSEvent.ModifierFlags = [], magnification: CGFloat = 0, phase: NSEvent.Phase = []) {
        kind = type; target = window; self.location = location
        self.dx = dx; self.dy = dy; self.flags = flags
        amount = magnification; gesturePhase = phase
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
    override var type: NSEvent.EventType { kind }
    override var window: NSWindow? { target }
    override var locationInWindow: NSPoint { location }
    override var scrollingDeltaX: CGFloat { dx }
    override var scrollingDeltaY: CGFloat { dy }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var modifierFlags: NSEvent.ModifierFlags { flags }
    override var magnification: CGFloat { amount }
    override var phase: NSEvent.Phase { gesturePhase }
}
#endif
