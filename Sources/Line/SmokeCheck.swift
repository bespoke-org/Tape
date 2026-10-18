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

            // Native Stop is a SwiftUI button. Its public accessibility action stays within this process.
            let content = try contentView(popover)
            try pressAccessibleButton(named: "Stop", in: content)
            try await settle()
            try require(model.store?.runningTask == nil, "Stop button must end tracking")
            try Data("PASS: native status item, no Dock policy, task picker reveal/focus/collapse/Escape, task field submission, start/switch/stop, live duration, close/reopen, popover anchoring through content resizing.\n".utf8)
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
#endif
