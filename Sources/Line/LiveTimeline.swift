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
                        HStack {
                            if let first = store.entries.first, first.start < visibleRange.start {
                                historyIndicator("chevron.left", label: "Earlier tracked time")
                            }
                            Spacer(minLength: 0)
                            if let last = store.entries.last, (last.end ?? now) > visibleRange.end {
                                historyIndicator("chevron.right", label: "Later tracked time")
                            }
                        }
                        .padding(.horizontal, 4)
                        .frame(width: width, height: stripHeight)
                        .offset(y: stripTop)
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
                    HStack {
                        Text(dateContext).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .frame(maxWidth: viewport.isFollowingNow ? width / 2 - 24 : nil, alignment: .leading)
                        Spacer()
                        if !viewport.isFollowingNow {
                            Button { viewport.followNow() } label: {
                                Label("Now", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.glass).controlSize(.mini)
                            .accessibilityLabel("Return to Now")
                        }
                    }
                    .frame(width: width, height: 20)

                }
                .clipped()
            }
            .frame(height: 116)
            .background {
                TimelineInput(scroll: { points, width in
                    viewport.scroll(points: points, width: width, now: .now)
                }, zoom: { factor, fraction in
                    viewport.zoom(factor: factor, anchorFraction: fraction, now: .now)
                }, endZoom: saveZoom, resetZoom: {
                    if abs(viewport.span - TimelineViewport.defaultSpan) < 0.001 {
                        viewport.followNow()
                    } else {
                        viewport.zoom(factor: viewport.span / TimelineViewport.defaultSpan, anchorFraction: 0.5, now: .now)
                    }
                    saveZoom()
                })
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Timeline, \(dateContext), \(viewport.isFollowingNow ? "following now" : "browsing")")
        }
    }

    private func position(_ date: Date, width: CGFloat) -> CGFloat {
        viewport.fraction(for: date, now: now) * width
    }

    private func historyIndicator(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .help(label)
            .accessibilityLabel(label)
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
