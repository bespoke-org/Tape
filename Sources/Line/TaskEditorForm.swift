import SwiftUI
import LineCore

/// Shared task controls. Each entry editor supplies its own actions and save behavior.
struct TaskEditorForm<Actions: View>: View {
    let store: TrackingStore
    let task: TrackedTask?
    @Binding var text: String
    @Binding var isFocused: Bool
    let accessibilityLabel: String
    let submit: () -> Void
    let cancel: () -> Void
    let selectColor: (TaskColor) -> Void
    @ViewBuilder let actions: Actions
    @State private var completion = TaskTagCompletion()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let task {
                    TaskColorPicker(color: task.color, onSelect: selectColor)
                        .accessibilityLabel("Task color")
                }
                TaskInputField(text: $text, isFocused: $isFocused, tags: store.tags,
                               completion: completion, accessibilityLabel: accessibilityLabel,
                               submit: submit, cancel: cancel)
                    .frame(height: 22)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .overlay {
                        Capsule().strokeBorder(.quaternary, lineWidth: 0.5).allowsHitTesting(false)
                    }
                actions
            }
            .controlSize(.large)
            if isFocused {
                TagCompletionList(completion: completion)
                if !matches.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(matches) { task in
                                Button {
                                    text = task.inputText
                                    isFocused = true
                                } label: {
                                    TaskSuggestionLabel(task: task)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Use \(task.name)")
                            }
                        }
                    }
                    .frame(height: min(CGFloat(matches.count) * 32, 108))
                }
            }
        }
        .onChange(of: task?.inputText) { _, value in
            if !isFocused { text = value ?? "" }
        }
    }

    private var matches: [TrackedTask] {
        store.taskSuggestions(matching: completion.query(for: text))
    }
}

private struct TaskColorPicker: NSViewRepresentable {
    let color: TaskColor
    let onSelect: (TaskColor) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.cell = ColorMenuCell(textCell: "", pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("Task color")
        button.toolTip = "Task color"
        if let cell = button.cell as? NSPopUpButtonCell {
            cell.arrowPosition = .noArrow
        }
        let menu = NSMenu()
        // Pull-down menus reserve the first item for the closed button's image.
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        for color in TaskColor.allCases {
            let item = NSMenuItem(title: "", action: #selector(Coordinator.selectColor(_:)), keyEquivalent: "")
            item.image = colorSwatch(color, diameter: 10)
            item.representedObject = color.rawValue
            item.setAccessibilityLabel(color.rawValue.capitalized)
            item.target = context.coordinator
            menu.addItem(item)
        }
        button.menu = menu
        button.selectItem(at: 0)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        button.menu?.items.first?.image = colorSwatch(color, diameter: 15)
        for item in button.menu?.items.dropFirst() ?? [] {
            item.state = item.representedObject as? String == color.rawValue ? .on : .off
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: 28, height: 28)
    }

    private func colorSwatch(_ color: TaskColor, diameter: CGFloat) -> NSImage {
        let fill = NSColor(color.displayColor)
        let size = diameter + 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (TaskColor) -> Void = { _ in }

        @objc func selectColor(_ sender: NSMenuItem) {
            guard let value = sender.representedObject as? String, let color = TaskColor(rawValue: value) else { return }
            onSelect(color)
        }
    }
}

private final class ColorMenuCell: NSPopUpButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        // Keep native menu interaction, but draw the swatch without the pressed-state tint.
        let highlighted = isHighlighted
        isHighlighted = false
        defer { isHighlighted = highlighted }
        super.draw(withFrame: cellFrame, in: controlView)
    }
}
