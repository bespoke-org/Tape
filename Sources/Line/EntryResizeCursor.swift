import AppKit
import LineCore

/// The bracket sits on the selected edge; the arrows sit inside its entry.
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
        let image = NSImage(size: NSSize(width: 30, height: 28), flipped: true) { _ in
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: mirrored ? 30 - x : x, y: y)
            }
            let path = NSBezierPath()
            path.move(to: point(9, 5))
            path.line(to: point(5, 5))
            path.line(to: point(5, 23))
            path.line(to: point(9, 23))
            path.move(to: point(12, 14))
            path.line(to: point(25, 14))
            path.move(to: point(15, 11))
            path.line(to: point(12, 14))
            path.line(to: point(15, 17))
            path.move(to: point(22, 11))
            path.line(to: point(25, 14))
            path.line(to: point(22, 17))
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
        return NSCursor(image: image, hotSpot: NSPoint(x: mirrored ? 25 : 5, y: 14))
    }
}
