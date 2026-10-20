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
            if ProcessInfo.processInfo.environment["LINE_SMOKE_CONTINUATION"] == "1" {
                try await checkContinuation(button: button, popover: popover, model: model)
                try Data("PASS: continuation panel preserves focus, hover pauses the nine-second countdown, OK resumes immediately, Reject and explicit actions cancel, outside clicks preserve the notice and opening Line accepts continuation, and short-break continuation reopens the original entry.\n".utf8)
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
            try pressAccessibleControl(named: "Switch to Build Line", in: contentView(popover))
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
                try require(popover.isShown, "Closing only the color menu must keep Line open")
            }
            // Exercise the production callback registered for clicks in other apps.
            (NSApp.delegate as? AppDelegate)?.dismissForOutsideClick()
            try await settle()
            try require(!popover.isShown, "Leaving Line must dismiss its popover; color menu action: \(menuAction)")
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
        try require(NSCursor.current == NSCursor.arrow, "Command overwrite must not advertise resizing")
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
        try clickEntry(completed.start)
        try require(model.editingEntryID == completed.id, "A shared boundary must select the later entry")
        model.cancelEntry()
        let sharedBoundary = model.timeline.fraction(for: completed.start, now: .now)
        hover(completed.start - model.timeline.span / width)
        try require(NSCursor.current == EntryResizeCursor.end, "Left of a shared boundary must target the earlier entry's end")
        hover(completed.start + model.timeline.span / width)
        try require(NSCursor.current == EntryResizeCursor.start, "Right of a shared boundary must target the later entry's start")
        let resizeTo = model.timeline.fraction(for: completed.start + 120, now: .now)
        try draw(sharedBoundary + 1 / width, resizeTo, in: popover, finish: false)
        hover(original.start)
        try require(NSCursor.current == EntryResizeCursor.start && model.resizingEntryID == completed.id,
                    "The chosen bracket must stay attached to its entry during dragging")
        let releasePoint = hoverInput.convert(NSPoint(x: hoverInput.bounds.width * resizeTo, y: 60), to: nil)
        _ = hoverInput.handle(TimelineTestEvent(type: .leftMouseUp, window: hoverInput.window!, location: releasePoint))
        try require(store.entries[1].start == completed.start + 120 && store.entries[0].end == completed.start,
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
            .first(where: { $0.placeholderString == "Name a new task" }) else {
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
        let to = model.timeline.fraction(for: base - 1_920, now: .now)
        try draw(from, to, in: popover)
        try await settle()
        try require(store.entries[0].start == base - 1_920, "Dragging a completed edge must resize it")
        try require(store.runningEntry?.id == running.id, "Resizing history must leave tracking alone")

        try clickEntry(base - 300)
        try await settle()
        try require(model.editingEntryID == running.id, "Running entries must be editable")
        guard let taskSearch = descendants(try contentView(popover)).compactMap({ $0 as? NSTextField })
            .first(where: { $0.placeholderString == "Name a new task" }) else {
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
        try require(store.runningEntry?.taskID == completed.taskID && store.tasks.count == 1,
                    "Choosing a suggestion must reuse its task and prune the abandoned task")
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
        let movedStart = remaining.start + 120
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
                    "The full notice must track hover even while Line is inactive")
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
                    "Opening Line must immediately accept continuation")
        try require(accessibilityElement(named: "Reject continuation", in: contentView(popover)) == nil,
                    "The main popover must never contain a continuation dialog")
        try clickStatusItem(button)
        try await settle()
        try require(model.stop(), "Stop work accepted by opening Line")

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
                try require(model.stop(), "Stop work already accepted when opening Line")
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
                    "The default four-hour view must snap to five-minute boundaries")
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
