import AppKit
import SwiftUI
import LineCore

@main
enum TapeApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = makeMainMenu(delegate: delegate)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor
    private static func makeMainMenu(delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        let application = NSMenu()
        let settings = application.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openMainWindow(_:)), keyEquivalent: ",")
        settings.target = delegate
        application.addItem(.separator())
        application.addItem(withTitle: "Quit Tape", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = window
        menu.addItem(windowItem)
        NSApplication.shared.windowsMenu = window
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
    private(set) var continuationPanel: ContinuationPanel?
    private var continuationTimer: Timer?
    private var presentedContinuationID: UUID?
    private(set) var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["LINE_DATA_DIRECTORY"] {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                // Keep the original data directory across app renames.
                .appendingPathComponent("Line", isDirectory: true)
        }
        model = AppModel(storeURL: directory.appendingPathComponent("tracking.json"))
        model.onChange = { [weak self] in
            self?.updateStatus()
            self?.syncContinuation()
        }

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
            continuationPanel?.dismiss()
        case .unlocked, .didWake:
            break
        }
    }

    private func syncContinuation() {
        guard let interruptions = model.interruptions else { return }
        if interruptions.needsContinuationPolling, continuationTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.pollContinuation()
                    if let seconds = self?.model.interruptions?.remainingSeconds {
                        self?.continuationPanel?.updateCountdown(seconds: seconds)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            continuationTimer = timer
        } else if !interruptions.needsContinuationPolling {
            continuationTimer?.invalidate()
            continuationTimer = nil
        }
        guard let pending = interruptions.pendingContinuation else {
            continuationPanel?.dismiss()
            continuationPanel = nil
            presentedContinuationID = nil
            return
        }
        guard pending.id != presentedContinuationID, let button = statusItem.button else { return }
        presentedContinuationID = pending.id
        continuationPanel?.dismiss()
        guard !popover.isShown else {
            model.acceptContinuation()
            return
        }
        let panel = ContinuationPanel(task: pending.task, remainingSeconds: interruptions.remainingSeconds,
                                      hoverChanged: { [weak self] hovered in
                                          self?.model.setContinuationHovered(hovered, id: pending.id)
                                      },
                                      accept: { [weak self] in self?.model.acceptContinuation() },
                                      reject: { [weak self] in self?.model.rejectContinuation() })
        continuationPanel = panel
        panel.show(below: button)
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
        guard model.finishCreation() else { return }
        model.acceptContinuation()
        continuationPanel?.dismiss()
        popover.close()
        let menu = makeActionsMenu()

        // Let the status item present its native menu, then restore left-click handling.
        statusItem.menu = menu
        defer { statusItem.menu = nil }
        statusItem.button?.performClick(nil)
    }

    func makeActionsMenu() -> NSMenu {
        let menu = NSMenu()
        for page in SettingsPage.allCases {
            let item = menu.addItem(withTitle: page.menuTitle, action: #selector(openSettingsPage(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)
            item.representedObject = page.rawValue
            item.target = self
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Tape", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)

        return menu
    }

    @objc func openMainWindow(_ sender: Any?) {
        presentMainWindow()
    }

    @objc private func openSettingsPage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let page = SettingsPage(rawValue: rawValue) else { return }
        presentMainWindow(page: page)
    }

    private func presentMainWindow(page: SettingsPage? = nil) {
        guard model.finishCreation() else { return }
        model.acceptContinuation()
        continuationPanel?.dismiss()
        popover.close()
        model.cancelEntry()
        if mainWindowController == nil {
            mainWindowController = MainWindowController(model: model)
        }
        mainWindowController?.present(page: page)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = mainWindowController?.window, window.isVisible || window.isMiniaturized {
            openMainWindow(nil)
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        model.acceptContinuation()
        continuationPanel?.dismiss()
        model.preparePopover()
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let controller = NSHostingController(rootView: TrackingPopover(model: model, dismiss: { [weak self] in
            self?.popover.performClose(nil)
        }, openMainWindow: { [weak self] in
            self?.openMainWindow(nil)
        }, contentSizeDidChange: { [weak self] size in
            self?.resizePopover(to: size)
        }))
        popover.contentViewController = controller
        // AppKit anchors using the initial size. A later shrink otherwise leaves a gap below the icon.
        popover.contentSize = controller.view.fittingSize
        // User-initiated opening activates Tape. Continuation uses a non-activating panel.
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

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        model.finishCreation()
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
            popover.performClose(nil)
        }
    }

    private func updateStatus() {
        let running = model.store?.runningTask
        let glyph = model.errorMessage != nil
            ? NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Tape")
            : Self.playheadIcon(isTracking: running != nil)
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
        let description = model.errorMessage.map { "Tape: \($0)" }
            ?? running.map { "Tape: tracking \($0.name)" } ?? "Tape: not tracking"
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
    }

    private static func playheadIcon(isTracking: Bool) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.scale(by: 0.75)
            transform.concat()
            NSColor.black.set()

            if isTracking {
                NSBezierPath(roundedRect: NSRect(x: 2, y: 10, width: 12, height: 7),
                             xRadius: 2, yRadius: 2).fill()
            }
            let strip = NSBezierPath(roundedRect: NSRect(x: 2, y: 10, width: 20, height: 7),
                                     xRadius: 2, yRadius: 2)
            strip.lineWidth = 1.7
            strip.stroke()

            let flag = NSBezierPath()
            flag.move(to: NSPoint(x: 11, y: 2))
            flag.line(to: NSPoint(x: 17, y: 2))
            flag.line(to: NSPoint(x: 17, y: 6))
            flag.line(to: NSPoint(x: 14, y: 9))
            flag.line(to: NSPoint(x: 11, y: 6))
            flag.close()
            flag.fill()

            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 14, y: 8))
            stem.line(to: NSPoint(x: 14, y: 22))
            stem.lineWidth = 1.7
            stem.lineCapStyle = .round
            stem.stroke()
            return true
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.stop() else {
            showPopover()
            return .terminateCancel
        }
        checkpointTimer?.invalidate()
        continuationTimer?.invalidate()
        continuationPanel?.dismiss()
        return .terminateNow
    }
}
