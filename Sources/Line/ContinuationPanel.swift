import AppKit
import SwiftUI
import LineCore

/// A mouse-interactive panel that never takes keyboard focus from the user's app.
@MainActor
final class ContinuationPanel: NSPanel {
    private let countdown = NSTextField(labelWithString: "")
    private let reject: () -> Void
    private let accept: () -> Void
    private let hoverChanged: (Bool) -> Void
    private weak var anchorButton: NSStatusBarButton?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(task: TrackedTask, remainingSeconds: Int, hoverChanged: @escaping (Bool) -> Void,
         accept: @escaping () -> Void, reject: @escaping () -> Void) {
        self.reject = reject
        self.accept = accept
        self.hoverChanged = hoverChanged
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let title = NSTextField(labelWithString: task.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = title.stringValue
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countdown.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countdown.textColor = .secondaryLabelColor
        updateCountdown(seconds: remainingSeconds)
        let labels = NSStackView(views: [title, countdown])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(task.color.displayColor).cgColor
        dot.layer?.cornerRadius = 5
        dot.setAccessibilityElement(false)
        let button = NSButton(title: "Reject", target: self, action: #selector(rejectClicked))
        // Glass button labels dim in a non-key panel; the standard push style stays legible.
        button.bezelStyle = .push
        button.tintProminence = .primary
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.toolTip = "Leave this time untracked"
        let acceptButton = NSButton(title: "OK", target: self, action: #selector(acceptClicked))
        acceptButton.bezelStyle = .push
        acceptButton.tintProminence = .primary
        acceptButton.font = .systemFont(ofSize: 13, weight: .medium)
        acceptButton.toolTip = "Resume this task now"
        let row = NSStackView(views: [dot, labels, button, acceptButton])
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let glass = NSGlassEffectView(frame: frame)
        glass.cornerRadius = 16
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        glass.contentView = container
        container.addSubview(row)
        contentView = glass
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        let textWidth = max(title.fittingSize.width, countdown.fittingSize.width)
        let contentWidth = 24 + 10 + row.spacing * 3 + textWidth + button.fittingSize.width + acceptButton.fittingSize.width
        setContentSize(NSSize(width: min(320, ceil(contentWidth)), height: 60))
        container.addTrackingArea(NSTrackingArea(rect: .zero,
                                                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                owner: self, userInfo: nil))
    }

    @objc private func rejectClicked() { reject() }
    @objc private func acceptClicked() { accept() }
    override func mouseEntered(with event: NSEvent) { hoverChanged(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged(false) }

    func updateCountdown(seconds: Int) {
        countdown.stringValue = "Auto-continuing in \(seconds) seconds"
    }

    func show(below button: NSStatusBarButton) {
        guard let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let x = min(max(anchor.midX - frame.width / 2, visible.minX), visible.maxX - frame.width)
        let y = max(visible.minY, anchor.minY - frame.height - 8)
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
        anchorButton = button
        button.highlight(true)
        hoverChanged(frame.contains(NSEvent.mouseLocation))
    }

    func dismiss() {
        anchorButton?.highlight(false)
        anchorButton = nil
        orderOut(nil)
    }
}
