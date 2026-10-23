#if DEBUG
import AppKit
import LineCore
import ServiceManagement
import SwiftUI

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
            if ProcessInfo.processInfo.environment["LINE_SMOKE_STATISTICS"] == "1" {
                try await checkStatistics(model: model, output: output)
                try Data("PASS: statistics navigation, chart drilldown, filters, search, small-window layout and unchanged tracking data.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_TAGS"] == "1" {
                try await checkTags(button: button, popover: popover, model: model, output: output)
                try Data("PASS: inline tags, native completion keys, search, editing, cleanup, and tracking continuity.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_MAIN_WINDOW"] == "1" {
                try await checkMainWindow(button: button, popover: popover, model: model, output: output)
                try Data("PASS: explicit single-window opening, native slider, default zoom, draft dismissal, frame restoration, minimize/reopen, Command-comma/Command-W, Dock policy, and tracking continuity.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_RESIZE_OVERWRITE"] == "1" {
                try await checkResizeOverwrite(button: button, popover: popover, model: model)
                try Data("PASS: Command before and during resize, stationary modifier changes, release to clamp, Escape cancellation, and overwrite commit.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_CONTINUATION"] == "1" {
                try await checkContinuation(button: button, popover: popover, model: model)
                try Data("PASS: continuation panel preserves focus, hover pauses the nine-second countdown, OK resumes immediately, Reject and explicit actions cancel, outside clicks preserve the notice and opening Tape accepts continuation, and short-break continuation reopens the original entry.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_SYSTEM_ACTIVITY"] == "1" {
                try await checkSystemActivity(button: button, popover: popover, model: model)
                try Data("PASS: lock/sleep notifications stop and save once, ignore display sleep, preserve return ordering, close drafts, and leave tracking stopped.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_DISMISSAL"] == "1" {
                popover.behavior = .transient
                try await checkDismissal(button: button, popover: popover, model: model)
                try Data("PASS: popover dismisses before and after opening its color menu.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_EDITING"] == "1" {
                try await checkEditing(button: button, popover: popover, model: model)
                try Data("PASS: inline entry editor, task reassignment and color changes, Escape, deletion confirmation/cancellation, running deletion, edge resizing, and stable anchoring.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_OVERWRITE"] == "1" {
                try await checkOverwrite(button: button, popover: popover, model: model)
                try Data("PASS: Command-drag overwrite, cancellation, split, multiple entries, task reuse, through-Now tracking, stable anchoring.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_CREATION"] == "1" {
                try await checkCreation(button: button, popover: popover, model: model)
                try Data("PASS: drawing, reverse selection, task creation/reuse, Escape, dismissal, selection boundaries, through-Now tracking, stable anchoring.\n".utf8)
                    .write(to: output.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["LINE_SMOKE_TIMELINE"] == "1" {
                try await checkTimeline(button: button, popover: popover, model: model)
                try Data("PASS: horizontal/Shift scroll, scoped input, pinch anchors, Now, configured default across reopen, temporary pinch zoom, stable popover.\n".utf8)
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
            try enterTaskName("Build Tape", in: popover)
            try await settle()
            try require(model.store?.runningTask?.name == "Build Tape", "Submitting the native text field must start tracking")
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
            try pressAccessibleControl(named: "Switch to Build Tape", in: contentView(popover))
            try await settle()
            try require(model.store?.runningTask?.name == "Build Tape", "Choosing an existing task must switch tracking")
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
            try require(model.store?.runningTask?.name == "Build Tape", "Closing must not stop tracking")
            try clickStatusItem(button)
            try await settle()
            try require(popover.isShown, "Popover must reopen")
            try requirePickerHidden(popover)
            try requireAnchored(popover, to: button)
            try await requireStablePosition(popover)

            // Native Stop is a SwiftUI button. Its public accessibility action stays within this process.
            let content = try contentView(popover)
            try pressAccessibleControl(named: "Stop", in: content)
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

    private static func checkLoginItemSettings() throws {
        var status = SMAppService.Status.notRegistered
        var registrationCount = 0
        var openedSettings = false
        var fail = false
        let setting = LoginItemSettings(readStatus: { status }, register: {
            registrationCount += 1
            if fail { throw NSError(domain: "LoginItemTest", code: 1) }
            status = .enabled
        }, unregister: {
            if fail { throw NSError(domain: "LoginItemTest", code: 2) }
            status = .notRegistered
        }, openSettings: { openedSettings = true })
        try require(!setting.isEnabled && registrationCount == 0, "Reading startup settings must not register the app")
        setting.setEnabled(true)
        try require(setting.isEnabled && registrationCount == 1, "Registering must reflect the resulting OS status")
        fail = true
        setting.setEnabled(false)
        try require(setting.isEnabled && setting.errorMessage != nil, "Failed unregister must retain the actual enabled state")
        fail = false
        setting.setEnabled(false)
        try require(!setting.isEnabled && setting.errorMessage == nil, "Successful unregister must refresh state and clear errors")
        fail = true
        setting.setEnabled(true)
        try require(!setting.isEnabled && setting.errorMessage != nil, "Failed register must not claim launch at login is enabled")
        status = .requiresApproval
        setting.refresh()
        try require(setting.needsApproval && !setting.isEnabled, "Pending approval must not claim an enabled login item")
        let attempts = registrationCount
        setting.setEnabled(true)
        try require(openedSettings && registrationCount == attempts, "Pending approval must direct the user to System Settings")
        status = .enabled
        setting.refresh()
        try require(setting.isEnabled && !setting.needsApproval, "External approval must refresh the toggle")
        status = .notFound
        setting.refresh()
        try require(!setting.isEnabled, "A missing service must not appear enabled")
        let missing = LoginItemSettings(readStatus: { .notFound }, register: {}, unregister: {}, openSettings: {})
        try require(missing.errorMessage == nil, "An unregistered app must not show a startup error before an enable attempt")
        missing.setEnabled(true)
        try require(!missing.isEnabled && missing.errorMessage != nil, "An enable attempt with a missing service must report an error")
    }

    private static func checkMainWindow(button: NSStatusBarButton, popover: NSPopover, model: AppModel, output: URL) async throws {
        guard let delegate = NSApp.delegate as? AppDelegate else { throw NSError(domain: "LineSmokeCheck", code: 10) }
        try require(delegate.mainWindowController == nil, "Launch must not create the main window")
        try checkLoginItemSettings()
        let firstLaunch = model.defaultZoomHours == 8
        try require(model.defaultZoomHours == (firstLaunch ? 8 : 12), "Configured zoom must survive a fresh process")
        try require(model.statisticsDayStartHour == (firstLaunch ? 0 : 4), "Statistics day start must survive a fresh process")
        try require(model.timeFormat == (firstLaunch ? .system : .twentyFourHour), "Time format must survive a fresh process")
        try require(model.resumeCountdownSeconds == (firstLaunch ? 9 : 15), "Resume countdown must survive a fresh process")
        try require(model.automaticResumeEnabled && model.shortBreakSeconds == (firstLaunch ? 300 : 30), "Resume preferences must survive a fresh process")
        let frameName = "Tape.MainWindow.\(ProcessInfo.processInfo.environment["LINE_DATA_DIRECTORY"]!)"
        let frameKey = "NSWindow Frame \(frameName)"
        let legacyFrameKey = "NSWindow Frame DayTape.MainWindow.\(ProcessInfo.processInfo.environment["LINE_DATA_DIRECTORY"]!)"
        if firstLaunch {
            let legacyWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 850, height: 650),
                                        styleMask: [.titled], backing: .buffered, defer: true)
            UserDefaults.standard.set(legacyWindow.frameDescriptor, forKey: legacyFrameKey)
        }
        if !firstLaunch {
            let saved = try String(contentsOf: output.appendingPathComponent("window-frame.txt"), encoding: .utf8)
            try require(UserDefaults.standard.string(forKey: frameKey) == saved, "Saved geometry must survive a fresh process")
        }
        try require(model.start("Window check"), "Tracking must start")
        let runningID = model.store!.runningEntry!.id
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try await openPicker(named: "Switch task", in: popover)
        try enterTaskName("Unsubmitted draft", in: popover, submit: false)
        try pressAccessibleControl(named: "Open Tape", in: contentView(popover))
        try await settle()
        guard let window = delegate.mainWindowController?.window,
              let content = window.contentView else { throw NSError(domain: "LineSmokeCheck", code: 11) }
        try require(window.isVisible && window.isKeyWindow && NSApp.activationPolicy() == .regular,
                    "Opening must focus the main window and enable Dock presence (visible=\(window.isVisible), key=\(window.isKeyWindow), policy=\(NSApp.activationPolicy().rawValue), active=\(NSApp.isActive), front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"))")
        try require(!popover.isShown && popover.contentViewController == nil, "Opening the window must dismiss and release the popover")
        try require(!model.store!.tasks.contains(where: { $0.name == "Unsubmitted draft" }), "Opening must discard unsubmitted text")
        try require(model.store?.runningEntry?.id == runningID, "Opening must keep the same running entry")
        try require(window.title == "Tape" && window.styleMask.contains([.resizable, .miniaturizable, .closable]),
                    "Main window must use normal native controls")
        if firstLaunch {
            try require(abs(window.frame.width - 850) < 1 && UserDefaults.standard.string(forKey: frameKey) != nil,
                        "Tape must restore the previous app name's saved window geometry")
            UserDefaults.standard.removeObject(forKey: legacyFrameKey)
        }
        guard let split = window.contentViewController as? NSSplitViewController else { throw NSError(domain: "LineSmokeCheck", code: 12) }
        try require(split.splitViewItems.count == 2 && split.splitViewItems[0].canCollapse, "Settings sidebar must support collapsing")
        guard let sidebar = descendants(split.splitViewItems[0].viewController.view).compactMap({ $0 as? NSOutlineView }).first else {
            throw NSError(domain: "LineSmokeCheck", code: 12, userInfo: [NSLocalizedDescriptionKey: "Native sidebar is missing"])
        }
        try require(sidebar.numberOfRows == 3 && sidebar.selectedRow == 0, "Sidebar must show General, Statistics, About, initially selecting General")
        guard let navigation = window.toolbar?.items.compactMap({ $0.view as? NSSegmentedControl }).first,
              let heading = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "Tape.SettingsTitle" })?.view as? NSTextField else {
            throw NSError(domain: "LineSmokeCheck", code: 20)
        }
        try require(!navigation.isEnabled(forSegment: 0) && !navigation.isEnabled(forSegment: 1), "New window must have no page history")
        func clickSidebarRow(_ row: Int) async throws {
            let rect = sidebar.rect(ofRow: row)
            let point = sidebar.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: true)
            sidebar.mouseDown(with: down)
            try await Task.sleep(for: .milliseconds(1_200))
        }
        try await clickSidebarRow(1)
        try require(sidebar.selectedRow == 1 && window.firstResponder === sidebar,
                    "Opening Statistics must keep keyboard focus in the sidebar after the page settles")
        try await clickSidebarRow(2)
        try require(sidebar.selectedRow == 2 && window.firstResponder === sidebar,
                    "Clicking a sidebar page must keep keyboard focus in the sidebar (selected=\(sidebar.selectedRow), sidebar=\(sidebar), responder=\(String(describing: window.firstResponder)))")
        try await clickSidebarRow(0)
        guard let sidebarToggle = window.toolbar?.items.first(where: { $0.itemIdentifier == .toggleSidebar }),
              let toggleAction = sidebarToggle.action else {
            throw NSError(domain: "LineSmokeCheck", code: 12, userInfo: [NSLocalizedDescriptionKey: "Native sidebar toggle is missing"])
        }
        let expandedFrame = window.frame
        let expandedSidebarWidth = split.splitViewItems[0].viewController.view.frame.width
        try require(NSApp.sendAction(toggleAction, to: sidebarToggle.target, from: sidebarToggle), "Sidebar toggle must handle clicks")
        try await settle()
        try require(split.splitViewItems[0].isCollapsed && window.frame == expandedFrame,
                    "Collapsing the sidebar must preserve the window frame")
        try require(window.toolbar?.visibleItems?.contains(where: { $0.itemIdentifier == .toggleSidebar }) == true,
                    "Sidebar toggle must remain visible when collapsed")
        if ProcessInfo.processInfo.environment["LINE_SMOKE_CAPTURE"] == "1" {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent("sidebar-collapsed.png").path]
            try capture.run()
            capture.waitUntilExit()
        }
        try require(NSApp.sendAction(toggleAction, to: sidebarToggle.target, from: sidebarToggle), "Collapsed sidebar toggle must handle clicks")
        try await settle()
        try require(!split.splitViewItems[0].isCollapsed && sidebar.selectedRow == 0
                    && abs(split.splitViewItems[0].viewController.view.frame.width - expandedSidebarWidth) < 1,
                    "Expanding the sidebar must restore its width and selected page")
        try await Task.sleep(for: .milliseconds(600))
        try require(window.firstResponder === sidebar,
                    "Unfolding must restore sidebar focus after the animation (responder=\(String(describing: window.firstResponder)))")
        guard let slider = descendants(content).compactMap({ $0 as? NSSlider }).first else {
            throw NSError(domain: "LineSmokeCheck", code: 13, userInfo: [NSLocalizedDescriptionKey: "Native default zoom slider is missing"])
        }
        window.setContentSize(NSSize(width: 900, height: 800))
        try await settle()
        if ProcessInfo.processInfo.environment["LINE_SMOKE_CAPTURE"] == "1" {
            try checkInitialSliderThumb(slider, in: window, output: output)
        }
        guard let timeFormatPicker = descendants(content).compactMap({ $0 as? NSPopUpButton }).first else {
            throw NSError(domain: "LineSmokeCheck", code: 16, userInfo: [NSLocalizedDescriptionKey: "Native time format menu is missing"])
        }
        let entriesBeforeFormatChange = model.store!.entries
        func selectMenu(_ picker: NSPopUpButton, from current: Int, to target: Int) async throws {
            let choose = Timer(timeInterval: 0.2, repeats: false) { _ in
                MainActor.assumeIsolated {
                    let arrow = target > current ? "\u{F701}" : "\u{F700}"
                    let keyCode: UInt16 = target > current ? 125 : 126
                    let keys = Array(repeating: (arrow, keyCode), count: abs(target - current)) + [("\r", UInt16(36))]
                    for (characters, code) in keys {
                        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                     context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                                     isARepeat: false, keyCode: code)!
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            RunLoop.main.add(choose, forMode: .common)
            RunLoop.main.add(choose, forMode: .eventTracking)
            defer { choose.invalidate() }
            let location = picker.convert(NSPoint(x: picker.bounds.midX, y: picker.bounds.midY), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: true)
            picker.mouseDown(with: down)
            try await settle()
        }
        for format in [TimeFormat.twelveHour, .system, .twentyFourHour] {
            try await selectMenu(timeFormatPicker, from: TimeFormat.allCases.firstIndex(of: model.timeFormat)!,
                                 to: TimeFormat.allCases.firstIndex(of: format)!)
            try require(model.timeFormat == format && model.settingsError == nil, "Time format must save immediately")
            try require(model.store!.entries == entriesBeforeFormatChange, "Time format must preserve tracking records")
        }
        let settingsMenus = descendants(content).compactMap { $0 as? NSPopUpButton }
        try require(settingsMenus.count == 4, "Time format, task order, threshold, and day start must use native menus")
        let dayStartPicker = settingsMenus[3]
        for hour in [6, 4] {
            try await selectMenu(dayStartPicker, from: model.statisticsDayStartHour, to: hour)
            try require(dayStartPicker.numberOfItems == 24, "Day start must offer every hour")
            try require(model.statisticsDayStartHour == hour && model.settingsError == nil, "Day start must save immediately")
            try require(model.store!.entries == entriesBeforeFormatChange, "Day start must preserve recorded entries")
        }
        let taskOrderPicker = settingsMenus[1]
        for order in [TaskOrder.alphabetical, .mostUsed, .recentlyUsed] {
            try await selectMenu(taskOrderPicker, from: TaskOrder.allCases.firstIndex(of: model.taskOrder)!,
                                 to: TaskOrder.allCases.firstIndex(of: order)!)
            try require(model.taskOrder == order && model.settingsError == nil, "Task order must save immediately")
            try require(model.store!.entries == entriesBeforeFormatChange, "Task order must preserve tracking records")
        }
        guard let countdownField = descendants(content).compactMap({ $0 as? NSTextField }).first(where: \.isEditable) else {
            throw NSError(domain: "LineSmokeCheck", code: 17, userInfo: [NSLocalizedDescriptionKey: "Native resume countdown field is missing"])
        }
        func enterCountdown(_ value: String, submit: Bool = true) async throws {
            guard let countdownField = descendants(content).compactMap({ $0 as? NSTextField }).first(where: \.isEditable) else {
                throw NSError(domain: "LineSmokeCheck", code: 17)
            }
            window.makeFirstResponder(countdownField)
            guard let editor = countdownField.currentEditor() as? NSTextView else {
                throw NSError(domain: "LineSmokeCheck", code: 17)
            }
            editor.selectAll(nil)
            editor.insertText(value, replacementRange: editor.selectedRange())
            try await Task.sleep(for: .milliseconds(100))
            if submit {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                             isARepeat: false, keyCode: 36)!
                window.sendEvent(event)
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        try await enterCountdown("1a5", submit: false)
        try require(countdownField.stringValue == "15", "Countdown field must keep only digits")
        try await enterCountdown("15")
        try require(model.resumeCountdownSeconds == 15, "Return must save the countdown")
        try await enterCountdown("")
        try require(countdownField.stringValue == "15" && model.resumeCountdownSeconds == 15, "Empty input must restore the saved countdown")
        try await enterCountdown("0")
        try require(countdownField.stringValue == "1" && model.resumeCountdownSeconds == 1, "Countdown must keep its one-second minimum")
        try await enterCountdown("999999999999999999999999999999")
        try require(countdownField.stringValue == "60" && model.resumeCountdownSeconds == 60, "Large input must remain within the countdown maximum")
        try await enterCountdown("15", submit: false)
        window.makeFirstResponder(nil)
        try await settle()
        try require(model.resumeCountdownSeconds == 15 && model.settingsError == nil && model.store!.entries == entriesBeforeFormatChange,
                    "Leaving the field must save without changing tracking records")
        let menus = descendants(content).compactMap { $0 as? NSPopUpButton }
        try require(menus.count == 4, "Time format, task order, threshold, and day start must use native menus")
        let thresholdPicker = menus[2]
        func selectThreshold(_ seconds: Int) async throws {
            var choices = [0, 30, 60, 120, 300, 600, 900, 1800, 3600]
            if !choices.contains(model.shortBreakSeconds) { choices.append(model.shortBreakSeconds) }
            let current = choices.firstIndex(of: model.shortBreakSeconds)!
            let target = choices.firstIndex(of: seconds)!
            let choose = Timer(timeInterval: 0.2, repeats: false) { _ in
                MainActor.assumeIsolated {
                    let arrow = target > current ? "\u{F701}" : "\u{F700}"
                    let keyCode: UInt16 = target > current ? 125 : 126
                    let keys = Array(repeating: (arrow, keyCode), count: abs(target - current)) + [("\r", UInt16(36))]
                    for (characters, code) in keys {
                        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                     context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                                     isARepeat: false, keyCode: code)!
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            RunLoop.main.add(choose, forMode: .common)
            RunLoop.main.add(choose, forMode: .eventTracking)
            defer { choose.invalidate() }
            let location = thresholdPicker.convert(NSPoint(x: thresholdPicker.bounds.midX, y: thresholdPicker.bounds.midY), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: true)
            thresholdPicker.mouseDown(with: down)
            try await settle()
        }
        for seconds in [0, 3600, 30] {
            try await selectThreshold(seconds)
            try require(model.shortBreakSeconds == seconds && model.settingsError == nil, "Threshold menu must save the selected duration: expected \(seconds), got \(model.shortBreakSeconds), items \(thresholdPicker.itemTitles)")
        }
        try require(!thresholdPicker.itemTitles.contains(where: { $0.hasPrefix("Custom") }),
                    "Threshold menu must not offer a custom dialog")
        model.setShortBreakSeconds(45)
        try await settle()
        // SwiftUI populates native menu items when the menu opens.
        try await selectThreshold(45)
        try require(thresholdPicker.titleOfSelectedItem == "45 seconds" && window.attachedSheet == nil,
                    "Previously saved non-preset thresholds must remain available without a dialog")
        try await selectThreshold(30)
        try require(model.shortBreakSeconds == 30, "A preset must replace a previously saved non-preset threshold")
        guard let resumeSwitch = descendants(content).compactMap({ $0 as? NSSwitch }).first else {
            throw NSError(domain: "LineSmokeCheck", code: 18, userInfo: [NSLocalizedDescriptionKey: "Native automatic resume switch is missing"])
        }
        resumeSwitch.performClick(nil)
        try await settle()
        try require(!model.automaticResumeEnabled && !countdownField.isEnabled && !thresholdPicker.isEnabled,
                    "Disabling resume must disable dependent controls")
        resumeSwitch.performClick(nil)
        try await settle()
        try require(model.automaticResumeEnabled && countdownField.isEnabled && thresholdPicker.isEnabled,
                    "Re-enabling resume must restore the saved controls")
        try require(model.resumeCountdownSeconds == 15 && model.shortBreakSeconds == 30 && model.store!.entries == entriesBeforeFormatChange,
                    "Resume preferences must preserve tracking and dependent values")
        try require(accessibilityElement(named: "Launch at login", in: content) != nil, "Launch at login must have an accessible control")
        try require(model.loginItem.status == SMAppService.mainApp.status, "Startup setting must reflect macOS registration")
        let originalSpan = model.timeline.span
        for hours in [1, 2, 4, 8, 16, 24, 12] {
            slider.doubleValue = Double(TrackingStore.defaultZoomPresets.firstIndex(of: hours)!)
            try require(slider.sendAction(slider.action, to: slider.target), "Native slider must deliver its change")
            try await Task.sleep(for: .milliseconds(100))
            try require(model.defaultZoomHours == hours && model.settingsError == nil, "Slider must save its selected value")
            try require(model.timeline.span == originalSpan, "Changing the default must wait for timeline opening or reset")
        }
        if firstLaunch {
            window.setContentSize(NSSize(width: 960, height: 640))
        }
        try await settle()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("settings.png"))
        }
        if ProcessInfo.processInfo.environment["LINE_SMOKE_CAPTURE"] == "1" {
            // Opt-in composited capture includes native glass that cacheDisplay cannot reproduce.
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent("settings-window.png").path]
            try capture.run()
            capture.waitUntilExit()
        }
        let sidebarWidth = sidebar.enclosingScrollView?.frame.width
        try await enterCountdown("17", submit: false)
        sidebar.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        try await settle()
        try require(heading.stringValue == "About" && split.splitViewItems.last?.viewController is NSHostingController<AboutView>,
                    "Selecting About must update the detail and toolbar title")
        try require(model.resumeCountdownSeconds == 17, "Leaving General must commit the edited countdown")
        try require(navigation.isEnabled(forSegment: 0) && !navigation.isEnabled(forSegment: 1), "About must enable Back")
        let aboutContent = split.splitViewItems.last!.viewController.view
        try require(accessibilityElement(named: "Source Code", in: aboutContent) != nil &&
                    accessibilityElement(named: "Show Data in Finder", in: aboutContent) != nil,
                    "About must expose source and local-data actions")
        if ProcessInfo.processInfo.environment["LINE_SMOKE_CAPTURE"] == "1" {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent("about-window.png").path]
            try capture.run()
            capture.waitUntilExit()
        }
        func navigate(_ segment: Int) async throws {
            let point = NSPoint(x: navigation.bounds.width * (CGFloat(segment) + 0.5) / 2, y: navigation.bounds.midY)
            let location = navigation.convert(point, to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: true)
            navigation.mouseDown(with: down)
            try await settle()
        }
        try await navigate(0)
        try require(sidebar.selectedRow == 0 && heading.stringValue == "General" && navigation.isEnabled(forSegment: 1),
                    "Back must restore General and enable Forward (row=\(sidebar.selectedRow), heading=\(heading.stringValue), forward=\(navigation.isEnabled(forSegment: 1)))")
        try await navigate(1)
        try require(sidebar.selectedRow == 2 && heading.stringValue == "About", "Forward must restore About")
        try await navigate(0)
        sidebar.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        try await settle()
        try require(!navigation.isEnabled(forSegment: 1), "Selecting a page after Back must clear forward history")
        sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try await settle()
        try require(sidebar.enclosingScrollView?.frame.width == sidebarWidth, "Page navigation must preserve sidebar width")
        try require(model.store!.entries == entriesBeforeFormatChange, "About navigation must preserve tracking")
        try await enterCountdown("15")
        if ProcessInfo.processInfo.environment["LINE_SMOKE_CAPTURE"] == "1" {
            window.setContentSize(NSSize(width: 900, height: 800))
            try await settle()
            let returnedSlider = descendants(content).compactMap { $0 as? NSSlider }.first!
            try checkInitialSliderThumb(returnedSlider, in: window, output: output)
        }
        func command(_ character: String, keyCode: UInt16) throws {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                        context: nil, characters: character, charactersIgnoringModifiers: character,
                                        isARepeat: false, keyCode: keyCode)!
            try require(NSApp.mainMenu?.performKeyEquivalent(with: event) == true, "Command-\(character) must be handled")
        }
        try command(",", keyCode: 43)
        try await settle()
        try require(delegate.mainWindowController?.window === window, "Repeated opening must reuse the same window")
        window.miniaturize(nil)
        try await settle()
        try require(window.isMiniaturized && NSApp.activationPolicy() == .regular, "Minimizing must keep Dock presence")
        let actions = delegate.makeActionsMenu()
        try require(actions.items.map(\.title) == ["General Settings", "Statistics", "About Tape", "", "Quit Tape"] && actions.items[3].isSeparatorItem,
                    "Status menu must order General, Statistics, About, then a separator and Quit")
        let general = actions.item(withTitle: "General Settings")!
        let about = actions.item(withTitle: "About Tape")!
        try require(NSApp.sendAction(about.action!, to: about.target, from: about), "Status menu must open About")
        try await settle()
        try require(!window.isMiniaturized && window.isKeyWindow && delegate.mainWindowController?.window === window,
                    "Opening a minimized window must restore and focus it (minimized=\(window.isMiniaturized), key=\(window.isKeyWindow), active=\(NSApp.isActive), front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"))")
        try require(sidebar.selectedRow == 2 && heading.stringValue == "About", "About menu item must select About even when General was minimized")
        try require(NSApp.sendAction(general.action!, to: general.target, from: general), "Status menu must open General Settings")
        try await settle()
        try require(sidebar.selectedRow == 0 && heading.stringValue == "General" && delegate.mainWindowController?.window === window,
                    "General Settings must select General in the same window")
        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
        try await settle()
        try require(window.isKeyWindow && delegate.mainWindowController?.window === window,
                    "Dock reopening must focus the existing main window (key=\(window.isKeyWindow), active=\(NSApp.isActive), front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"))")
        try command("w", keyCode: 13)
        try await settle()
        try require(!window.isVisible && NSApp.activationPolicy() == .accessory, "Closing must restore menu-bar-only operation")
        try require(model.store?.runningEntry?.id == runningID, "Closing must keep tracking")
        try require(NSApp.sendAction(about.action!, to: about.target, from: about), "About must reopen a closed window")
        try await settle()
        try require(window.isKeyWindow && sidebar.selectedRow == 2 && heading.stringValue == "About" && NSApp.activationPolicy() == .regular,
                    "About must directly select its page when reopening from menu-bar-only operation")
        try require(model.store?.runningEntry?.id == runningID && delegate.mainWindowController?.window === window,
                    "Section menu actions must preserve tracking and reuse the window")
        window.close()
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try require(model.timeline.span == 12 * 3_600 && model.timeline.isFollowingNow, "Reopening the timeline must use the configured default")
        try draw(0.1, 0.2, in: popover)
        try require(model.entrySelection != nil, "Historical draft must exist before opening Settings")
        try command(",", keyCode: 43)
        try await settle()
        try require(model.entrySelection == nil && !popover.isShown && window.isKeyWindow, "Command-comma must discard the interval draft and open Settings")
        try require(model.store?.runningEntry?.id == runningID, "Window and settings operations must preserve tracking")
        window.close()
        try await settle()
        guard let savedFrame = UserDefaults.standard.string(forKey: frameKey) else {
            throw NSError(domain: "LineSmokeCheck", code: 14, userInfo: [NSLocalizedDescriptionKey: "Native window geometry was not saved"])
        }
        try Data(savedFrame.utf8).write(to: output.appendingPathComponent("window-frame.txt"))
    }

    private static func checkStatistics(model: AppModel, output: URL) async throws {
        let store = model.store!
        let calendar = Calendar.autoupdatingCurrent
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))!
        for (name, offset, duration) in [("Building Tape :dayline :coding", 8.0, 2.0),
                                         ("Meeting :dayline :meeting", 11.0, 1.0),
                                         ("Reading", 14.0, 1.0)] {
            let start = yesterday.addingTimeInterval(offset * 3_600)
            try store.createEntry(named: name, selection: store.prepareEntry(from: start, to: start + duration * 3_600))
        }
        for index in 0..<24 {
            let start = yesterday.addingTimeInterval(17 * 3_600 + Double(index) * 60)
            try store.createEntry(named: "Sample \(index) :sample\(index)",
                                  selection: store.prepareEntry(from: start, to: start + 60))
        }
        try require(model.start("Live task :coding"), "Start live task before statistics")
        let entries = store.entries
        let tasks = store.tasks
        let delegate = NSApp.delegate as! AppDelegate
        let item = delegate.makeActionsMenu().item(withTitle: "Statistics")!
        try require(item.image != nil, "Statistics menu item must have its sidebar icon")
        try require(NSApp.sendAction(item.action!, to: item.target, from: item), "Open Statistics from the status menu")
        try await settle()
        let controller = delegate.mainWindowController!
        let window = controller.window!
        let state = controller.statisticsSelection
        let content = window.contentView!
        try require(state.period == .week && state.grouping == .tags, "Statistics must begin with the current week and tags")
        state.anchor = yesterday
        try await settle()
        func breakdownTable() throws -> NSTableView {
            let detail = (window.contentViewController as! NSSplitViewController).splitViewItems.last!.viewController.view
            guard let table = descendants(detail).compactMap({ $0 as? NSTableView }).first else {
                throw NSError(domain: "LineSmokeCheck", code: 40, userInfo: [NSLocalizedDescriptionKey: "Native statistics table missing"])
            }
            return table
        }
        func clickRow(_ row: Int, column: Int = 0) async throws {
            let table = try breakdownTable()
            try require(row >= 0 && row < table.numberOfRows, "The row to click must exist")
            table.scrollRowToVisible(row)
            let cell = table.frameOfCell(atColumn: column, row: row)
            let point = table.convert(NSPoint(x: cell.midX, y: cell.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
            }
            try await settle()
        }
        let initialTable = try breakdownTable()
        try require(initialTable.usesAlternatingRowBackgroundColors, "Native table must use alternating row backgrounds")
        try require(initialTable.enclosingScrollView?.borderType == .noBorder, "Statistics table must have no enclosing border")
        let nativeRowHeight = initialTable.rowHeight + initialTable.intercellSpacing.height
        try require((0..<initialTable.numberOfRows).allSatisfy {
            abs(initialTable.rect(ofRow: $0).height - nativeRowHeight) < 0.5
        }, "Populated table rows must match the native empty stripe height")
        try await clickRow(0)
        try require(state.filter == .tag("dayline"), "Tag row must select its filter")
        try require(accessibilityElement(named: "Clear statistics filter", in: content) == nil,
                    "Selected filters must not add a pill above the chart")
        try await clickRow(0, column: 1)
        try require(state.filter == nil && (try breakdownTable()).selectedRow == -1,
                    "Clicking the selected row's Time cell must deselect it")
        try await clickRow(1)
        try require(state.filter == .tag("coding"), "Another row must select its own filter")
        try await clickRow(0)
        try require(state.filter == .tag("dayline"), "Clicking a different row must replace the filter")
        state.search = "no matching rows"
        try await settle()
        try require(state.filter == .tag("dayline") && (try breakdownTable()).numberOfRows == 0,
                    "Search must not clear an active chart filter when its row is hidden")
        state.search = ""
        try await settle()
        try pressAccessibleControl(named: "Show tasks", in: content)
        try await settle()
        try require(state.grouping == .tasks, "The glass control must switch to tasks")
        try require(try breakdownTable().numberOfRows == 2 && state.filter == .tag("dayline"),
                    "Changing grouping must show only the two tasks in the selected tag")
        try capture("statistics-table-filtered")
        let dayLabel = "Explore \(yesterday.formatted(date: .complete, time: .omitted)), 3h"
        try pressAccessibleControl(named: dayLabel, in: content)
        try await settle()
        try require(state.period == .day && calendar.isDate(state.anchor, inSameDayAs: yesterday), "Day bar must open the session timeline")
        try pressAccessibleControl(named: "Show tags", in: content)
        try await settle()
        try require(state.grouping == .tags, "The glass control must switch back to tags")
        try await clickRow(0)
        try require(state.filter == nil, "Clicking the selected tag must restore all tracked time")
        state.grouping = .tasks
        try await settle()
        let session = store.entries.first!
        let task = store.task(id: session.taskID)!
        let sessionLabel = "\(task.inputText), \(model.timeFormat.string(from: session.start))–\(model.timeFormat.string(from: session.end!)), 2h"
        try pressAccessibleControl(named: sessionLabel, in: content)
        try await settle()
        try require(state.filter == .task(task.id), "Selecting a session must focus its task")
        try await clickRow(breakdownTable().selectedRow)
        try require(state.filter == nil, "Clicking the selected task must clear a chart-originated selection")
        let searchField = descendants(content).compactMap { $0 as? NSSearchField }.first!
        window.makeFirstResponder(searchField)
        let searchEditor = searchField.currentEditor() as! NSTextView
        searchEditor.selectAll(nil)
        searchEditor.insertText("READ", replacementRange: searchEditor.selectedRange())
        try await settle()
        try require(state.search == "READ", "Native search field must filter while typing")
        try require(try breakdownTable().numberOfRows == 1, "Search must narrow the native table to Reading")
        state.search = ""
        state.period = .month
        try await settle()
        guard let periodNavigation = descendants(content).compactMap({ $0 as? NSSegmentedControl }).first(where: {
            $0.segmentCount == 3 && $0.label(forSegment: 1) == "This month"
        }) else {
            throw NSError(domain: "LineSmokeCheck", code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "Statistics navigation is missing"])
        }
        try require(!periodNavigation.isEnabled(forSegment: 1), "Current period button must be disabled in the current period")
        try require(!periodNavigation.isEnabled(forSegment: 2), "Next must be disabled in the current period")
        func clickPeriodNavigation(at x: CGFloat) async throws {
            let point = periodNavigation.convert(NSPoint(x: x, y: periodNavigation.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
            }
            try await settle()
        }
        try await clickPeriodNavigation(at: 14)
        try require(state.anchor < yesterday, "Previous must move to an earlier month")
        try require(periodNavigation.isEnabled(forSegment: 1), "Current period button must be enabled in a past period")
        try require(periodNavigation.isEnabled(forSegment: 2), "Next must be enabled in a past period")
        try await clickPeriodNavigation(at: periodNavigation.bounds.midX)
        try require(calendar.isDate(state.anchor, equalTo: .now, toGranularity: .month), "This month must restore the current month")
        try require(!periodNavigation.isEnabled(forSegment: 1), "Returning to the current period must disable its button")
        func capture(_ name: String) throws {
            guard ProcessInfo.processInfo.environment["LINE_SMOKE_CAPTURE"] == "1" else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
            try process.run()
            process.waitUntilExit()
        }
        window.setContentSize(NSSize(width: 900, height: 650))
        state.period = .week
        state.anchor = yesterday
        state.grouping = .tags
        try await settle()
        try capture("statistics-week")
        state.grouping = .tasks
        try await settle()
        try capture("statistics-week-tasks")
        state.grouping = .tags
        state.filter = .tag("dayline")
        try await settle()
        try capture("statistics-filtered")
        state.filter = .tag("coding")
        try await settle()
        try capture("statistics-middle-segment")
        state.filter = nil
        state.period = .month
        try await settle()
        try capture("statistics-month")
        state.filter = .tag("coding")
        try await settle()
        try capture("statistics-month-filtered")
        state.filter = nil
        state.showDay(yesterday)
        try await settle()
        try capture("statistics-day")
        model.setStatisticsDayStartHour(4)
        state.anchor = yesterday.addingTimeInterval(12 * 3_600)
        try await settle()
        let shiftedRange = StatisticsPeriod.day.interval(containing: state.anchor, dayStartHour: 4)
        let shiftedTicks = StatisticsDayBoundary(hour: 4).ticks(in: shiftedRange)
        try capture("statistics-shifted-day")
        try require(shiftedTicks.allSatisfy { accessibilityElement(named: model.timeFormat.string(from: $0), in: content) != nil },
                    "Changing day start must update the visible timeline marks across midnight")
        try require(calendar.component(.day, from: shiftedTicks.last!) != calendar.component(.day, from: shiftedRange.start),
                    "The shifted chart must include the next morning")
        let navigationState = StatisticsSelection()
        navigationState.period = .day
        let beforeBoundary = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: yesterday)!
        navigationState.anchor = beforeBoundary
        navigationState.move(1, now: beforeBoundary, dayStartHour: 4)
        try require(navigationState.anchor == beforeBoundary, "Next must not leave the current statistics day before its boundary")
        navigationState.move(-1, now: beforeBoundary, dayStartHour: 4)
        navigationState.move(1, now: beforeBoundary, dayStartHour: 4)
        try require(navigationState.anchor == StatisticsPeriod.day.interval(containing: beforeBoundary, dayStartHour: 4).start,
                    "Previous and next must navigate between shifted boundaries")
        model.setStatisticsDayStartHour(0)
        state.anchor = yesterday
        try await settle()
        window.setContentSize(NSSize(width: 640, height: 600))
        try await settle()
        try require(accessibilityElement(named: "Search statistics", in: content) != nil, "Search must remain available at minimum width")
        try capture("statistics-small")
        let table = try breakdownTable()
        let scroll = table.enclosingScrollView!
        let tableFrame = scroll.convert(scroll.bounds, to: nil)
        let periodPicker = descendants(content).compactMap { $0 as? NSPopUpButton }.first {
            $0.itemTitles == ["Day", "Week", "Month"]
        }!
        let periodPickerFrame = periodPicker.convert(periodPicker.bounds, to: nil)
        table.scrollRowToVisible(table.numberOfRows - 1)
        try await settle()
        try require(scroll.contentView.bounds.origin.y > 0, "Long breakdown must scroll independently")
        try require(scroll.convert(scroll.bounds, to: nil) == tableFrame && periodPicker.convert(periodPicker.bounds, to: nil) == periodPickerFrame,
                    "Scrolling rows must not move the table container or chart controls")
        try capture("statistics-scrolled")
        window.setContentSize(NSSize(width: 640, height: 420))
        state.filter = .tag("dayline")
        try await settle()
        let smallest = try breakdownTable().enclosingScrollView!
        try require(smallest.frame.height >= 55, "Minimum window height must retain a usable table")
        let visibleTable = smallest.convert(smallest.bounds, to: content)
        try require(content.bounds.insetBy(dx: -1, dy: -1).contains(visibleTable), "The whole table viewport must fit in the shortest window")
        try capture("statistics-short")
        state.period = .week
        try await settle()
        let shortWeek = try breakdownTable().enclosingScrollView!
        try require(content.bounds.insetBy(dx: -1, dy: -1).contains(shortWeek.convert(shortWeek.bounds, to: content)),
                    "The weekly chart must also leave the table inside the shortest window")
        try capture("statistics-short-week")
        state.period = .day
        state.filter = nil
        window.setContentSize(NSSize(width: 640, height: 600))
        try await settle()
        window.appearance = NSAppearance(named: .aqua)
        try await settle()
        try capture("statistics-light")
        controller.present(page: .general)
        try await settle()
        controller.present(page: .statistics)
        try await settle()
        try require(state.period == .day && state.grouping == .tags, "Page navigation must preserve the explored period")
        try require(store.entries == entries && store.tasks == tasks,
                    "Statistics must preserve saved data and running entry identity")
        window.close()
    }

    private static func checkInitialSliderThumb(_ slider: NSSlider, in window: NSWindow, output: URL) throws {
        let url = output.appendingPathComponent("settings-first-open.png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0,
              let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)),
              let cell = slider.cell as? NSSliderCell else {
            throw NSError(domain: "LineSmokeCheck", code: 15, userInfo: [NSLocalizedDescriptionKey: "Initial slider capture failed"])
        }
        let knob = cell.knobRect(flipped: slider.isFlipped)
        let point = window.convertPoint(toScreen: slider.convert(NSPoint(x: knob.midX, y: knob.midY), to: nil))
        let x = Int((point.x - window.frame.minX) * CGFloat(bitmap.pixelsWide) / window.frame.width)
        let y = Int((window.frame.maxY - point.y) * CGFloat(bitmap.pixelsHigh) / window.frame.height)
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            throw NSError(domain: "LineSmokeCheck", code: 15)
        }
        let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
        print("Initial slider thumb brightness: \(brightness), enabled=\(slider.isEnabled), key=\(window.isKeyWindow), sample=(\(x), \(y))")
        if slider.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            try require(brightness > 0.5, "Slider thumb must be light on first opening, before interaction (brightness=\(brightness))")
        }
        let switches = descendants(window.contentView!).compactMap { $0 as? NSSwitch }
        try require(switches.count == 2, "Both settings switches must exist on first opening")
        for (index, toggle) in switches.enumerated() {
            let center = window.convertPoint(toScreen: toggle.convert(NSPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: nil))
            let scale = CGFloat(bitmap.pixelsWide) / window.frame.width
            let midX = Int((center.x - window.frame.minX) * scale)
            let midY = Int((window.frame.maxY - center.y) * scale)
            let halfWidth = Int(toggle.bounds.width * scale / 2) - 3
            var brightest = 0.0
            for px in (midX - halfWidth)...(midX + halfWidth) {
                guard let sample = bitmap.colorAt(x: px, y: midY)?.usingColorSpace(.deviceRGB) else { continue }
                brightest = max(brightest, (sample.redComponent + sample.greenComponent + sample.blueComponent) / 3)
            }
            print("Initial switch \(index) brightness: \(brightest), state=\(toggle.state.rawValue), frame=\(toggle.frame)")
            try require(brightest > 0.7, "Switch \(index) must show a light thumb before interaction (brightness=\(brightest))")
        }
    }

    private static func timelineInput(in popover: NSPopover) throws -> TimelineInputView {
        guard let input = try descendants(contentView(popover)).compactMap({ $0 as? TimelineInputView }).first else {
            throw NSError(domain: "LineSmokeCheck", code: 9)
        }
        return input
    }

    private static func draw(_ from: Double, _ to: Double, in popover: NSPopover, command: Bool = false,
                             finish: Bool = true, release: Double? = nil) throws {
        let input = try timelineInput(in: popover)
        let window = input.window!
        func event(_ type: NSEvent.EventType, _ fraction: Double) -> NSEvent {
            TimelineTestEvent(type: type, window: window,
                              location: input.convert(NSPoint(x: input.bounds.width * fraction, y: 60), to: nil),
                              flags: command && type == .leftMouseDown ? .command : [])
        }
        _ = input.handle(event(.leftMouseDown, from))
        _ = input.handle(event(.leftMouseDragged, to))
        if finish { _ = input.handle(event(.leftMouseUp, release ?? to)) }
    }

    private static func checkDismissal(button: NSStatusBarButton, popover: NSPopover, model: AppModel) async throws {
        let store = model.store!
        let now = Date.now
        try store.createEntry(named: "Dismissal", selection: store.prepareEntry(from: now - 600, to: now - 300))
        for menuAction in ["none", "cancel", "select"] {
            try clickStatusItem(button)
            try await settle()
            model.editEntry(id: store.entries[0].id)
            try await settle()
            if menuAction != "none" {
                guard let picker = descendants(try contentView(popover)).compactMap({ $0 as? NSPopUpButton }).first else {
                    throw NSError(domain: "LineSmokeCheck", code: 19, userInfo: [NSLocalizedDescriptionKey: "Color menu is missing"])
                }
                let dismiss = Timer(timeInterval: 0.2, repeats: false) { _ in
                    MainActor.assumeIsolated { picker.menu?.cancelTrackingWithoutAnimation() }
                }
                RunLoop.main.add(dismiss, forMode: .eventTracking)
                picker.performClick(nil)
                dismiss.invalidate()
                if menuAction == "select", let menu = picker.menu {
                    menu.performActionForItem(at: 1)
                }
                try await settle()
                try require(popover.isShown, "Closing only the color menu must keep Tape open")
            }
            // Exercise the production callback registered for clicks in other apps.
            (NSApp.delegate as? AppDelegate)?.dismissForOutsideClick()
            try await settle()
            try require(!popover.isShown, "Leaving Tape must dismiss its popover; color menu action: \(menuAction)")
        }
    }

    private static func checkEditing(button: NSStatusBarButton, popover: NSPopover, model: AppModel) async throws {
        let store = model.store!
        let base = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970 / 60) * 60)
        try store.createEntry(named: "Edit", selection: store.prepareEntry(from: base - 3_600, to: base - 3_000))
        try store.createEntry(named: "Keep", selection: store.prepareEntry(from: base - 1_800, to: base - 1_200))
        try store.createEntry(named: "Keep", selection: store.prepareEntry(from: base - 600, to: .now, reachesNow: true))
        let original = store.entries[0]
        let completed = store.entries[1]
        let running = store.runningEntry!
        try await settle()
        try clickStatusItem(button)
        try await settle()

        func clickEntry(_ date: Date) throws {
            let input = try timelineInput(in: popover)
            let fraction = model.timeline.fraction(for: date, now: .now)
            let point = input.convert(NSPoint(x: input.bounds.width * fraction, y: 60), to: nil)
            _ = input.handle(TimelineTestEvent(type: .leftMouseDown, window: input.window!, location: point))
            _ = input.handle(TimelineTestEvent(type: .leftMouseUp, window: input.window!, location: point))
        }
        func confirm(_ title: String) throws {
            let host = try contentView(popover).window!
            let panel = host.attachedSheet ?? NSApp.modalWindow ??
                NSApp.windows.first { $0.isVisible && $0 !== host && $0.contentView.map { accessibilityElement(named: title, in: $0) != nil } == true }
            guard let panel, let content = panel.contentView else {
                throw NSError(domain: "LineSmokeCheck", code: 12, userInfo: [NSLocalizedDescriptionKey: "Native deletion confirmation is missing"])
            }
            if let button = descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == title && $0.isEnabled }) {
                button.performClick(nil)
            } else {
                try pressAccessibleControl(named: title, in: content)
            }
        }

        model.timeline.pauseFollowing(at: .now)
        let hoverInput = try timelineInput(in: popover)
        func hover(_ date: Date, y: CGFloat = 60, flags: NSEvent.ModifierFlags = []) {
            let fraction = model.timeline.fraction(for: date, now: .now)
            let point = hoverInput.convert(NSPoint(x: hoverInput.bounds.width * fraction, y: y), to: nil)
            hoverInput.cursorUpdate(with: TimelineTestEvent(type: .cursorUpdate, window: hoverInput.window!, location: point, flags: flags))
        }
        let beforeHover = store.entries
        hover(original.start)
        try require(NSCursor.current == EntryResizeCursor.start, "Completed entry starts must show the start-edge bracket")
        hover(original.start + 300)
        try require(NSCursor.current == NSCursor.arrow, "Entry interiors must clear the resize cursor")
        hover(original.end!)
        try require(NSCursor.current == EntryResizeCursor.end, "Completed entry ends must show the end-edge bracket")
        hover(original.end!, flags: .command)
        try require(NSCursor.current == EntryResizeCursor.end, "Command must keep the resize cursor at entry edges")
        hover(original.start)
        hover(running.start)
        try require(NSCursor.current == EntryResizeCursor.start, "Running starts must show the start-edge bracket")
        hover(.now)
        try require(NSCursor.current == EntryResizeCursor.end, "Running ends at Now must show the end-edge bracket")
        hover(original.start)
        hover(original.start, y: 110)
        try require(NSCursor.current == NSCursor.arrow, "Leaving the strip must clear the resize cursor")
        try require(store.entries == beforeHover && model.resizingEntryID == nil && model.editingEntryID == nil,
                    "Hovering must not change records or begin editing")
        try store.updateEntry(id: original.id, taskID: original.taskID, start: original.start, end: original.start + 1)
        try await settle()
        let width = try timelineInput(in: popover).bounds.width
        try clickEntry(original.start + model.timeline.span / width)
        try require(model.editingEntryID == original.id, "The entire two-point block of a short entry must be clickable")
        let beforeDeselect = store.entries
        try clickEntry(base - 2_400)
        try require(model.editingEntryID == nil && store.entries == beforeDeselect && store.runningEntry?.id == running.id,
                    "Clicking empty timeline space must deselect without changing entries or stopping tracking")
        try store.updateEntry(id: original.id, taskID: original.taskID, start: original.start, end: completed.start)
        // Pick one pixel inside the later entry to avoid a float round-trip landing before the boundary.
        try clickEntry(completed.start + model.timeline.span / width)
        try require(model.editingEntryID == completed.id, "The right side of a shared boundary must select the later entry")
        model.cancelEntry()
        let sharedBoundary = model.timeline.fraction(for: completed.start, now: .now)
        hover(completed.start - model.timeline.span / width)
        try require(NSCursor.current == EntryResizeCursor.end, "Left of a shared boundary must target the earlier entry's end")
        hover(completed.start + model.timeline.span / width)
        try require(NSCursor.current == EntryResizeCursor.start, "Right of a shared boundary must target the later entry's start")
        // At the default eight-hour zoom, two minutes is below the three-pixel drag threshold.
        let resizeTo = model.timeline.fraction(for: completed.start + 300, now: .now)
        try draw(sharedBoundary + 1 / width, resizeTo, in: popover, finish: false)
        hover(original.start)
        try require(NSCursor.current == EntryResizeCursor.start && model.resizingEntryID == completed.id,
                    "The chosen bracket must stay attached to its entry during dragging (startCursor=\(NSCursor.current == EntryResizeCursor.start), expectedEntry=\(model.resizingEntryID == completed.id), drawing=\(model.isDrawing))")
        let releasePoint = hoverInput.convert(NSPoint(x: hoverInput.bounds.width * resizeTo, y: 60), to: nil)
        _ = hoverInput.handle(TimelineTestEvent(type: .leftMouseUp, window: hoverInput.window!, location: releasePoint))
        try require(store.entries[1].start == completed.start + 300 && store.entries[0].end == completed.start,
                    "Dragging inside the later entry must resize its start at a shared boundary")
        try store.updateEntry(id: completed.id, taskID: completed.taskID, start: completed.start, end: completed.end)
        try store.updateEntry(id: original.id, taskID: original.taskID, start: original.start, end: original.end)

        try clickEntry(base - 3_300)
        try await settle()
        try require(model.editingEntryID == original.id, "Clicking an entry must reveal its inline settings")
        try requireAnchored(popover, to: button)
        try require(accessibilityElement(named: "Task color", in: contentView(popover)) != nil,
                    "The color picker must have an accessible label")
        // SwiftUI can expose the label on its accessibility node instead of the native view.
        guard let colorPicker = descendants(try contentView(popover)).compactMap({ $0 as? NSPopUpButton }).first,
              colorPicker.menu != nil else {
            throw NSError(domain: "LineSmokeCheck", code: 14, userInfo: [NSLocalizedDescriptionKey: "Native color menu is missing"])
        }
        guard let swatch = colorPicker.image, !swatch.isTemplate,
              let swatchData = swatch.tiffRepresentation, let swatchBitmap = NSBitmapImageRep(data: swatchData),
              let swatchPixel = swatchBitmap.colorAt(x: swatchBitmap.pixelsWide / 2, y: swatchBitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else {
            throw NSError(domain: "LineSmokeCheck", code: 17, userInfo: [NSLocalizedDescriptionKey: "The closed color menu must display its full-color swatch image"])
        }
        let swatchChannels = [swatchPixel.redComponent, swatchPixel.greenComponent, swatchPixel.blueComponent]
        try require(swatchPixel.alphaComponent > 0.9 && swatchChannels.max()! - swatchChannels.min()! > 0.1,
                    "The closed color menu's circle must be visible and retain its task color")
        try require(!colorPicker.isBordered, "The color circle must not have a rectangular button bezel")
        try require(swatch.size == NSSize(width: 17, height: 17), "The 15-point circle must have a one-point image inset")
        func renderedSwatch(highlighted: Bool) throws -> NSColor {
            let cell = colorPicker.cell!
            cell.isHighlighted = highlighted
            defer { cell.isHighlighted = false }
            let image = NSImage(size: colorPicker.bounds.size, flipped: false) { rect in
                cell.draw(withFrame: rect, in: colorPicker)
                return true
            }
            guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
                  let pixel = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else {
                throw NSError(domain: "LineSmokeCheck", code: 18, userInfo: [NSLocalizedDescriptionKey: "Could not render color menu highlight"])
            }
            return pixel
        }
        let normalSwatch = try renderedSwatch(highlighted: false)
        let pressedSwatch = try renderedSwatch(highlighted: true)
        try require(abs(normalSwatch.redComponent - pressedSwatch.redComponent) < 0.02 &&
                    abs(normalSwatch.greenComponent - pressedSwatch.greenComponent) < 0.02 &&
                    abs(normalSwatch.blueComponent - pressedSwatch.blueComponent) < 0.02,
                    "Opening the color menu must not change the circle color: \(normalSwatch) vs \(pressedSwatch)")
        let dismissMenu = Timer(timeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated { colorPicker.menu?.cancelTrackingWithoutAnimation() }
        }
        RunLoop.main.add(dismissMenu, forMode: .eventTracking)
        colorPicker.performClick(nil)
        dismissMenu.invalidate()
        let colorItems = Array(colorPicker.menu!.items.dropFirst())
        try require(colorItems.count == TaskColor.allCases.count, "The color menu must show every task color directly")
        for item in colorItems {
            try require(item.title.isEmpty, "Color choices must show swatches without visible color names")
            guard let image = item.image, !image.isTemplate, let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data),
                  let pixel = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else {
                throw NSError(domain: "LineSmokeCheck", code: 15, userInfo: [NSLocalizedDescriptionKey: "Color swatch must retain full color: \(item.title)"])
            }
            let channels = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
            try require(channels.max()! - channels.min()! > 0.1, "Color swatch must not be monochrome: \(item.title)")
        }
        let nextColorIndex = TaskColor.allCases.firstIndex { $0 != store.task(id: original.taskID)?.color }!
        let nativeIndex = colorPicker.menu!.index(of: colorItems[nextColorIndex])
        colorPicker.menu?.performActionForItem(at: nativeIndex)
        try await settle()
        try require(store.task(id: original.taskID)?.color == TaskColor.allCases[nextColorIndex],
                    "Choosing a swatch must save the task color immediately")
        let colorFrame = colorPicker.convert(colorPicker.bounds, to: nil)
        guard let searchField = descendants(try contentView(popover)).compactMap({ $0 as? NSTextField })
            .first(where: { $0.accessibilityLabel() == "Entry task name or search" }) else {
            throw NSError(domain: "LineSmokeCheck", code: 16, userInfo: [NSLocalizedDescriptionKey: "Entry task search is missing"])
        }
        let searchFrame = searchField.convert(searchField.bounds, to: nil)
        try require(colorFrame.maxX <= searchFrame.minX, "The color picker must precede the task search")
        try require(!descendants(try contentView(popover)).contains(where: { $0 is NSDatePicker }),
                    "Entry times are edited by dragging edges, without date controls")
        try require(accessibilityElement(named: "Save entry", in: contentView(popover)) == nil &&
                    accessibilityElement(named: "Cancel", in: contentView(popover)) == nil, "The editor must not have Save or Cancel actions")
        try requireAnchored(popover, to: button)

        let window = try contentView(popover).window!
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                      context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                      isARepeat: false, keyCode: 53)!
        // sendEvent bypasses local monitors; exercise the production monitor handler explicitly.
        let input = try timelineInput(in: popover)
        if !input.handle(escape) { window.sendEvent(escape) }
        try await settle()
        try require(model.editingEntryID == nil && model.entryError == nil && store.entries[0].start == original.start && store.task(id: original.taskID)?.color == TaskColor.allCases[nextColorIndex], "Escape must close the editor and retain the saved color without changing entry times")
        try clickEntry(base - 3_300)
        try await settle()
        try pressAccessibleControl(named: "Delete entry", in: contentView(popover))
        try await settle()
        try require(store.entries.count == 3 && store.runningEntry?.id == running.id, "Asking to delete must preserve records and tracking")
        try confirm("Cancel")
        try await settle()
        try require(store.entries.count == 3 && model.editingEntryID == original.id, "Cancel must retain the entry and editor")
        try pressAccessibleControl(named: "Delete entry", in: contentView(popover))
        try await settle()
        try confirm("Delete")
        try await settle()
        try require(store.entries.count == 2 && store.task(id: original.taskID) == nil, "Confirmed deletion must prune the unused task")

        let from = model.timeline.fraction(for: completed.start, now: .now)
        let to = model.timeline.fraction(for: base - 2_100, now: .now)
        try draw(from, to, in: popover)
        try await settle()
        try require(store.entries[0].start == base - 2_100, "Dragging a completed edge must resize it")
        try require(store.runningEntry?.id == running.id, "Resizing history must leave tracking alone")

        try clickEntry(base - 300)
        try await settle()
        try require(model.editingEntryID == running.id, "Running entries must be editable")
        guard let taskSearch = descendants(try contentView(popover)).compactMap({ $0 as? NSTextField })
            .first(where: { $0.accessibilityLabel() == "Entry task name or search" }) else {
            throw NSError(domain: "LineSmokeCheck", code: 17, userInfo: [NSLocalizedDescriptionKey: "Running entry task search is missing"])
        }
        _ = taskSearch.window?.makeFirstResponder(taskSearch)
        try await settle()
        try enterTaskName("New assignment", in: popover, submit: false)
        try await settle()
        try require(store.runningEntry?.taskID == running.taskID, "Typing must not reassign the entry")
        try enterTaskName("New assignment", in: popover)
        try await settle()
        try require(store.runningTask?.name == "New assignment" && store.runningEntry?.id == running.id,
                    "Return must create and assign a task without stopping the entry")
        _ = taskSearch.window?.makeFirstResponder(taskSearch)
        try await settle()
        try enterTaskName("Keep", in: popover, submit: false)
        try await settle()
        try pressAccessibleControl(named: "Use Keep", in: contentView(popover))
        try await settle()
        try require(store.runningTask?.name == "New assignment", "Choosing an editor suggestion must wait for Return")
        try enterTaskName("Keep", in: popover)
        try await settle()
        try require(store.runningEntry?.taskID == completed.taskID && store.tasks.count == 1,
                    "Confirming a suggestion must reuse its task and prune the abandoned task")
        try requireAnchored(popover, to: button)
        try clickEntry(base - 300)
        try await settle()
        try pressAccessibleControl(named: "Delete entry", in: contentView(popover))
        try await settle()
        try confirm("Delete")
        try await settle()
        try require(store.runningEntry == nil && store.entries.count == 1, "Deleting the running entry must stop tracking")
        let remaining = store.entries[0]
        let resizeInstant = Date.now
        let endFraction = model.timeline.fraction(for: remaining.end!, now: resizeInstant)
        let nowFraction = model.timeline.fraction(for: resizeInstant, now: resizeInstant)
        try draw(endFraction, nowFraction + 1 / width, in: popover, finish: false)
        try require(model.drawnRange != nil, "Resizing through Now must retain the preview")
        let nowPoint = hoverInput.convert(NSPoint(x: hoverInput.bounds.width * nowFraction, y: 60), to: nil)
        _ = hoverInput.handle(TimelineTestEvent(type: .leftMouseUp, window: hoverInput.window!, location: nowPoint))
        try await settle()
        try require(store.runningEntry?.id == remaining.id && store.runningEntry?.start == remaining.start && store.entries.count == 1,
                    "Releasing a resized end at Now must continue the same entry")
        let movedStart = remaining.start + 300
        try draw(model.timeline.fraction(for: remaining.start, now: .now),
                 model.timeline.fraction(for: movedStart, now: .now), in: popover)
        try require(store.runningEntry?.id == remaining.id && store.runningEntry?.start == movedStart,
                    "Dragging the running start must preserve tracking")
        let runningFrame = try contentView(popover).window!.frame
        let liveEnd = model.timeline.fraction(for: .now, now: .now)
        try draw(liveEnd, liveEnd + 6 / width, in: popover)
        try require(store.runningEntry?.id == remaining.id, "Dragging a running end beyond Now must keep tracking")
        try draw(model.timeline.fraction(for: .now, now: .now),
                 model.timeline.fraction(for: base - 600, now: .now), in: popover)
        try await settle()
        try require(store.runningEntry == nil && store.entries[0].end == base - 600 && store.entries[0].id == remaining.id,
                    "Dragging the running end into the past must stop at that time")
        let stoppedFrame = try contentView(popover).window!.frame
        try require(abs(runningFrame.minY - stoppedFrame.minY) < 0.25 && abs(runningFrame.height - stoppedFrame.height) < 0.25,
                    "Stopping by resize must not shift the popover: running \(runningFrame), stopped \(stoppedFrame)")
        try draw(model.timeline.fraction(for: base - 600, now: .now),
                 model.timeline.fraction(for: .now, now: .now), in: popover)
        try await settle()
        let resumedFrame = try contentView(popover).window!.frame
        try require(abs(stoppedFrame.minY - resumedFrame.minY) < 0.25 && abs(stoppedFrame.height - resumedFrame.height) < 0.25,
                    "Resuming by resize must not shift the popover: stopped \(stoppedFrame), resumed \(resumedFrame)")
        try pressAccessibleControl(named: "Stop", in: contentView(popover))
        try await settle()
        try require(store.runningEntry == nil && store.entries[0].id == remaining.id, "The continued entry must stop normally")
        try requireAnchored(popover, to: button)
        try await requireStablePosition(popover)
    }

    private static func checkContinuation(button: NSStatusBarButton, popover: NSPopover, model: AppModel) async throws {
        let delegate = NSApp.delegate as! AppDelegate
        let store = model.store!
        func offer() async throws -> PendingContinuation {
            try require(model.start("Continuation check"), "Start interrupted work")
            try await settle()
            delegate.handleSystemEvent(.locked)
            try await settle()
            delegate.handleSystemEvent(.unlocked)
            try await settle()
            guard let pending = model.interruptions?.pendingContinuation else {
                throw NSError(domain: "LineSmokeCheck", code: 30, userInfo: [NSLocalizedDescriptionKey: "An unlocked return must offer continuation"])
            }
            // Keep hardware pointer position from affecting the synthetic countdown tests.
            if let notice = delegate.continuationPanel {
                notice.mouseExited(with: TimelineTestEvent(type: .mouseExited, window: notice, location: .zero))
            }
            return pending
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        _ = try await offer()
        guard let panel = delegate.continuationPanel, let content = panel.contentView else {
            throw NSError(domain: "LineSmokeCheck", code: 31, userInfo: [NSLocalizedDescriptionKey: "Continuation panel missing"])
        }
        try require(panel.isVisible && !panel.canBecomeKey && !panel.isKeyWindow && !panel.isMainWindow,
                    "Automatic continuation must show without becoming key or main")
        try require(button.isHighlighted, "The menu bar icon must highlight while the continuation notice is visible")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost,
                    "Automatic presentation must preserve the frontmost application")
        let anchor = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
        try require(abs(panel.frame.maxY - (anchor.minY - 8)) < 1, "Continuation must anchor just below the menu bar")
        guard let reject = descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Reject" }) else {
            throw NSError(domain: "LineSmokeCheck", code: 32, userInfo: [NSLocalizedDescriptionKey: "Native Reject button missing"])
        }
        try require(reject.isEnabled && reject.acceptsFirstMouse(for: nil), "Reject must accept the first click without activation")
        try require(accessibilityElement(named: "Reject", in: content) != nil, "Reject must have an accessibility title")
        panel.mouseEntered(with: TimelineTestEvent(type: .mouseEntered, window: panel, location: .zero))
        reject.performClick(nil)
        try await settle()
        try require(model.interruptions?.pendingContinuation == nil && !panel.isVisible && store.runningEntry == nil,
                    "Reject must close the panel without recording the provisional interval")
        try require(!button.isHighlighted, "Reject must clear the menu bar highlight")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost,
                    "Reject must preserve the frontmost application")

        let outside = try await offer()
        let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 10, y: 10), modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: otherWindow.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(event)
        }
        try await settle()
        model.pollContinuation()
        try require(model.interruptions?.pendingContinuation?.id == outside.id && store.runningEntry == nil,
                    "Clicks outside the notice must leave the countdown pending")
        try require(delegate.continuationPanel?.isVisible == true,
                    "The continuation notice must remain visible after outside clicks")
        try require(button.isHighlighted, "Outside clicks must preserve the notice's menu bar highlight")
        guard let notice = delegate.continuationPanel, let noticeContent = notice.contentView,
              let accept = descendants(noticeContent).compactMap({ $0 as? NSButton }).first(where: { $0.title == "OK" }) else {
            throw NSError(domain: "LineSmokeCheck", code: 33, userInfo: [NSLocalizedDescriptionKey: "Native OK button missing"])
        }
        try require(accept.isEnabled && accept.acceptsFirstMouse(for: nil), "OK must accept the first click without activation")
        try require(accessibilityElement(named: "OK", in: noticeContent) != nil, "OK must have an accessibility title")
        let hoverAreas = descendants(noticeContent).flatMap(\.trackingAreas).filter { ($0.owner as? ContinuationPanel) === notice }
        try require(hoverAreas.contains { $0.options.contains([.activeAlways, .mouseEnteredAndExited, .inVisibleRect]) },
                    "The full notice must track hover even while Tape is inactive")
        notice.mouseEntered(with: TimelineTestEvent(type: .mouseEntered, window: notice, location: .zero))
        let frozenSeconds = model.interruptions!.remainingSeconds
        try await Task.sleep(for: .milliseconds(1_200))
        model.pollContinuation()
        try require(model.interruptions?.remainingSeconds == frozenSeconds && store.runningEntry == nil,
                    "Hover must freeze the displayed countdown and keep continuation pending")
        notice.mouseExited(with: TimelineTestEvent(type: .mouseExited, window: notice, location: .zero))
        try await Task.sleep(for: .milliseconds(1_200))
        try require(model.interruptions!.remainingSeconds < frozenSeconds,
                    "Leaving the notice must resume the remaining countdown")
        notice.mouseEntered(with: TimelineTestEvent(type: .mouseEntered, window: notice, location: .zero))
        let beforeAccept = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let acceptedEntry = store.entries.last!
        accept.performClick(nil)
        try await settle()
        try require(store.runningEntry?.id == acceptedEntry.id && model.interruptions?.pendingContinuation == nil && !notice.isVisible,
                    "OK must resume immediately and close the notice")
        try require(!button.isHighlighted, "OK must clear the menu bar highlight")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == beforeAccept,
                    "OK must preserve the frontmost application")
        try require(model.stop(), "Stop work accepted with OK")

        _ = try await offer()
        let openedEntry = store.entries.last!
        try clickStatusItem(button)
        try await settle()
        try require(store.runningEntry?.id == openedEntry.id && model.interruptions?.pendingContinuation == nil,
                    "Opening Tape must immediately accept continuation")
        try require(accessibilityElement(named: "Reject continuation", in: contentView(popover)) == nil,
                    "The main popover must never contain a continuation dialog")
        try clickStatusItem(button)
        try await settle()
        try require(model.stop(), "Stop work accepted by opening Tape")

        let pending = try await offer()
        let timerEntry = store.entries.last!
        // Exercise the real timer with a bounded wait, without changing its production duration.
        let deadline = ContinuousClock.now + .seconds(12)
        while store.runningEntry == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(store.runningEntry?.id == timerEntry.id && store.runningEntry?.start == timerEntry.start && store.runningTask?.id == pending.task.id,
                    "The timer must reopen the original entry after a short break")
        try require(!button.isHighlighted, "Countdown completion must clear the menu bar highlight")
        try require(model.stop(), "Stop automatically continued work")

        let old = Date.now - 3_600
        try store.createEntry(named: "History", selection: store.prepareEntry(from: old, to: old + 600))
        let historical = store.entries[0]
        for action in ["picker", "edit", "resize", "draw", "overwrite", "start", "stop", "color", "reassign", "delete", "quit"] {
            _ = try await offer()
            switch action {
            case "picker":
                try clickStatusItem(button)
                try await settle()
                try pressAccessibleControl(named: "Switch task", in: contentView(popover))
                try require(model.stop(), "Stop work already accepted when opening Tape")
            case "edit":
                model.editEntry(id: historical.id)
                model.cancelEntry()
            case "resize":
                let fraction = model.timeline.fraction(for: historical.start, now: .now)
                try require(model.beginResizing(at: fraction, tolerance: 5 / 580) != nil, "Begin resizing")
                model.cancelEntry()
            case "draw", "overwrite":
                try require(model.beginDrawing(at: 0.1, overwriting: action == "overwrite"), "Begin drawing")
                model.cancelEntry()
            case "start":
                try require(model.start("Manual work"), "Manual start")
                try require(model.stop(), "Stop manual work")
            case "stop":
                try require(model.stop(), "Explicit Stop")
            case "color":
                try require(model.saveTaskColor(id: historical.taskID, color: .purple), "Recolor")
            case "reassign":
                try require(model.reassignEntry(id: historical.id, taskName: "Reassigned"), "Reassign")
            case "delete":
                try require(model.deleteEntry(id: historical.id), "Delete")
            default:
                try require(delegate.applicationShouldTerminate(NSApp) == .terminateNow, "Quit must cancel continuation")
            }
            model.pollContinuation()
            try require(model.interruptions?.pendingContinuation == nil && model.interruptions?.interruptedTask == nil,
                        "\(action) must cancel continuation even if the action is subsequently abandoned")
        }
    }

    private static func checkSystemActivity(button: NSStatusBarButton, popover: NSPopover, model: AppModel) async throws {
        // Inject private centers, never post fake system events to other apps or the release build.
        let workspace = NotificationCenter()
        let locks = NotificationCenter()
        let delegate = NSApp.delegate as! AppDelegate
        let monitor = SystemActivityMonitor(workspace: workspace, lockNotifications: locks,
                                            receive: delegate.handleSystemEvent)
        defer { withExtendedLifetime(monitor) {} }
        let store = model.store!
        try require(model.start("Lock check"), "Start lock check")
        try await settle()
        let running = store.runningEntry!
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        model.checkpoint()
        try require(store.runningEntry?.id == running.id, "Display sleep and unrelated session notifications must not stop tracking")
        try clickStatusItem(button)
        try await settle()
        model.editEntry(id: running.id)
        let beforeLock = Date.now
        locks.post(name: SystemActivityMonitor.locked, object: nil)
        let afterLock = Date.now
        try require(store.runningEntry == nil && store.entries.count == 1, "Screen lock must stop exactly one entry")
        let end = store.entries[0].end!
        try require(end >= beforeLock && end <= afterLock, "Lock must save synchronously at receipt")
        try require(model.interruptions?.interruptedTask?.id == running.taskID, "Remember the interrupted task")
        try await settle()
        try require(!popover.isShown && model.editingEntryID == nil, "Lock must close the popover and discard editing state")
        locks.post(name: SystemActivityMonitor.locked, object: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try require(model.interruptions?.isAvailable == false, "Wake while locked is not a usable return")
        locks.post(name: SystemActivityMonitor.unlocked, object: nil)
        try require(model.interruptions?.isAvailable == true && store.runningEntry == nil, "Unlock must leave tracking stopped")
        try require(store.entries[0].end == end, "Duplicate events must not extend the entry")
        try require(model.start("Sleep check"), "Start sleep check")
        try await settle()
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        locks.post(name: SystemActivityMonitor.locked, object: nil)
        locks.post(name: SystemActivityMonitor.unlocked, object: nil)
        try require(model.interruptions?.isAvailable == false, "Unlock before wake is not a usable return")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try require(model.interruptions?.isAvailable == true && store.runningEntry == nil, "Sleep return must stay stopped")
        model.rejectContinuation()
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try require(store.entries.count == 2 && model.interruptions?.interruptedTask == nil, "Idle sleep must not invent tracked work")
        try require(model.errorMessage == nil, "Notification handling must not produce errors")
    }

    private static func checkResizeOverwrite(button: NSStatusBarButton, popover: NSPopover, model: AppModel) async throws {
        try await settle()
        try clickStatusItem(button)
        try await settle()
        let store = model.store!
        let base = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970 / 60) * 60)
        for commandAtStart in [false, true] {
            for commandAtRelease in [false, true] {
                model.cancelEntry()
                for entry in store.entries { try store.deleteEntry(id: entry.id) }
                for (name, start, end) in [("Resize", -6_000.0, -4_800.0), ("Covered", -4_200.0, -3_000.0), ("Trimmed", -2_400.0, -1_200.0)] {
                    try store.createEntry(named: name, selection: store.prepareEntry(from: base + start, to: base + end))
                }
                try await settle()
                let original = store.entries
                let first = original[0]
                let input = try timelineInput(in: popover)
                let window = input.window!
                let from = model.timeline.fraction(for: first.end!, now: .now)
                let to = model.timeline.fraction(for: base - 1_800, now: .now)
                func send(_ type: NSEvent.EventType, _ fraction: Double, command: Bool) {
                    _ = input.handle(TimelineTestEvent(type: type, window: window,
                        location: input.convert(NSPoint(x: input.bounds.width * fraction, y: 60), to: nil),
                        flags: command ? .command : []))
                }
                send(.leftMouseDown, from, command: commandAtStart)
                send(.leftMouseDragged, to, command: commandAtStart)
                try require(model.resizingEntryID == first.id && !model.isDrawing,
                            "Entry edges must resize even when Command is already held")
                try require(model.drawnRange?.end == (commandAtStart ? base - 1_800 : original[1].start),
                            "Resize preview must use the initial Command state")
                send(.flagsChanged, to, command: true)
                try require(model.drawnRange?.end == base - 1_800 && model.isOverwriting,
                            "Pressing Command without moving must immediately extend across neighbors")
                send(.flagsChanged, to, command: false)
                try require(model.drawnRange?.end == original[1].start && !model.isOverwriting,
                            "Releasing Command without moving must immediately clamp to the neighbor")
                send(.flagsChanged, to, command: true)
                try require(store.entries == original, "Resizing previews must not write or delete time")
                let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
                _ = input.handle(escape)
                try require(model.resizingEntryID == nil && model.drawnRange == nil && store.entries == original,
                            "Escape must discard an overwrite resize without changing records")
                send(.leftMouseDown, from, command: commandAtStart)
                send(.leftMouseDragged, to, command: commandAtStart)
                send(.flagsChanged, to, command: true)
                // Mouse-up is authoritative even if a modifier-change event was not delivered first.
                send(.leftMouseUp, to, command: commandAtRelease)
                try require(model.entryError == nil && model.resizingEntryID == nil && model.entrySelection == nil,
                            "Resize must commit without opening a task picker")
                if commandAtRelease {
                    try require(store.entries.count == 2 && store.tasks.count == 2,
                                "Overwrite resize must remove the fully covered entry and orphan task")
                    try require(store.entries[0].id == first.id && store.entries[0].end == base - 1_800 && store.entries[1].start == base - 1_800,
                                "Overwrite resize must keep the resized entry and trim the later neighbor")
                } else {
                    try require(store.entries.count == 3 && store.entries[0].end == original[1].start && Array(store.entries.dropFirst()) == Array(original.dropFirst()),
                                "Releasing Command at mouse-up must preserve neighbors")
                }
            }
        }
        try await settle()
        try requireAnchored(popover, to: button)
    }

    private static func checkOverwrite(button: NSStatusBarButton, popover: NSPopover, model: AppModel) async throws {
        try await settle()
        try clickStatusItem(button)
        try await settle()
        let store = model.store!
        let instant = Date.now
        try store.createEntry(named: "Original", selection: store.prepareEntry(
            from: model.timeline.date(at: 0.05, now: instant), to: model.timeline.date(at: 0.35, now: instant)))
        try store.createEntry(named: "Tail", selection: store.prepareEntry(
            from: model.timeline.date(at: 0.38, now: instant), to: model.timeline.date(at: 0.46, now: instant)))
        let original = store.entries
        try await settle()
        try draw(0.15, 0.25, in: popover)
        try require(model.entrySelection == nil, "Ordinary drawing must still reject an occupied origin")
        try draw(0.15, 0.25, in: popover, command: true, finish: false)
        try require(model.drawnRange != nil && store.entries == original, "Command-drag must preview over an entry without saving")
        let input = try timelineInput(in: popover)
        let window = input.window!
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        _ = input.handle(escape)
        try require(model.drawnRange == nil && !model.isDrawing && store.entries == original, "Escape must cancel overwrite drawing")
        try draw(0.15, 0.25, in: popover, command: true, release: 0.15)
        try require(model.entrySelection == nil && model.entryError == nil, "Collapsed overwrite must silently cancel")
        try draw(0.15, 0.25, in: popover, command: true)
        try await settle()
        try require(accessibilityElement(named: "Cancel", in: contentView(popover)) == nil,
                    "Overwrite picker must use the compact layout without a Cancel button")
        window.sendEvent(escape)
        try await settle()
        try require(model.entrySelection == nil && store.entries == original, "Escape in the overwrite picker must preserve entries")
        try draw(0.15, 0.25, in: popover, command: true)
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try require(model.entrySelection == nil && store.entries == original, "Closing must discard an overwrite draft")
        try draw(0.15, 0.25, in: popover, command: true)
        try await settle()
        try pressAccessibleControl(named: "Use Original", in: contentView(popover))
        try await settle()
        try require(store.entries == original, "Overwriting inside the same task must keep one continuous original entry")
        try draw(0.15, 0.25, in: popover, command: true)
        try await settle()
        try require(accessibilityElement(named: "Overwrite", in: contentView(popover)) != nil, "Overwrite must be explicit in the task picker")
        let split = try requireSelection(model)
        try enterTaskName("Replacement", in: popover)
        try await settle()
        try require(store.entries.count == 4 && store.entries[0].end == split.start && store.entries[2].start == split.end,
                    "Committing a middle overwrite must split the original")
        try draw(0.44, 0.10, in: popover, command: true)
        try await settle()
        try pressAccessibleControl(named: "Use Replacement", in: contentView(popover))
        try await settle()
        try require(store.entries.count == 3 && store.tasks.count == 3, "Reverse overwrite must cross multiple entries and reuse a task")
        try draw(0.43, 0.55, in: popover, command: true)
        try await settle()
        let live = try requireSelection(model)
        try require(live.end == nil, "Overwrite through Now must retain running intent")
        try pressAccessibleControl(named: "Use Original", in: contentView(popover))
        try await settle()
        try require(store.runningEntry?.start == live.start && store.runningTask?.name == "Original" && store.entries.count == 3,
                    "Through-Now overwrite must start the chosen task and remove covered entries")
        try require(store.tasks.count == 2 && !store.tasks.contains(where: { $0.name == "Tail" }),
                    "Overwriting a task's final entry must delete the task")
        try await openPicker(named: "Switch task", in: popover)
        try require(accessibilityElement(named: "Switch to Tail", in: contentView(popover)) == nil,
                    "Deleted tasks must disappear from picker suggestions")
        try pressAccessibleControl(named: "Switch task", in: contentView(popover))
        try await settle()
        try requireAnchored(popover, to: button)
        try await requireStablePosition(popover)
    }

    private static func requireSelection(_ model: AppModel) throws -> EntrySelection {
        try require(model.entrySelection != nil, "Drawing must produce a selection")
        return model.entrySelection!
    }

    private static func checkCreation(button: NSStatusBarButton, popover: NSPopover, model: AppModel) async throws {
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try requireAnchored(popover, to: button)
        func inputView() throws -> TimelineInputView {
            try timelineInput(in: popover)
        }
        func draw(_ from: Double, _ to: Double, finish: Bool = true, release: Double? = nil) throws {
            try Self.draw(from, to, in: popover, finish: finish, release: release)
        }
        func escape() throws {
            let window = try contentView(popover).window!
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            if !(try inputView()).handle(event) { window.sendEvent(event) }
        }
        try draw(0.1, 0.2)
        try await settle()
        try require(model.entrySelection?.end != nil, "Historical drag must open a completed-entry draft")
        let firstSelection = model.entrySelection!
        try require(firstSelection.start.timeIntervalSince1970.truncatingRemainder(dividingBy: 300) == 0 &&
                    firstSelection.end!.timeIntervalSince1970.truncatingRemainder(dividingBy: 300) == 0,
                    "The default eight-hour view must snap to five-minute boundaries")
        try require(model.store!.entries.isEmpty && model.store!.tasks.isEmpty, "Drawing must not save a task or entry")
        try requireAnchored(popover, to: button)
        let fields = try descendants(contentView(popover)).compactMap { $0 as? NSTextField }
        try require(fields.contains(where: { $0.isEditable && $0.currentEditor() != nil }), "Drawing must focus the task picker")
        try enterTaskName("Past work", in: popover)
        try await settle()
        try require(model.store!.entries.count == 1 && model.store!.runningEntry == nil, "Historical task submission must save a completed entry")
        try require(model.store!.entries[0].start == firstSelection.start && model.store!.entries[0].end == firstSelection.end, "Saved timestamps must match the selection")
        try requirePickerHidden(popover)
        try draw(0.25, 0.28, release: 0.25)
        try require(model.entrySelection == nil && model.entryError == nil && !model.isDrawing,
                    "Dragging back to the origin must cancel silently")
        let snapDate = Date(timeIntervalSince1970: (model.timeline.date(at: 0.25, now: .now).timeIntervalSince1970 / 300).rounded() * 300)
        let snapFraction = model.timeline.fraction(for: snapDate, now: .now)
        try draw(snapFraction, 0.28, release: snapFraction + 0.001)
        try await settle()
        try require(model.entrySelection == nil && model.entryError == nil && model.drawnRange == nil,
                    "A selection that snaps to zero must cancel silently")
        try require(model.store!.entries.count == 1 && model.store!.tasks.count == 1, "Collapsed selections must not save records")
        try requirePickerHidden(popover)
        try draw(0.25, 0.28)
        try await settle()
        try enterTaskName("Discard me", in: popover, submit: false)
        try escape()
        try await settle()
        try require(model.entrySelection == nil && model.store!.tasks.count == 1, "Escape must discard the draft and typed task")
        try requirePickerHidden(popover)
        try draw(0.25, 0.28, finish: false)
        try require(model.isDrawing, "Mouse drag must show a selection preview")
        try escape()
        try require(!model.isDrawing && model.drawnRange == nil, "Escape during drawing must cancel the preview")
        try draw(0.4, 0.3)
        try await settle()
        try pressAccessibleControl(named: "Use Past work", in: contentView(popover))
        try await settle()
        try require(model.store!.entries.count == 2 && model.store!.tasks.count == 1, "Reverse drag must reuse the selected task")
        try draw(0.05, 0.25, finish: false)
        try require(model.drawnRange?.end == firstSelection.start, "Drag preview must stop at the next entry")
        try escape()
        try draw(0.05, 0.25)
        try await settle()
        try require(model.entrySelection?.end == firstSelection.start && model.entryError == nil && model.store!.entries.count == 2,
                    "Releasing at a neighboring entry must open the picker for the available interval")
        try escape()
        try draw(0.15, 0.25)
        try require(model.entrySelection == nil && !model.isDrawing, "Dragging from an existing entry must not create another entry")
        try draw(0.7, 0.8)
        try require(model.entryError != nil && model.entrySelection == nil, "Wholly future drawing must be rejected")
        try escape()
        try draw(0.25, 0.28)
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try require(model.entrySelection == nil && model.store!.entries.count == 2, "Closing must discard the draft")
        try requirePickerHidden(popover)
        try draw(0.45, 0.55)
        try await settle()
        let runningStart = model.entrySelection?.start
        try require(runningStart != nil && model.entrySelection?.end == nil,
                    "Drawing through Now must retain running intent; selection=\(String(describing: model.entrySelection)), error=\(String(describing: model.entryError)), drawing=\(model.isDrawing)")
        try enterTaskName("Past work", in: popover)
        try await settle()
        try require(model.store!.runningEntry?.start == runningStart && model.store!.entries.count == 3, "Delayed task submission must start from the drawn start")
        try require(model.store!.runningEntry!.duration(at: .now) > 540, "Running entry must include historical and picker time")
        try requireAnchored(popover, to: button)
        try await requireStablePosition(popover)
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
        let initialSpan = model.defaultTimelineSpan
        try require(model.timeline.span == initialSpan && model.timeline.isFollowingNow, "Opening must use the configured default and follow now")
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
        try require(model.defaultTimelineSpan == initialSpan, "Pinching must not change the configured default")
        let outsideReset = TimelineTestEvent(type: .smartMagnify, window: window, location: NSPoint(x: -100, y: -100))
        try require(!input.handle(outsideReset) && model.timeline.span == initialSpan / 2, "Smart zoom outside the timeline must be ignored")
        let center = model.timeline.date(at: 0.5, now: .now)
        let reset = TimelineTestEvent(type: .smartMagnify, window: window, location: location)
        try require(input.handle(reset), "Two-finger double-tap must be handled")
        try await Task.sleep(for: .milliseconds(400))
        try require(model.timeline.span == initialSpan, "Smart zoom must reset to the configured default")
        try require(!model.timeline.isFollowingNow && abs(model.timeline.date(at: 0.5, now: .now).timeIntervalSince(center)) < 0.001, "Resetting zoom must preserve the browsed center")
        _ = input.handle(reset)
        try await Task.sleep(for: .milliseconds(400))
        try require(model.timeline.span == initialSpan && model.timeline.isFollowingNow, "A second double-tap must return to Now at the default scale")
        _ = input.handle(reset)
        try await Task.sleep(for: .milliseconds(400))
        try require(model.timeline.isFollowingNow, "Further double-taps at Now must keep following")
        // Force animation for this check even if the test Mac has Reduce Motion enabled.
        model.timeline.zoom(factor: 2, anchorFraction: 0.5, now: .now)
        let zoomStart = model.timeline.span
        model.resetTimeline(animated: true)
        try require(model.timeline.span == zoomStart, "Animated zoom must not jump immediately")
        try await Task.sleep(for: .milliseconds(100))
        try require(model.timeline.span > zoomStart && model.timeline.span < initialSpan && model.timeline.isFollowingNow,
                    "Zoom must pass through intermediate scales while keeping Now centered")
        try await Task.sleep(for: .milliseconds(350))
        try require(model.timeline.span == initialSpan,
                    "Animated zoom must finish at the configured default scale")
        _ = input.handle(horizontal)
        let animationStart = model.timeline.date(at: 0.5, now: .now)
        model.resetTimeline(animated: true)
        try require(model.timeline.date(at: 0.5, now: .now) == animationStart,
                    "Animated return must not jump immediately")
        try await Task.sleep(for: .milliseconds(100))
        let intermediate = model.timeline.date(at: 0.5, now: .now)
        try require(intermediate > animationStart && intermediate < .now,
                    "Animated return must pass through intermediate times")
        _ = input.handle(horizontal)
        let interruptedRange = model.timeline.range(at: .now)
        try await Task.sleep(for: .milliseconds(350))
        try require(model.timeline.range(at: .now) == interruptedRange,
                    "Scrolling must interrupt animation without a later jump")
        model.resetTimeline(animated: false)
        try require(model.timeline.isFollowingNow, "Reduced-motion reset must finish immediately")
        // Leave a temporary pinch scale; reopening must discard it.
        _ = input.handle(TimelineTestEvent(type: .magnify, window: window, location: location,
                                         magnification: 1, phase: .began))
        _ = input.handle(TimelineTestEvent(type: .magnify, window: window, location: location, phase: .ended))
        _ = input.handle(horizontal)
        try await settle()
        try requireAnchored(popover, to: button)
        try await requireStablePosition(popover)
        try clickStatusItem(button)
        try await settle()
        try clickStatusItem(button)
        try await settle()
        try require(model.timeline.isFollowingNow && model.timeline.span == initialSpan, "Reopening must follow now at the configured default")
        try requireAnchored(popover, to: button)
        try await requireStablePosition(popover)
        model.setDefaultZoomHours(model.defaultZoomHours == 8 ? 4 : 12)
        try require(model.settingsError == nil, "Configured default must save")
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
        try pressAccessibleControl(named: title, in: contentView(popover))
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

    private static func checkTags(button: NSStatusBarButton, popover: NSPopover, model: AppModel, output: URL) async throws {
        try await settle()
        let store = model.store!
        let base = Date.now
        try store.createEntry(named: "Study :Универ :deepwork", selection: store.prepareEntry(from: base - 1_200, to: base - 900))
        try store.createEntry(named: "Coding :coding", selection: store.prepareEntry(from: base - 600, to: base - 300))
        try clickStatusItem(button)
        try await settle()
        try await openPicker(named: "Start task", in: popover)

        func field() throws -> NSTextField {
            guard let field = descendants(try contentView(popover)).compactMap({ $0 as? NSTextField }).first(where: \.isEditable) else {
                throw NSError(domain: "LineSmokeCheck", code: 30)
            }
            return field
        }
        func key(_ characters: String, _ code: UInt16) throws {
            let window = try field().window!
            window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
        }

        try enterTaskName("Building :de DayLine", in: popover, submit: false)
        let middleEditor = try field().currentEditor() as! NSTextView
        middleEditor.setSelectedRange(NSRange(location: ("Building :de" as NSString).length, length: 0))
        try await settle()
        try pressAccessibleControl(named: "Insert tag :deepwork", in: contentView(popover))
        try await settle()
        try require(TaskInput(try field().stringValue) == TaskInput("Building DayLine :deepwork"),
                    "Clicking a completion at the caret must preserve the surrounding name")
        try require(store.runningEntry == nil, "Clicking a completion must not submit the task")
        try enterTaskName("Building DayLine :dayline :coding :deep", in: popover, submit: false)
        try await settle()
        try require(accessibilityElement(named: "Insert tag :deepwork", in: contentView(popover)) != nil, "Tag prefix must offer saved tags")
        try key("", 125)
        try key("\t", 48)
        try await settle()
        try require(try field().stringValue == "Building DayLine :dayline :coding :deepwork ", "Tab must insert a selected tag as plain text")
        try require(store.runningEntry == nil, "Accepting a completion must not start tracking")
        try key("\r", 36)
        try await settle()
        try require(store.runningTask?.name == "Building DayLine" && store.runningTask?.tags == ["dayline", "coding", "deepwork"],
                    "Return must save separate task tags")
        let running = store.runningEntry!

        try await openPicker(named: "Switch task", in: popover)
        try enterTaskName("Building DayLine :Ун", in: popover, submit: false)
        try await settle()
        try require(accessibilityElement(named: "Insert tag :универ", in: contentView(popover)) != nil, "Cyrillic completion must ignore case")
        try key("", 125)
        try key("\r", 36)
        try await settle()
        try require(try field().stringValue.hasSuffix(":универ "), "Return with a selection must only complete the tag")
        try require(store.runningEntry == running, "Completion must preserve tracking")
        try key("\r", 36)
        try await settle()
        try require(store.runningEntry == running && store.runningTask!.tags.contains("универ"), "Adding tags must not split a running entry")

        try await openPicker(named: "Switch task", in: popover)
        try enterTaskName(":coding ", in: popover, submit: false)
        try await settle()
        try require(accessibilityElement(named: "Switch to Study", in: contentView(popover)) == nil, "Completed tags must filter tasks")
        try require(accessibilityElement(named: "Switch to Building DayLine", in: contentView(popover)) != nil, "Tag search must find matching tasks")
        try key("\r", 36)
        try await settle()
        try require(store.runningEntry == running && store.tasks.count == 3, "Tag-only input must not create a task")

        try enterTaskName("Building DayLine :co", in: popover, submit: false)
        try await settle()
        try key("\u{1b}", 53)
        try await settle()
        try require(accessibilityElement(named: "Insert tag :coding", in: contentView(popover)) == nil, "Escape must dismiss completion")
        try require(try field().stringValue == "Building DayLine :co", "First Escape must preserve the draft")
        try key("\u{1b}", 53)
        try await settle()
        try requirePickerHidden(popover)

        try await openPicker(named: "Switch task", in: popover)
        try enterTaskName("Building DayLine :co", in: popover, submit: false)
        try await settle()
        try key("\r", 36)
        try await settle()
        try require(store.runningTask!.tags.contains("co") && store.runningEntry == running, "Return without a selected suggestion must submit the typed tag")

        try await openPicker(named: "Switch task", in: popover)
        try enterTaskName("Building :newtag", in: popover, submit: false)
        try await settle()
        try pressAccessibleControl(named: "Switch to Building DayLine", in: contentView(popover))
        try await settle()
        try require(store.runningEntry == running && store.runningTask!.tags.contains("newtag"), "Choosing a task must retain typed tags")

        model.editEntry(id: running.id)
        try await settle()
        try require(try field().stringValue == store.runningTask!.inputText, "Editor must include saved tags")
        try enterTaskName("Building DayLine :co", in: popover, submit: false)
        try await settle()
        try key("\u{1b}", 53)
        try await settle()
        try require(model.editingEntryID == running.id && store.runningTask!.tags.contains("newtag"),
                    "First Escape in the editor must dismiss completion without canceling or saving the draft")
        try key("\u{1b}", 53)
        try await settle()
        try require(model.editingEntryID == nil && store.runningTask!.tags.contains("newtag"),
                    "Second Escape must discard the edited tag draft")
        model.editEntry(id: running.id)
        try await settle()
        try enterTaskName("Building DayLine :research", in: popover)
        try await settle()
        try require(store.runningEntry == running && store.runningTask?.tags == ["research"], "Editing replaces task tags without changing entry time")
        try require(!store.tags.contains("newtag") && !store.tags.contains("co"), "Unused tags must disappear")
        try enterTaskName("Study", in: popover, submit: false)
        try await settle()
        try pressAccessibleControl(named: "Use Study", in: contentView(popover))
        try await settle()
        try require(store.runningTask?.name == "Building DayLine", "Selecting another task must wait for confirmation")
        try require(try field().stringValue == "Study :универ :deepwork", "Selection must load destination tags without source tags")
        try key("\r", 36)
        try await settle()
        try require(store.runningTask?.name == "Study" && store.runningTask?.tags == ["универ", "deepwork"], "Return must confirm the destination tags")
        try require(!store.tags.contains("research"), "Removing the last source entry must prune its tags")
        if ProcessInfo.processInfo.environment["LINE_SMOKE_CAPTURE"] == "1", let window = popover.contentViewController?.view.window {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent("tag-editor.png").path]
            try capture.run()
            capture.waitUntilExit()
        }
        try enterTaskName("Study", in: popover)
        try await settle()
        try require(store.runningTask?.tags.isEmpty == true && store.tags == ["coding"], "Removing tags must clear all entries for the task")
        try enterTaskName("Study :discarded", in: popover, submit: false)
        try key("\u{1b}", 53)
        try await settle()
        try require(store.runningTask?.tags.isEmpty == true, "Cancel must discard tag edits")
        try requireAnchored(popover, to: button)
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

    private static func pressAccessibleControl(named name: String, in root: NSView, role: NSAccessibility.Role = .button) throws {
        guard let object = accessibilityElement(named: name, in: root),
              attribute("accessibilityRole", of: object) as? String == role.rawValue else {
            throw NSError(domain: "LineSmokeCheck", code: 6, userInfo: [NSLocalizedDescriptionKey: "Accessible \(name) control is missing"])
        }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector), let implementation = object.method(for: selector) else {
            throw NSError(domain: "LineSmokeCheck", code: 7, userInfo: [NSLocalizedDescriptionKey: "Accessible \(name) control has no press action"])
        }
        // SwiftUI nodes implement public accessibility methods without declaring the full protocol.
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let pressed = unsafeBitCast(implementation, to: Press.self)(object, selector)
        try require(pressed, "Accessible \(name) control must be operable")
    }

    private static func accessibilityElement(named name: String, in element: Any) -> NSObject? {
        guard let object = element as? NSObject else { return nil }
        if attribute("accessibilityLabel", of: object) as? String == name || attribute("accessibilityTitle", of: object) as? String == name ||
            attribute("accessibilityValue", of: object) as? String == name {
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
