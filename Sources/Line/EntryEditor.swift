import SwiftUI
import LineCore

/// Entry corrections stay inline, in the same space as the task picker.
struct EntryEditor: View {
    @Bindable var model: AppModel
    let store: TrackingStore
    let entry: TimeEntry
    @State private var taskName: String
    @State private var isTaskFocused = false
    @State private var tagCompletion = TaskTagCompletion()
    @State private var confirmsDeletion = false
    @State private var showsReschedule = false
    @State private var plannedStart = Date.now
    @State private var plannedEnd = Date.now

    init(model: AppModel, store: TrackingStore, entry: TimeEntry) {
        self.model = model
        self.store = store
        self.entry = entry
        _taskName = State(initialValue: store.task(id: entry.taskID)?.inputText ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let task = store.task(id: entry.taskID) {
                    TaskColorPicker(model: model, task: task)
                        .accessibilityLabel("Task color")
                }
                TaskInputField(text: $taskName, isFocused: $isTaskFocused, tags: store.tags,
                               completion: tagCompletion, accessibilityLabel: "Entry task name or search",
                               submit: { chooseTask(taskName) }, cancel: { model.cancelEntry() })
                    .frame(height: 22)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .overlay {
                        Capsule()
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                if let plan = store.plans.first(where: { $0.id == entry.id }) {
                    Button("Reschedule…") {
                        plannedStart = Date(timeIntervalSince1970: ceil(max(plan.start, Date.now.addingTimeInterval(60)).timeIntervalSince1970 / 60) * 60)
                        plannedEnd = plannedStart.addingTimeInterval(plan.end.timeIntervalSince(plan.start))
                        showsReschedule = true
                    }
                    .buttonStyle(.borderless)
                    .frame(height: 28)
                    .popover(isPresented: $showsReschedule) {
                        VStack(alignment: .leading, spacing: 12) {
                            DatePicker("Start", selection: $plannedStart, displayedComponents: [.date, .hourAndMinute])
                            DatePicker("End", selection: $plannedEnd, displayedComponents: [.date, .hourAndMinute])
                            if let error = model.entryError {
                                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                            }
                            HStack {
                                Spacer()
                                Button("Cancel") { showsReschedule = false }
                                Button("Reschedule") {
                                    if model.reschedulePlan(id: entry.id, start: plannedStart, end: plannedEnd) {
                                        showsReschedule = false
                                    }
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                        .padding().frame(width: 310)
                    }
                }
                Button { confirmsDeletion = true } label: {
                    Label("Delete entry", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .help("Delete entry")
                .accessibilityLabel("Delete entry")
            }
            .controlSize(.large)
            if isTaskFocused { TagCompletionList(completion: tagCompletion) }
            if isTaskFocused && !matches.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(matches) { task in
                            Button {
                                taskName = task.inputText
                                isTaskFocused = true
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
        .onChange(of: store.task(id: entry.taskID)?.inputText) { _, text in
            if !isTaskFocused { taskName = text ?? "" }
        }
        .alert("Delete this entry?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { _ = model.deleteEntry(id: entry.id) }
        } message: {
            Text(store.plans.contains(where: { $0.id == entry.id }) ? "This will cancel the plan and keep any time already recorded." : entry.end == nil ? "This will stop tracking and remove this entry. This cannot be undone." :
                    "This will remove the recorded time. This cannot be undone.")
        }
    }

    private var matches: [TrackedTask] {
        store.taskSuggestions(matching: tagCompletion.query(for: taskName))
    }

    private func chooseTask(_ name: String) {
        guard !TaskInput(name).name.isEmpty else { return }
        if model.reassignEntry(id: entry.id, taskName: name) {
            taskName = store.editableEntry(id: entry.id)
                .flatMap { store.task(id: $0.taskID)?.inputText } ?? name
            isTaskFocused = false
        }
    }
}

private struct TaskColorPicker: NSViewRepresentable {
    let model: AppModel
    let task: TrackedTask

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
        context.coordinator.onSelect = { color in
            _ = model.saveTaskColor(id: task.id, color: color)
        }
        button.menu?.items.first?.image = colorSwatch(task.color, diameter: 15)
        for item in button.menu?.items.dropFirst() ?? [] {
            item.state = item.representedObject as? String == task.color.rawValue ? .on : .off
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
