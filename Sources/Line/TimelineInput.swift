import AppKit
import SwiftUI

/// Native timeline gestures, confined to the timeline and its window.
struct TimelineInput: NSViewRepresentable {
    let scroll: (Double, Double) -> Void
    let zoom: (Double, Double) -> Void
    let endZoom: () -> Void
    let resetZoom: () -> Void
    let drawingBounds: CGRect
    let beginDraw: (Double) -> Bool
    let updateDraw: (Double) -> Void
    let endDraw: (Double, Double) -> Void
    let cancelDraw: () -> Void

    func makeNSView(context: Context) -> TimelineInputView { TimelineInputView() }

    func updateNSView(_ view: TimelineInputView, context: Context) {
        view.scroll = scroll
        view.zoom = zoom
        view.endZoom = endZoom
        view.resetZoom = resetZoom
        view.drawingBounds = drawingBounds
        view.beginDraw = beginDraw
        view.updateDraw = updateDraw
        view.endDraw = endDraw
        view.cancelDraw = cancelDraw
    }

    static func dismantleNSView(_ view: TimelineInputView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class TimelineInputView: NSView {
    var scroll: (Double, Double) -> Void = { _, _ in }
    var zoom: (Double, Double) -> Void = { _, _ in }
    var endZoom: () -> Void = {}
    var resetZoom: () -> Void = {}
    var drawingBounds: CGRect = .zero
    var beginDraw: (Double) -> Bool = { _ in false }
    var updateDraw: (Double) -> Void = { _ in }
    var endDraw: (Double, Double) -> Void = { _, _ in }
    var cancelDraw: () -> Void = {}
    private var monitor: Any?
    private var magnificationScale: Double = 1
    private var dragOrigin: NSPoint?
    private var isDrawing = false

    override var isFlipped: Bool { true }

    // Leave buttons, entry tooltips, and future drawing gestures to the SwiftUI content.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .smartMagnify,
                                                            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        dragOrigin = nil
        isDrawing = false
    }

    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        if event.type == .keyDown {
            guard event.keyCode == 53, isDrawing else { return false }
            dragOrigin = nil
            isDrawing = false
            cancelDraw()
            return true
        }
        let point = convert(event.locationInWindow, from: nil)
        let fraction = point.x / max(bounds.width, 1)
        if event.type == .leftMouseDown {
            dragOrigin = drawingBounds.contains(point) && !event.modifierFlags.contains(.control) ? point : nil
            return false
        }
        if event.type == .leftMouseDragged, let origin = dragOrigin {
            if !isDrawing {
                guard abs(point.x - origin.x) >= 3 else { return false }
                guard beginDraw(origin.x / max(bounds.width, 1)) else { dragOrigin = nil; return false }
                isDrawing = true
            }
            updateDraw(fraction)
            return true
        }
        if event.type == .leftMouseUp {
            dragOrigin = nil
            guard isDrawing else { return false }
            isDrawing = false
            endDraw(fraction, 3 / max(bounds.width, 1))
            return true
        }
        guard bounds.contains(point) else { return false }
        // Keep the time-to-position mapping fixed for the duration of a drawing gesture.
        if isDrawing { return true }
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
                endZoom()
                magnificationScale = 1
            }
            return true
        default:
            return false
        }
    }
}
