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
                Button("Cancel", action: model.cancelEntry)
                Button("Save") {
                    _ = model.saveEntry(id: entry.id, taskID: taskID, start: start, end: entry.end == nil ? nil : end)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Save entry")
            }
        }
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
}

private struct TaskSettings: View {
    let model: AppModel
    let task: TrackedTask
    @State private var name: String
    @State private var color: TaskColor
    @State private var expanded = false

    init(model: AppModel, task: TrackedTask) {
        self.model = model
        self.task = task
        _name = State(initialValue: task.name)
        _color = State(initialValue: task.color)
    }

    var body: some View {
        DisclosureGroup("Rename and recolor task", isExpanded: $expanded) {
            HStack {
                TextField("Task name", text: $name)
                    .accessibilityLabel("Reusable task name")
                Picker("Color", selection: $color) {
                    ForEach(TaskColor.allCases, id: \.self) { color in
                        Label {
                            Text(color.rawValue.capitalized)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(color.displayColor)
                        }.tag(color)
                    }
                }
                .frame(width: 145)
                .accessibilityLabel("Task color")
                Button("Save task") {
                    if model.saveTask(id: task.id, name: name, color: color) { expanded = false }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          (name == task.name && color == task.color))
                .help("Apply this name and color to every entry for this task")
            }
            .padding(.top, 6)
        }
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
