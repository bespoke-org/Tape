import AppKit
import SwiftUI
import LineCore

@main
enum LineApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = makeMainMenu()
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor
    private static func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        let application = NSMenu()
        application.addItem(withTitle: "Quit Line", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = application
        menu.addItem(applicationItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)
        return menu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var model: AppModel!
    private var checkpointTimer: Timer?
    private var outsideClickMonitor: Any?
    private var systemActivityMonitor: SystemActivityMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["LINE_DATA_DIRECTORY"] {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Line", isDirectory: true)
        }
        model = AppModel(storeURL: directory.appendingPathComponent("tracking.json"))
        model.onChange = { [weak self] in self?.updateStatus() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.delegate = self
        updateStatus()
        systemActivityMonitor = SystemActivityMonitor { [weak self] event in
            self?.handleSystemEvent(event)
        }

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.checkpoint() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        checkpointTimer = timer

        #if DEBUG
        if let argument = CommandLine.arguments.firstIndex(of: "--smoke-test"),
           CommandLine.arguments.indices.contains(argument + 1),
           ProcessInfo.processInfo.environment["LINE_DATA_DIRECTORY"] != nil {
            let output = URL(fileURLWithPath: CommandLine.arguments[argument + 1], isDirectory: true)
            Task { @MainActor in
                await SmokeCheck.run(button: statusItem.button!, popover: popover, model: model, output: output)
            }
        }
        #endif
    }

    func handleSystemEvent(_ event: SystemActivityEvent) {
        model.handleSystemEvent(event)
        switch event {
        case .locked, .willSleep:
            model.cancelEntry()
            popover.close()
        case .unlocked, .didWake:
            break
        }
    }

    @objc private func handleStatusItemClick() {
        let event = NSApplication.shared.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showActionsMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showActionsMenu() {
        popover.close()
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit Line", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)

        // Let the status item present its native menu, then restore left-click handling.
        statusItem.menu = menu
        defer { statusItem.menu = nil }
        statusItem.button?.performClick(nil)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        model.preparePopover()
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let controller = NSHostingController(rootView: TrackingPopover(model: model, dismiss: { [weak self] in
            self?.popover.performClose(nil)
        }, contentSizeDidChange: { [weak self] size in
            self?.resizePopover(to: size)
        }))
        popover.contentViewController = controller
        // AppKit anchors using the initial size. A later shrink otherwise leaves a gap below the icon.
        popover.contentSize = controller.view.fittingSize
        // This path is user-initiated. Automatic continuation gets its own non-activating path later.
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.dismissForOutsideClick()
            }
        }
    }

    private func resizePopover(to size: CGSize) {
        guard let controller = popover.contentViewController else { return }
        // Wait until SwiftUI has applied its layout, then refresh the native anchor.
        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self, let controller,
                  self.popover.isShown, self.popover.contentViewController === controller,
                  let button = self.statusItem.button else { return }
            self.popover.contentSize = size
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        // Destroy the TimelineView so no rendering schedule survives a closed popover.
        popover.contentViewController = nil
    }

    func dismissForOutsideClick() {
        // A nested menu can leave AppKit's transient dismissal inactive after it closes.
        if popover.behavior == .transient {
            popover.close()
        }
    }

    private func updateStatus() {
        let running = model.store?.runningTask
        let symbol = model.errorMessage != nil ? "exclamationmark.circle" :
            (running == nil ? "timeline.selection" : "record.circle")
        let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: "Line")
        // AppKit anchors status-item popovers to the image. Keep its canvas constant across states.
        let image = glyph.map { glyph in
            NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                let scale = min(1, rect.width / glyph.size.width, rect.height / glyph.size.height)
                let size = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
                glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                     width: size.width, height: size.height))
                return true
            }
        }
        image?.isTemplate = true
        statusItem.button?.image = image
        let description = model.errorMessage.map { "Line: \($0)" }
            ?? running.map { "Line: tracking \($0.name)" } ?? "Line: not tracking"
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.stop() else {
            showPopover()
            return .terminateCancel
        }
        checkpointTimer?.invalidate()
        return .terminateNow
    }
}
