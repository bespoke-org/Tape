import SwiftUI
import LineCore

struct LiveTimeline: View {
    let store: TrackingStore
    let now: Date
    @Binding var viewport: TimelineViewport
    let saveZoom: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let stripTop: CGFloat = 28
    private let stripHeight: CGFloat = 64
    private let nowOverhang: CGFloat = 10
    private var visibleRange: DateInterval { viewport.range(at: now) }
    private var visibleEntries: ArraySlice<TimeEntry> {
        store.entries(overlapping: visibleRange, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let ticks = viewport.ticks(at: now, width: width)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.035))
                        .frame(height: stripHeight)
                        .overlay(alignment: .topLeading) {
                            ForEach(ticks, id: \.self) { date in
                                Rectangle().fill(Color.primary.opacity(contrast == .increased ? 0.35 : 0.12))
                                    .frame(width: 1, height: stripHeight)
                                    .offset(x: position(date, width: width))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .offset(y: stripTop)

                    ForEach(ticks, id: \.self) { date in
                        let x = position(date, width: width)
                        Text(TimelineViewport.tickLabel(for: date))
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
                                .offset(x: left, y: stripTop + (stripHeight - 46) / 2)
                                .help(entryDescription(entry, task: task))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(entryDescription(entry, task: task))
                        }
                    }

                    if visibleEntries.isEmpty {
                        Text(viewport.isFollowingNow && store.runningTask == nil ? "Start a task to begin tracking." : "No tracked time here.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(width: width / 2 - 12, height: stripHeight).offset(y: stripTop)
                    }

                    let nowX = position(now, width: width)
                    if nowX >= 0 && nowX <= width {
                        Rectangle().fill(.primary).frame(width: 1.5, height: stripHeight + 2 * nowOverhang)
                            .offset(x: nowX, y: stripTop - nowOverhang)
                        if viewport.isFollowingNow {
                            Text("Now").font(.caption2.weight(.semibold))
                                .position(x: nowX, y: 7)
                                .accessibilityLabel("Now, \(now.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                    if !viewport.isFollowingNow {
                        HStack {
                            Text(dateContext).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button { viewport.followNow() } label: {
                                Label("Now", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.glass).controlSize(.mini)
                            .accessibilityLabel("Return to Now")
                        }
                        .frame(width: width, height: 20)
                    }

                }
                .clipped()
            }
            .frame(height: 116)
            .background {
                TimelineInput(scroll: { points, width in
                    viewport.scroll(points: points, width: width, now: .now)
                }, zoom: { factor, fraction in
                    viewport.zoom(factor: factor, anchorFraction: fraction, now: .now)
                }, endZoom: saveZoom)
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Timeline, \(dateContext), \(viewport.isFollowingNow ? "following now" : "browsing")")
        }
    }

    private func position(_ date: Date, width: CGFloat) -> CGFloat {
        viewport.fraction(for: date, now: now) * width
    }

    private var dateContext: String {
        if Calendar.current.isDate(visibleRange.start, inSameDayAs: visibleRange.end) {
            return visibleRange.start.formatted(date: .abbreviated, time: .omitted)
        }
        return visibleRange.start.formatted(date: .abbreviated, time: .omitted) + " – " +
            visibleRange.end.formatted(date: .abbreviated, time: .omitted)
    }

    private func entryDescription(_ entry: TimeEntry, task: TrackedTask) -> String {
        let start = entry.start.formatted(date: .abbreviated, time: .shortened)
        let end = entry.end?.formatted(date: .abbreviated, time: .shortened) ?? "now, tracking"
        return "\(task.name), \(start) to \(end)"
    }
}
