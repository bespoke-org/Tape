import SwiftUI
import LineCore

/// Entry corrections stay inline, in the same space as the task picker.
struct EntryEditor: View {
    @Bindable var model: AppModel
    let store: TrackingStore
    let entry: TimeEntry
    @State private var taskID: UUID
    @State private var start: Date
    @State private var end: Date
    @State private var confirmsDeletion = false

    init(model: AppModel, store: TrackingStore, entry: TimeEntry) {
        self.model = model
        self.store = store
        self.entry = entry
        _taskID = State(initialValue: entry.taskID)
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end ?? .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.bottom, 4)
            Picker("Task", selection: $taskID) {
                ForEach(store.tasks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { task in
                    Text(task.name).tag(task.id)
                }
            }
            .accessibilityLabel("Entry task")

            HStack(alignment: .top, spacing: 16) {
                TimestampField(title: "Start", date: $start)
                if entry.end != nil {
                    TimestampField(title: "End", date: $end)
                } else {
                    Spacer()
                    Button("Stop tracking") { _ = model.stop() }
                        .help("Stop this entry before setting its end time")
                }
            }
            if let task = store.task(id: taskID) {
                TaskSettings(model: model, task: task)
                    .id(task.id)
            }
            HStack {
                Button { confirmsDeletion = true } label: {
                    Label("Delete entry", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete entry")
                .accessibilityLabel("Delete entry")
                Spacer()
            }
        }
        .onChange(of: taskID) { saveChanges() }
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

    private func saveChanges() {
        let editedEnd = entry.end == nil ? nil : end
        guard taskID != entry.taskID || start != entry.start || editedEnd != entry.end else {
            model.clearEntryError()
            return
        }
        _ = model.saveEntry(id: entry.id, taskID: taskID, start: start, end: editedEnd)
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
        DisclosureGroup("Rename and recolor task", isExpanded: $expanded) {
            HStack {
                TextField("Task name", text: $name)
                    .accessibilityLabel("Reusable task name")
                    .focused($isNameFocused)
                    .onSubmit(saveName)
                    .onChange(of: isNameFocused) { _, focused in
                        if !focused { saveName() }
                    }
                Picker("Color", selection: Binding(get: { task.color }, set: {
                    guard let current = model.store?.task(id: task.id) else { return }
                    _ = model.saveTask(id: task.id, name: current.name, color: $0)
                })) {
                    ForEach(TaskColor.allCases, id: \.self) { color in
                        Label {
                            Text(color.rawValue.capitalized)
                        } icon: {
                            colorSwatch(color)
                        }.tag(color)
                    }
                }
                .frame(width: 145)
                .accessibilityLabel("Task color")
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
            DatePicker(title, selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
                .accessibilityLabel("Entry \(title.lowercased())")
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
