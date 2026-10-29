import SwiftUI
import LineCore

struct TrackingPopover: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void
    let openMainWindow: () -> Void
    let contentSizeDidChange: (CGSize) -> Void
    private var taskName: String { model.creationName ?? "" }
    private var isTaskPickerShown: Bool { model.creationName != nil }
    @State private var isTaskFieldFocused = false
    @State private var tagCompletion = TaskTagCompletion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmedName: String { taskName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [TrackedTask] {
        model.store?.taskSuggestions(matching: tagCompletion.query(for: taskName)) ?? []
    }
    private var taskListBottomInset: CGFloat {
        isTaskPickerShown && !matches.isEmpty && model.entryError == nil && model.errorMessage == nil ? 20 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let store = model.store {
                TimelineView(.periodic(from: .now, by: reduceMotion ? 5 : 1)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        runningControls(store: store)
                        LiveTimeline(store: store, now: context.date, model: model)
                    }
                }
                if let id = model.editingEntryID, let entry = store.editableEntry(id: id) {
                    EntryEditor(model: model, store: store, entry: entry)
                        .id(id)
                } else if isTaskPickerShown {
                    taskPicker(store: store)
                        .task {
                            await Task.yield()
                            guard !Task.isCancelled else { return }
                            isTaskFieldFocused = true
                        }
                }
            } else {
                HStack {
                    Spacer()
                    mainWindowButton
                }
                ContentUnavailableView("Couldn’t open your time records", systemImage: "externaldrive.badge.exclamationmark")
                Button("Try Again") { model.load() }
            }

            if let message = model.entryError ?? model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(message)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20 - taskListBottomInset)
        .frame(width: 620)
        // Measure natural height so resizing the popover cannot feed back into this measurement.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            contentSizeDidChange(size)
        }
        .onExitCommand {
            if isTaskPickerShown || model.editingEntryID != nil || model.resizingEntryID != nil || model.isDrawing || model.entryError != nil {
                closeTaskPicker()
            } else {
                dismiss()
            }
        }
        .onChange(of: isTaskPickerShown) { _, shown in
            if !shown { isTaskFieldFocused = false }
        }
        .onDisappear {
            model.stopTimelineAnimation(finish: true)
            model.cancelEntry()
        }
    }

    @ViewBuilder
    private func runningControls(store: TrackingStore) -> some View {
        HStack(spacing: 12) {
            if let task = store.runningTask {
                RunningTaskIndicator(color: task.color.displayColor)
                Text(task.name).font(.title3.weight(.medium)).lineLimit(1)
                Spacer(minLength: 8)
                pickerButton("Switch task", systemImage: "arrow.left.arrow.right")
                Button {
                    if model.finishCreation() { _ = model.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
                .help("Stop tracking this task")
            } else {
                Text("Not tracking").font(.title3.weight(.medium))
                Spacer()
                pickerButton("Start task", systemImage: "play.fill")
            }
            mainWindowButton
        }
        .frame(minHeight: 24)
    }

    private var mainWindowButton: some View {
        Button(action: openMainWindow) {
            Label("Open Tape", systemImage: "gearshape")
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Tape")
        .accessibilityLabel("Open Tape")
    }

    private func pickerButton(_ title: String, systemImage: String) -> some View {
        Button {
            if isTaskPickerShown && model.entrySelection == nil {
                if model.finishCreation() { isTaskFieldFocused = false }
            } else {
                if model.beginCreation() { isTaskFieldFocused = true }
            }
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func closeTaskPicker() {
        model.cancelEntry()
        isTaskFieldFocused = false
    }

    private func taskPicker(store: TrackingStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TaskInputField(text: Binding(get: { taskName }, set: { model.creationName = $0 }),
                               isFocused: $isTaskFieldFocused, tags: store.tags,
                               completion: tagCompletion, accessibilityLabel: "Task name or search",
                               submit: { start(trimmedName) }, cancel: { closeTaskPicker() })
                    .frame(height: 22)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                Button("Cancel", action: closeTaskPicker)
                    .buttonStyle(.glass)
                Button(pickerAction(store: store)) { start(trimmedName) }
                    .buttonStyle(.glassProminent)
                    .disabled(TaskInput(taskName).name.isEmpty)
            }
            if isTaskFieldFocused { TagCompletionList(completion: tagCompletion) }
            if !matches.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(matches) { task in
                            Button { start(TaskInput.text(name: task.name, tags: TaskInput(taskName).tags)) } label: {
                                TaskSuggestionLabel(task: task)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(model.entrySelection != nil ? "Use" : store.runningTask == nil ? "Start" : "Switch to") \(task.name)")
                        }
                    }
                    .padding(.bottom, taskListBottomInset)
                }
                .frame(height: min(CGFloat(matches.count) * 32, 108) + taskListBottomInset)
            }
        }
    }

    private func start(_ name: String) {
        guard !TaskInput(name).name.isEmpty else { return }
        if model.submitCreation(named: name) { isTaskFieldFocused = false }
    }

    private func pickerAction(store: TrackingStore) -> String {
        if let selection = model.entrySelection {
            if selection.overwritesExisting { return selection.end == nil ? "Overwrite & Start" : "Overwrite" }
            if selection.startsInFuture { return "Schedule" }
            if let end = selection.end, end > .now { return "Start" }
            return selection.end == nil ? "Start" : "Save"
        }
        return store.runningTask == nil ? "Start" : "Switch"
    }
}

private struct RunningTaskIndicator: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .background {
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let cycle = context.date.timeIntervalSinceReferenceDate / 2.4
                        ZStack {
                            ForEach(0..<2) { index in
                                let phase = (cycle + Double(index) / 2).truncatingRemainder(dividingBy: 1)
                                Circle()
                                    .fill(color.opacity(0.4 * (1 - phase) * (1 - phase)))
                                    .scaleEffect(1 + 1.4 * phase)
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension TaskColor {
    var displayColor: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: Color(red: 240 / 255, green: 98 / 255, blue: 179 / 255)
        case .purple: .purple
        case .red: .red
        case .yellow: .yellow
        case .brown: .brown
        }
    }
}
