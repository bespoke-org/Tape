import SwiftUI
import LineCore

struct TrackingPopover: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void
    let contentSizeDidChange: (CGSize) -> Void
    @State private var taskName = ""
    @State private var isTaskPickerShown = false
    @FocusState private var isTaskFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmedName: String { taskName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [TrackedTask] {
        (model.store?.tasks ?? []).filter {
            trimmedName.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmedName)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
                if isTaskPickerShown {
                    taskPicker(store: store)
                        .task {
                            await Task.yield()
                            guard !Task.isCancelled else { return }
                            isTaskFieldFocused = true
                        }
                }
            } else {
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
        .padding(20)
        .frame(width: 620)
        // Measure natural height so resizing the popover cannot feed back into this measurement.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            contentSizeDidChange(size)
        }
        .onExitCommand {
            if isTaskPickerShown || model.isDrawing || model.entryError != nil {
                closeTaskPicker()
            } else {
                dismiss()
            }
        }
        .onChange(of: model.isDrawing) { _, drawing in
            if drawing {
                isTaskPickerShown = false
                isTaskFieldFocused = false
                taskName = ""
            }
        }
        .onChange(of: model.entrySelection) { _, selection in
            if selection != nil {
                taskName = ""
                isTaskPickerShown = true
            }
        }
        .onDisappear {
            model.saveTimelineScale()
            model.cancelEntry()
        }
    }

    @ViewBuilder
    private func runningControls(store: TrackingStore) -> some View {
        HStack(spacing: 12) {
            if let task = store.runningTask {
                Circle().fill(task.color.displayColor).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(task.name).font(.title3.weight(.medium)).lineLimit(1)
                Spacer(minLength: 8)
                pickerButton("Switch task", systemImage: "arrow.left.arrow.right")
                Button { _ = model.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.glass)
                .help("Stop tracking this task")
            } else {
                Text("Not tracking").font(.title3.weight(.medium))
                Spacer()
                pickerButton("Start task")
            }
        }
        .frame(minHeight: 24)
    }

    private func pickerButton(_ title: String, systemImage: String? = nil) -> some View {
        Button {
            if isTaskPickerShown && model.entrySelection == nil {
                closeTaskPicker()
            } else {
                model.cancelEntry()
                taskName = ""
                isTaskPickerShown = true
                isTaskFieldFocused = true
            }
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.glass)
    }

    private func closeTaskPicker() {
        model.cancelEntry()
        isTaskFieldFocused = false
        isTaskPickerShown = false
        taskName = ""
    }

    private func taskPicker(store: TrackingStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selection = model.entrySelection {
                HStack {
                    Text(selectionDescription(selection))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: closeTaskPicker).buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Name a task or search…", text: $taskName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTaskFieldFocused)
                    .onSubmit { start(trimmedName) }
                    .accessibilityLabel("Task name or search")
                Button(pickerAction(store: store)) { start(trimmedName) }
                    .buttonStyle(.glassProminent)
                    .disabled(trimmedName.isEmpty)
            }
            if !matches.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(matches) { task in
                            Button { start(task.name) } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(task.color.displayColor).frame(width: 8, height: 8)
                                    Text(task.name).lineLimit(1)
                                    Spacer()
                                    if model.entrySelection != nil || task.id != store.runningTask?.id {
                                        Image(systemName: model.entrySelection?.end != nil ? "checkmark" : "play.fill")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(model.entrySelection != nil ? "Use" : store.runningTask == nil ? "Start" : "Switch to") \(task.name)")
                        }
                    }
                }
                .frame(height: min(CGFloat(matches.count) * 32, 108))
            }
        }
    }

    private func start(_ name: String) {
        guard !name.isEmpty else { return }
        let saved = model.entrySelection != nil ? model.createSelectedEntry(named: name) : model.start(name)
        if saved { closeTaskPicker() }
    }

    private func pickerAction(store: TrackingStore) -> String {
        if let selection = model.entrySelection { return selection.end == nil ? "Start" : "Save" }
        return store.runningTask == nil ? "Start" : "Switch"
    }

    private func selectionDescription(_ selection: EntrySelection) -> String {
        let start = selection.start.formatted(date: .abbreviated, time: .shortened)
        if let end = selection.end {
            return "\(start) – \(end.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(start) – Now · starts tracking"
    }
}

extension TaskColor {
    var displayColor: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .indigo: .indigo
        }
    }
}
