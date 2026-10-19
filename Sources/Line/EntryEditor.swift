import SwiftUI
import LineCore

/// Entry corrections stay inline, in the same space as the task picker.
struct EntryEditor: View {
    @Bindable var model: AppModel
    let store: TrackingStore
    let entry: TimeEntry
    @State private var taskName: String
    @FocusState private var isTaskFocused: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var confirmsDeletion = false

    init(model: AppModel, store: TrackingStore, entry: TimeEntry) {
        self.model = model
        self.store = store
        self.entry = entry
        _taskName = State(initialValue: store.task(id: entry.taskID)?.name ?? "")
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end ?? .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.bottom, 4)
            HStack(alignment: .top, spacing: 16) {
                TimestampField(title: "Start", date: $start)
                if entry.end != nil {
                    TimestampField(title: "End", date: $end)
                }
                Spacer(minLength: 0)
                Button { confirmsDeletion = true } label: {
                    Label("Delete entry", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete entry")
                .accessibilityLabel("Delete entry")
            }
            HStack(spacing: 8) {
                if let task = store.task(id: entry.taskID) {
                    TaskColorPicker(model: model, task: task)
                }
                TextField("Name a task or search…", text: $taskName)
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
            if let task = store.task(id: entry.taskID) {
                TaskSettings(model: model, task: task).id(task.id)
            }
        }
        .onChange(of: store.task(id: entry.taskID)?.name) { _, name in
            if !isTaskFocused { taskName = name ?? "" }
        }
        .onChange(of: isTaskFocused) { _, focused in
            if !focused { taskName = store.task(id: entry.taskID)?.name ?? "" }
        }
        .onChange(of: start) { saveChanges() }
        .onChange(of: end) { saveChanges() }
        .onChange(of: entry.end) { _, value in
            if let value { end = value }
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

    private func saveChanges() {
        let editedEnd = entry.end == nil ? nil : end
        guard start != entry.start || editedEnd != entry.end else {
            model.clearEntryError()
            return
        }
        _ = model.saveEntry(id: entry.id, taskID: entry.taskID, start: start, end: editedEnd)
    }
}

private struct TaskSettings: View {
    let model: AppModel
    let task: TrackedTask
    @State private var name: String
    @FocusState private var isNameFocused: Bool
    @State private var expanded = false

    init(model: AppModel, task: TrackedTask) {
        self.model = model
        self.task = task
        _name = State(initialValue: task.name)
    }

    var body: some View {
        DisclosureGroup("Rename task", isExpanded: $expanded) {
            TextField("Task name", text: $name)
                .textFieldStyle(.plain)
                .accessibilityLabel("Reusable task name")
                .focused($isNameFocused)
                .onSubmit(saveName)
                .onChange(of: isNameFocused) { _, focused in
                    if !focused { saveName() }
                }
                .padding(.top, 6)
        }
        .onDisappear(perform: saveName)
    }

    private func saveName() {
        guard let current = model.store?.task(id: task.id) else { return }
        guard name != current.name else {
            model.clearEntryError()
            return
        }
        _ = model.saveTask(id: task.id, name: name, color: current.color)
    }
}

private struct TaskColorPicker: View {
    let model: AppModel
    let task: TrackedTask

    var body: some View {
        Picker("", selection: Binding(get: { task.color }, set: {
            guard let current = model.store?.task(id: task.id) else { return }
            _ = model.saveTask(id: task.id, name: current.name, color: $0)
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

/// During a repeated local hour, expose both absolute instants with their UTC offsets.
private struct TimestampField: View {
    let title: String
    @Binding var date: Date
    @Environment(\.calendar) private var calendar

    private var repeatedInstants: [Date] {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let beforeDay = calendar.startOfDay(for: date).addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: beforeDay, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: beforeDay, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last),
              first != last, calendar.isDate(first, inSameDayAs: date), calendar.isDate(last, inSameDayAs: date) else { return [] }
        let fraction = date.timeIntervalSince1970 - floor(date.timeIntervalSince1970)
        return [first.addingTimeInterval(fraction), last.addingTimeInterval(fraction)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                TransparentDatePicker(date: $date, label: "Entry \(title.lowercased())")
                    .fixedSize()
            }
            if !repeatedInstants.isEmpty {
                Picker("UTC offset", selection: $date) {
                    ForEach(repeatedInstants, id: \.self) { instant in
                        Text(offsetLabel(instant)).tag(instant)
                    }
                }
                .accessibilityLabel("\(title) repeated hour")
            }
        }
    }

    private func offsetLabel(_ instant: Date) -> String {
        let seconds = calendar.timeZone.secondsFromGMT(for: instant)
        return String(format: "UTC%@%02d:%02d", seconds < 0 ? "−" : "+", abs(seconds) / 3_600, abs(seconds) % 3_600 / 60)
    }
}

/// Keep native date editing while letting the popover material show through.
private struct TransparentDatePicker: NSViewRepresentable {
    @Binding var date: Date
    let label: String
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.presentsCalendarOverlay = true
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        picker.calendar = calendar
        picker.timeZone = timeZone
        picker.locale = locale
        picker.isEnabled = isEnabled
        picker.setAccessibilityLabel(label)
        if picker.dateValue != date { picker.dateValue = date }
    }

    @MainActor
    final class Coordinator: NSObject {
        var date: Binding<Date>

        init(date: Binding<Date>) { self.date = date }

        @objc func dateChanged(_ sender: NSDatePicker) {
            date.wrappedValue = sender.dateValue
        }
    }
}
