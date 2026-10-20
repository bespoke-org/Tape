import AppKit
import SwiftUI
import LineCore

struct ContinuationContent: View {
    let interruptions: TrackingInterruption
    let reject: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let pending = interruptions.pendingContinuation {
                HStack(spacing: 12) {
                    Circle().fill(pending.task.color.displayColor)
                        .frame(width: 10, height: 10).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-continuing \(pending.task.name)")
                            .font(.callout.weight(.medium)).lineLimit(2)
                        Text("In \(interruptions.remainingSeconds) seconds")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Button("Reject", action: reject)
                        .buttonStyle(.glass)
                        .help("Leave this time untracked")
                        .accessibilityLabel("Reject continuation")
                }
            }
        }
    }
}

/// A mouse-interactive panel that never takes keyboard focus from the user's app.
@MainActor
final class ContinuationPanel: NSPanel {
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private let countdown = NSTextField(labelWithString: "")
    private let reject: () -> Void

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(task: TrackedTask, remainingSeconds: Int, reject: @escaping () -> Void) {
        self.reject = reject
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 76), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let title = NSTextField(labelWithString: "Auto-continuing \(task.name)")
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
        labels.spacing = 4
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(task.color.displayColor).cgColor
        dot.layer?.cornerRadius = 5
        dot.setAccessibilityElement(false)
        let button = NSButton(title: "Reject", target: self, action: #selector(rejectClicked))
        button.bezelStyle = .glass
        button.toolTip = "Leave this time untracked"
        let row = NSStackView(views: [dot, labels, button])
        row.alignment = .centerY
        row.spacing = 12
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
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    @objc private func rejectClicked() { reject() }

    func updateCountdown(seconds: Int) {
        countdown.stringValue = "In \(seconds) seconds"
    }

    func show(below button: NSStatusBarButton) {
        guard let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let x = min(max(anchor.midX - frame.width / 2, visible.minX), visible.maxX - frame.width)
        let y = max(visible.minY, anchor.minY - frame.height - 8)
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if let self, event.window !== self { self.dismiss() }
            return event
        }
    }

    func dismiss() {
        orderOut(nil)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil
        localClickMonitor = nil
    }
}

