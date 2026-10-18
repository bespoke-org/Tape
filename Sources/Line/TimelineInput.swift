import AppKit
import SwiftUI

/// Native scroll and pinch delivery, confined to the timeline and its window.
struct TimelineInput: NSViewRepresentable {
    let scroll: (Double, Double) -> Void
    let zoom: (Double, Double) -> Void
    let endZoom: () -> Void

    func makeNSView(context: Context) -> TimelineInputView { TimelineInputView() }

    func updateNSView(_ view: TimelineInputView, context: Context) {
        view.scroll = scroll
        view.zoom = zoom
        view.endZoom = endZoom
    }

    static func dismantleNSView(_ view: TimelineInputView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class TimelineInputView: NSView {
    var scroll: (Double, Double) -> Void = { _, _ in }
    var zoom: (Double, Double) -> Void = { _, _ in }
    var endZoom: () -> Void = {}
    private var monitor: Any?
    private var magnificationScale: Double = 1

    // Leave buttons, entry tooltips, and future drawing gestures to the SwiftUI content.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
        switch event.type {
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
