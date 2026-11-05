import AppKit
import LineCore

@MainActor
final class CalendarConflictPanel: NSPanel {
    private var actions: [UUID: () -> Void] = [:]
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(entries: [TimeEntry], store: TrackingStore, choose: @escaping (UUID) -> Void, skip: @escaping () -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 350, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        hasShadow = true; hidesOnDeactivate = false; level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let title = NSTextField(labelWithString: "Which event would you like to track?")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let stack = NSStackView(views: [title])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        for entry in entries {
            let task = store.task(id: entry.taskID)
            let time = store.timeFormat.string(from: entry.start)
            let button = NSButton(title: "\(task?.name ?? "Event") · \(time)", target: self, action: #selector(clicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(entry.id.uuidString)
            button.bezelStyle = .push
            button.lineBreakMode = .byTruncatingTail
            button.toolTip = button.title
            actions[entry.id] = { choose(entry.id) }
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
        }
        let skipID = UUID()
        let skipButton = NSButton(title: "Skip these events", target: self, action: #selector(clicked(_:)))
        skipButton.identifier = NSUserInterfaceItemIdentifier(skipID.uuidString)
        skipButton.bezelStyle = .push
        actions[skipID] = skip
        stack.addArrangedSubview(skipButton)
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        container.setFrameSize(NSSize(width: 350, height: stack.fittingSize.height + 24))
        scroll.documentView = container
        let glass = NSGlassEffectView()
        glass.cornerRadius = 16; glass.contentView = scroll; contentView = glass
        setContentSize(NSSize(width: 350, height: min(320, stack.fittingSize.height + 24)))
    }

    @objc private func clicked(_ button: NSButton) {
        if let value = button.identifier?.rawValue, let id = UUID(uuidString: value) { actions[id]?() }
    }

    func show(below button: NSStatusBarButton, avoiding other: NSRect?) {
        guard let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        setFrameOrigin(NSPoint(x: min(max(anchor.midX - frame.width / 2, visible.minX), visible.maxX - frame.width),
                               y: max(visible.minY, min(anchor.minY, other?.minY ?? anchor.minY) - frame.height - 8)))
        orderFrontRegardless()
    }
}
