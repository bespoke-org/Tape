import AppKit
import SwiftUI
import LineCore

/// Native timeline gestures, confined to the timeline and its window.
struct TimelineInput: NSViewRepresentable {
    let scroll: (Double, Double) -> Void
    let zoom: (Double, Double) -> Void
    let resetZoom: () -> Void
    let drawingBounds: CGRect
    let interruptNavigation: () -> Void
    let beginDraw: (Double, Bool) -> Bool
    let updateDraw: (Double) -> Void
    let endDraw: (Double, Double) -> Void
    let cancelDraw: () -> Void
    let selectEntry: (Double, Double) -> Void
    let resizeEdge: (Double, Double) -> EntryEdge?
    let beginResize: (Double, Double) -> EntryEdge?
    let updateResize: (Double, Bool) -> Void
    let endResize: (Double, Double, Bool) -> Void
    let cancelEdit: () -> Bool

    func makeNSView(context: Context) -> TimelineInputView { TimelineInputView() }

    func updateNSView(_ view: TimelineInputView, context: Context) {
        view.scroll = scroll
        view.zoom = zoom
        view.resetZoom = resetZoom
        view.drawingBounds = drawingBounds
        view.interruptNavigation = interruptNavigation
        view.beginDraw = beginDraw
        view.updateDraw = updateDraw
        view.endDraw = endDraw
        view.cancelDraw = cancelDraw
        view.selectEntry = selectEntry
        view.resizeEdge = resizeEdge
        view.beginResize = beginResize
        view.updateResize = updateResize
        view.endResize = endResize
        view.cancelEdit = cancelEdit
        view.refreshCursor()
    }

