import SwiftUI
import LineCore

struct LiveTimeline: View {
    let store: TrackingStore
    let now: Date
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let span: TimeInterval = 4 * 60 * 60
    private var lower: Date { now.addingTimeInterval(-span / 2) }
    private var upper: Date { now.addingTimeInterval(span / 2) }
    private var visibleEntries: [TimeEntry] {
        store.entries.filter { $0.start < upper && ($0.end ?? now) > lower }
    }
    private var ticks: [Date] {
        let hour = Calendar.current.dateInterval(of: .hour, for: lower)?.start ?? lower
        return (0...9).map { hour.addingTimeInterval(Double($0) * 1_800) }
            .filter { $0 >= lower && $0 <= upper }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.035))
                        .frame(height: 64).offset(y: 28)

                    ForEach(ticks, id: \.self) { date in
                        let x = position(date, width: width)
                        Rectangle().fill(Color.primary.opacity(contrast == .increased ? 0.35 : 0.12))
                            .frame(width: 1, height: 68).offset(x: x, y: 28)
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            .fixedSize()
                            .position(x: min(max(x, 22), width - 22), y: 108)
                            .accessibilityHidden(true)
                    }

                    ForEach(visibleEntries) { entry in
                        if let task = store.task(id: entry.taskID) {
                            let left = max(0, position(entry.start, width: width))
                            let right = min(width, position(entry.end ?? now, width: width))
                            let entryWidth = max(2, right - left)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : task.color.displayColor.opacity(0.23))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(task.color.displayColor, lineWidth: contrast == .increased ? 2 : 1)
                                }
                                .overlay(alignment: .leading) {
                                    if entryWidth > 42 {
                                        Text(task.name).font(.caption.weight(.medium)).lineLimit(1)
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 6)
                                    }
                                }
                                .frame(width: entryWidth, height: 46)
                                .offset(x: left, y: 37)
                                .help(entryDescription(entry, task: task))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(entryDescription(entry, task: task))
                        }
                    }

                    if visibleEntries.isEmpty {
                        Text("Start a task to begin tracking.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(width: width / 2 - 12, height: 64).offset(y: 28)
                    }

                    Rectangle().fill(.primary).frame(width: 1.5, height: 78)
                        .offset(x: width / 2, y: 18)
                    Text("Now").font(.caption2.weight(.semibold))
                        .position(x: width / 2, y: 7)
                        .accessibilityLabel("Now, \(now.formatted(date: .omitted, time: .shortened))")
                }
                .clipped()
            }
            .frame(height: 124)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Timeline, four hours centered on now")
        }
    }

    private func position(_ date: Date, width: CGFloat) -> CGFloat {
        date.timeIntervalSince(lower) / span * width
    }

    private func entryDescription(_ entry: TimeEntry, task: TrackedTask) -> String {
        let start = entry.start.formatted(date: .abbreviated, time: .shortened)
        let end = entry.end?.formatted(date: .abbreviated, time: .shortened) ?? "now, tracking"
        return "\(task.name), \(start) to \(end)"
    }
}
