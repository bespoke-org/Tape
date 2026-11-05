import SwiftUI
import LineCore

/// Entry corrections stay inline, in the same space as the task picker.
struct EntryEditor: View {
    @Bindable var model: AppModel
    let store: TrackingStore
    let entry: TimeEntry
    @State private var taskName: String
    @State private var isTaskFocused = false
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
        TaskEditorForm(store: store, task: store.task(id: entry.taskID),
                       text: $taskName, isFocused: $isTaskFocused,
                       accessibilityLabel: "Entry task name or search",
                       submit: { chooseTask(taskName) }, cancel: { model.cancelEntry() },
                       selectColor: { _ = model.saveTaskColor(id: entry.taskID, color: $0) }) {
            if entry.recorded.isEmpty, let end = entry.end {
                Button("Reschedule…") {
                    plannedStart = Date(timeIntervalSince1970: ceil(max(entry.start, Date.now.addingTimeInterval(60)).timeIntervalSince1970 / 60) * 60)
                    plannedEnd = plannedStart.addingTimeInterval(end.timeIntervalSince(entry.start))
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
        .alert("Delete this entry?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { _ = model.deleteEntry(id: entry.id) }
        } message: {
            Text(entry.isRunning ? "This will stop tracking and remove the entire entry, including its recorded and scheduled time. This cannot be undone." :
                    "This will remove the entire entry, including any recorded and scheduled time. This cannot be undone.")
        }
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