    static func dismantleNSView(_ view: TimelineInputView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class TimelineInputView: NSView {
    var scroll: (Double, Double) -> Void = { _, _ in }
    var zoom: (Double, Double) -> Void = { _, _ in }
    var resetZoom: () -> Void = {}
    var drawingBounds: CGRect = .zero
    var interruptNavigation: () -> Void = {}
    var beginDraw: (Double, Bool) -> Bool = { _, _ in false }
    var updateDraw: (Double) -> Void = { _ in }
    var endDraw: (Double, Double) -> Void = { _, _ in }
    var cancelDraw: () -> Void = {}
    var selectEntry: (Double, Double) -> Void = { _, _ in }
    var resizeEdge: (Double, Double) -> EntryEdge? = { _, _ in nil }
    var beginResize: (Double, Double) -> EntryEdge? = { _, _ in nil }
    var updateResize: (Double, Bool) -> Void = { _, _ in }
    var endResize: (Double, Double, Bool) -> Void = { _, _, _ in }
    var cancelEdit: () -> Bool = { false }
    private var hoverArea: NSTrackingArea?
    private var showsResizeCursor = false
    private let resizeTolerance: CGFloat = 5
    private var monitor: Any?
    private var magnificationScale: Double = 1
    private var dragOrigin: NSPoint?
    private var dragOverwrites = false
    private var isDrawing = false
    private var lastResizeFraction: Double?
    private var draggingEdge: EntryEdge?
    private var isResizing: Bool { draggingEdge != nil }

    override var isFlipped: Bool { true }

    // Leave hit testing to SwiftUI; the monitor handles timeline gestures.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                            .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseMoved(with event: NSEvent) { cursorUpdate(with: event) }
    override func mouseEntered(with event: NSEvent) { cursorUpdate(with: event) }
    override func mouseExited(with event: NSEvent) {
        if !isResizing { clearResizeCursor() }
    }

    func refreshCursor(modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        guard let window, window.isVisible, window.isKeyWindow else {
            clearResizeCursor()
            return
        }
        updateCursor(at: convert(window.mouseLocationOutsideOfEventStream, from: nil), modifiers: modifiers)
    }

    private func updateCursor(at point: NSPoint, modifiers: NSEvent.ModifierFlags) {
        let canHover = !isDrawing && !modifiers.contains(.control) && drawingBounds.contains(point)
        let edge = draggingEdge ?? (canHover ? resizeEdge(point.x / max(bounds.width, 1), resizeTolerance / max(bounds.width, 1)) : nil)
        if let edge {
            EntryResizeCursor.cursor(for: edge).set()
            showsResizeCursor = true
        } else {
            clearResizeCursor()
        }
    }

    private func clearResizeCursor() {
        if showsResizeCursor { NSCursor.arrow.set() }
        showsResizeCursor = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .smartMagnify,
                                                            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stopMonitoring() {
        clearResizeCursor()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        dragOrigin = nil
        dragOverwrites = false
        isDrawing = false
        draggingEdge = nil
        lastResizeFraction = nil
    }

    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        if event.type == .flagsChanged {
            if isResizing, let fraction = lastResizeFraction {
                updateResize(fraction, event.modifierFlags.contains(.command))
            }
            refreshCursor(modifiers: event.modifierFlags)
            return false
        }
        if event.type == .keyDown {
            guard event.keyCode == 53, window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
            guard isDrawing || isResizing else { return cancelEdit() }
            dragOrigin = nil
            isDrawing = false
            draggingEdge = nil
            lastResizeFraction = nil
            cancelDraw()
            refreshCursor()
            return true
        }
        let point = convert(event.locationInWindow, from: nil)
        let fraction = point.x / max(bounds.width, 1)
        if event.type == .leftMouseDown {
            dragOrigin = drawingBounds.contains(point) && !event.modifierFlags.contains(.control) ? point : nil
            if dragOrigin != nil { interruptNavigation() }
            lastResizeFraction = nil
            dragOverwrites = event.modifierFlags.contains(.command)
            // Own the full pointer sequence so entry buttons cannot activate after a drag.
            return dragOrigin != nil
        }
        if event.type == .leftMouseDragged, let origin = dragOrigin {
            if !isDrawing && !isResizing {
                guard abs(point.x - origin.x) >= 3 else { return false }
                let start = origin.x / max(bounds.width, 1)
                draggingEdge = beginResize(start, resizeTolerance / max(bounds.width, 1))
                if !isResizing {
                    guard beginDraw(start, dragOverwrites) else { dragOrigin = nil; return false }
                    isDrawing = true
                }
            }
            if isResizing {
                lastResizeFraction = fraction
                updateResize(fraction, event.modifierFlags.contains(.command))
            } else { updateDraw(fraction) }
            updateCursor(at: point, modifiers: event.modifierFlags)
            return true
        }
        if event.type == .leftMouseUp {
            defer { updateCursor(at: point, modifiers: event.modifierFlags) }
            let origin = dragOrigin
            dragOrigin = nil
            if isResizing {
                draggingEdge = nil
                lastResizeFraction = nil
                endResize(fraction, 3 / max(bounds.width, 1), event.modifierFlags.contains(.command))
                return true
            }
            if !isDrawing, let origin, abs(point.x - origin.x) < 3, drawingBounds.contains(point), !dragOverwrites {
                selectEntry(fraction, 2 / max(bounds.width, 1))
                return true
            }
            guard isDrawing else { return false }
            isDrawing = false
            endDraw(fraction, 3 / max(bounds.width, 1))
            return true
        }
        guard bounds.contains(point) else { return false }
        // Keep the time-to-position mapping fixed for the duration of a drawing gesture.
        if isDrawing || isResizing { return true }
        switch event.type {
        case .smartMagnify:
            magnificationScale = 1
            resetZoom()
            return true
        case .scrollWheel:
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX :
                (event.modifierFlags.contains(.shift) ? event.scrollingDeltaY : 0)
            guard delta != 0 else { return false }
            // AppKit already applies the user's natural-scrolling preference.
            scroll(delta * (event.hasPreciseScrollingDeltas ? 1 : 16), bounds.width)
            return true
        case .magnify:
            if event.phase == .began { magnificationScale = 1 }
            let nextScale = max(0.01, magnificationScale + event.magnification)
            let fraction = convert(event.locationInWindow, from: nil).x / max(bounds.width, 1)
            zoom(nextScale / magnificationScale, fraction)
            magnificationScale = nextScale
            if event.phase == .ended || event.phase == .cancelled || event.phase.isEmpty {
                magnificationScale = 1
            }
            return true
        default:
            return false
        }
    }
}
