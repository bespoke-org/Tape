import SwiftUI
import LineCore

/// Entry corrections stay inline, in the same space as the task picker.
struct EntryEditor: View {
    @Bindable var model: AppModel
    let store: TrackingStore
    let entry: TimeEntry
    @State private var taskName: String
    @FocusState private var isTaskFocused: Bool
    @State private var confirmsDeletion = false

    init(model: AppModel, store: TrackingStore, entry: TimeEntry) {
        self.model = model
        self.store = store
        self.entry = entry
        _taskName = State(initialValue: store.task(id: entry.taskID)?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let task = store.task(id: entry.taskID) {
                    TaskColorPicker(model: model, task: task)
                }
                TextField("Name a new task", text: $taskName)
                    .textFieldStyle(.plain)
                    .focused($isTaskFocused)
                    .onSubmit { chooseTask(taskName) }
                    .accessibilityLabel("Entry task name or search")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                Button { confirmsDeletion = true } label: {
                    Label("Delete entry", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete entry")
                .accessibilityLabel("Delete entry")
            }
            if isTaskFocused && !matches.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(matches) { task in
                            Button { chooseTask(task.name) } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(task.color.displayColor).frame(width: 8, height: 8)
                                    Text(task.name).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Use \(task.name)")
                        }
                    }
                }
                .frame(height: min(CGFloat(matches.count) * 32, 108))
            }
        }
        .onChange(of: store.task(id: entry.taskID)?.name) { _, name in
            if !isTaskFocused { taskName = name ?? "" }
        }
        .onChange(of: isTaskFocused) { _, focused in
            if !focused { taskName = store.task(id: entry.taskID)?.name ?? "" }
        }
        .alert("Delete this entry?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { _ = model.deleteEntry(id: entry.id) }
        } message: {
            Text(entry.end == nil ? "This will stop tracking and remove this entry. This cannot be undone." :
                    "This will remove the recorded time. This cannot be undone.")
        }
    }

    private var matches: [TrackedTask] {
        let query = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.tasks.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseTask(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if model.reassignEntry(id: entry.id, taskName: name) {
            taskName = store.entries.first(where: { $0.id == entry.id })
                .flatMap { store.task(id: $0.taskID)?.name } ?? name
            isTaskFocused = false
        }
    }
}

private struct TaskColorPicker: View {
    let model: AppModel
    let task: TrackedTask

    var body: some View {
        Picker("", selection: Binding(get: { task.color }, set: {
            _ = model.saveTaskColor(id: task.id, color: $0)
        })) {
            ForEach(TaskColor.allCases, id: \.self) { color in
                colorSwatch(color)
                    .accessibilityLabel(color.rawValue.capitalized)
                    .tag(color)
            }
        }
        .labelsHidden()
        .menuIndicator(.hidden)
        .frame(width: 28)
        .help("Task color")
        .accessibilityLabel("Task color")
    }

    private func colorSwatch(_ color: TaskColor) -> Image {
        let fill = NSColor(color.displayColor)
        // Native menus tint template symbols, discarding SwiftUI foreground styles.
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image).renderingMode(.original)
    }
}
