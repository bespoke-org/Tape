import AppKit
import LineCore

/// A single bracket marks the selected edge and opens toward its entry.
@MainActor
enum EntryResizeCursor {
    static let start = make(mirrored: false)
    static let end = make(mirrored: true)

    static func cursor(for edge: EntryEdge) -> NSCursor {
        switch edge {
        case .start: start
        case .end: end
        }
    }

    private static func make(mirrored: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 12, height: 26), flipped: true) { _ in
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: mirrored ? 12 - x : x, y: y)
            }
            let path = NSBezierPath()
            path.move(to: point(9, 4))
            path.line(to: point(3, 4))
            path.line(to: point(3, 22))
            path.line(to: point(9, 22))
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // Match the outlined system pointer's contrast on light and dark surfaces.
            NSColor.white.setStroke()
            path.lineWidth = 3.5
            path.stroke()
            NSColor.black.setStroke()
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
        image.isTemplate = false
        return NSCursor(image: image, hotSpot: NSPoint(x: mirrored ? 9 : 3, y: 13))
    }
}
