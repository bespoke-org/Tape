import SwiftUI
import LineCore

struct TrackingPopover: View {
    let model: AppModel
    let dismiss: () -> Void
    @State private var taskName = ""
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
            HStack {
                Text("Line").font(.headline)
                Spacer()
                Menu {
                    Button("Quit Line") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Line menu")
            }

            if let store = model.store {
                TimelineView(.periodic(from: .now, by: reduceMotion ? 5 : 1)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        runningControls(store: store, now: context.date)
                        LiveTimeline(store: store, now: context.date)
                    }
                }
                Divider()
                taskPicker(store: store)
            } else {
                ContentUnavailableView("Couldn’t open your time records", systemImage: "externaldrive.badge.exclamationmark")
                Button("Try Again") { model.load() }
            }

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Could not save or load time records. \(message)")
            }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear { isTaskFieldFocused = true }
        .onExitCommand(perform: dismiss)
    }

    @ViewBuilder
    private func runningControls(store: TrackingStore, now: Date) -> some View {
        HStack(spacing: 12) {
            if let task = store.runningTask, let entry = store.runningEntry {
                Circle().fill(task.color.displayColor).frame(width: 10, height: 10).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.name).font(.title3.weight(.medium)).lineLimit(1)
                    Text("Tracking").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(Duration.seconds(entry.duration(at: now)), format: .time(pattern: .hourMinuteSecond))
                    .font(.system(.title3, design: .monospaced)).monospacedDigit()
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(Duration.seconds(entry.duration(at: now)).formatted(.time(pattern: .hourMinuteSecond)))
                Button { _ = model.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.glass)
                .help("Stop tracking this task")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Not tracking").font(.title3.weight(.medium))
                    Text("Choose a task to begin.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .frame(height: 44)
    }

    private func taskPicker(store: TrackingStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Name a task or search…", text: $taskName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTaskFieldFocused)
                    .onSubmit { start(trimmedName) }
                    .accessibilityLabel("Task name or search")
                Button(store.runningTask == nil ? "Start" : "Switch") { start(trimmedName) }
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
                                    if task.id == store.runningTask?.id {
                                        Text("Tracking").font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Image(systemName: "play.fill").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(store.runningTask == nil ? "Start" : "Switch to") \(task.name)")
                        }
                    }
                }
                .frame(height: min(CGFloat(matches.count) * 32, 108))
            } else if !trimmedName.isEmpty {
                Text("A new task will be created.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func start(_ name: String) {
        guard !name.isEmpty else { return }
        if model.start(name) { taskName = "" }
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
