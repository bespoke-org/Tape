import SwiftUI
import LineCore

struct CalendarEntryEditor: View {
    @Bindable var model: AppModel
    let store: TrackingStore
    let entry: TimeEntry
    let occurrence: CalendarOccurrence
    @State private var input: String
    @State private var focused = false
    @State private var chooseScope = false
    @State private var confirmsDeletion = false

    init(model: AppModel, store: TrackingStore, entry: TimeEntry, occurrence: CalendarOccurrence) {
        self.model = model; self.store = store; self.entry = entry; self.occurrence = occurrence
        _input = State(initialValue: store.task(id: entry.taskID)?.inputText ?? occurrence.event.title)
    }

    var body: some View {
        TaskEditorForm(store: store, task: store.task(id: entry.taskID),
                       text: $input, isFocused: $focused,
                       accessibilityLabel: "Calendar event task",
                       submit: { assign() }, cancel: { model.cancelEntry() },
                       selectColor: { _ = model.saveCalendarColor(id: entry.id, color: $0) }) {
            if occurrence.event.seriesKey != nil {
                Menu("Skip") {
                    Button("This occurrence") { model.skipCalendar(id: entry.id, scope: .occurrence) }
                    Button("Entire series") { model.skipCalendar(id: entry.id, scope: .series) }
                }.menuStyle(.borderlessButton).fixedSize()
            } else {
                Button("Skip") { model.skipCalendar(id: entry.id, scope: .occurrence) }.buttonStyle(.borderless)
            }
            if !entry.recorded.isEmpty {
                Button { confirmsDeletion = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete recorded entry").accessibilityLabel("Delete recorded entry")
            }
        }
        .confirmationDialog("Apply this task to which events?", isPresented: $chooseScope) {
            Button("This occurrence") { save(scope: .occurrence) }
            Button("Entire series") { save(scope: .series) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete this recorded entry?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { _ = model.deleteEntry(id: entry.id) }
        } message: { Text("This removes recorded time and hides this occurrence from Tape. The calendar event will not change.") }
    }

    private func assign() {
        guard !TaskInput(input).name.isEmpty else { return }
        if occurrence.event.seriesKey != nil && input != (store.task(id: entry.taskID)?.inputText ?? occurrence.event.title) {
            chooseScope = true
        } else { save(scope: .occurrence) }
    }

    private func save(scope: CalendarScope) {
        guard model.assignCalendarTask(id: entry.id, input: input, scope: scope) else { return }
        focused = false
    }
}
