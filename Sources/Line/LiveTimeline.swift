import SwiftUI
import LineCore

struct LiveTimeline: View {
    let store: TrackingStore
    let now: Date
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let stripTop: CGFloat = 28
    private let stripHeight: CGFloat = 64
    private let nowOverhang: CGFloat = 10
    private var playheadColor: Color { colorScheme == .dark ? .white : .black }
    private var visibleRange: DateInterval { model.timeline.range(at: now) }
    private var visibleEntries: ArraySlice<TimeEntry> {
        store.entries(overlapping: visibleRange, now: now)
    }

    private var lanes: [UUID: TimelineLane] { TimelineLane.layout(store.timelineEntries(at: now), now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let ticks = model.timeline.ticks(at: now, width: width)
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
                        Text(TimelineViewport.tickLabel(for: date, timeFormat: model.timeFormat))
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            .fixedSize()
                            .position(x: min(max(x, 22), width - 22), y: 108)
                            .accessibilityHidden(true)
                    }

                    ForEach(displayedSegments) { segment in
                        entrySegment(segment, width: width)
                    }

                    if let selection = selectionRange {
                        let left = max(0, position(selection.start, width: width))
                        let right = min(width, position(selection.end, width: width))
                        if right > left {
                            let pastWidth = min(right - left, max(0, position(now, width: width) - left))
                            let shape = entryShape(from: selection.start, to: selection.end, width: width)
                            shape
                                .fill(Color.gray.opacity(reduceTransparency ? 0.35 : 0.18))
                                .overlay {
                                    selectionStripes(color: .gray, shape: shape)
                                }
                                .overlay {
                                    shape
                                        .strokeBorder(Color.gray, lineWidth: 2)
                                        .mask(alignment: .leading) {
                                            Rectangle().frame(width: pastWidth)
                                        }
                                }
                                .overlay {
                                    shape
                                        .strokeBorder(Color.gray, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                        .mask(alignment: .trailing) {
                                            Rectangle().frame(width: right - left - pastWidth)
                                        }
                                }
                                .frame(width: right - left, height: 46)
                                .offset(x: left, y: stripTop + (stripHeight - 46) / 2)
                                .accessibilityLabel(model.isOverwriting ? "Selected time will replace existing entries" : "Selected time interval")
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
                        Rectangle().fill(playheadColor).frame(width: 1.5, height: stripHeight + 2 * nowOverhang)
                            .offset(x: nowX - 0.75, y: stripTop - nowOverhang)
                            .zIndex(2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: 12, y: 0))
                            path.addLine(to: CGPoint(x: 12, y: 4))
                            path.addLine(to: CGPoint(x: 6, y: 10))
                            path.addLine(to: CGPoint(x: 0, y: 4))
                            path.closeSubpath()
                        }
                        .fill(playheadColor)
                        .frame(width: 12, height: 10)
                        .offset(x: nowX - 6, y: stripTop - nowOverhang)
                        .zIndex(2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        if model.timeline.isFollowingNow {
                            Text("Now").font(.caption2.weight(.semibold))
                                .position(x: nowX, y: 7)
                                .accessibilityLabel("Now, \(model.timeFormat.string(from: now))")
                        }
                    }
                    HStack {
                        Text(dateContext).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .frame(maxWidth: model.timeline.isFollowingNow ? width / 2 - 24 : nil, alignment: .leading)
                        Spacer()
                    }
                    .frame(width: width, height: 20)

                }
                .clipped()
            }
            .frame(height: 116)
            .background {
                GeometryReader { geometry in
                    TimelineInput(scroll: { points, width in
                        model.stopTimelineAnimation()
                        model.timeline.scroll(points: points, width: width, now: .now)
                    }, zoom: { factor, fraction in
                        model.stopTimelineAnimation()
                        model.timeline.zoom(factor: factor, anchorFraction: fraction, now: .now)
                    }, resetZoom: {
                        model.resetTimeline(animated: !reduceMotion)
                    }, drawingBounds: CGRect(x: 0, y: stripTop, width: geometry.size.width, height: stripHeight),
                       interruptNavigation: { model.stopTimelineAnimation() }, beginDraw: model.beginDrawing, updateDraw: model.updateDrawing,
                       endDraw: model.finishDrawing, cancelDraw: model.cancelEntry,
                       selectEntry: model.selectEntry, resizeEdge: model.resizeEdge, beginResize: model.beginResizing,
                       updateResize: model.updateResizing, endResize: model.finishResizing, cancelEdit: {
                        guard model.editingEntryID != nil else { return false }
                        model.cancelEntry()
                        return true
                    }, pointerHeight: model.setTimelinePointerHeight)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .onAppear { model.calendars?.show(range: visibleRange) }
            .onChange(of: visibleRange) { _, _ in model.calendars?.show(range: visibleRange) }
            .accessibilityLabel("Timeline, \(dateContext), \(model.timeline.isFollowingNow ? "following now" : "browsing")")
        }
    }

    private var displayedSegments: [EntrySegment] {
        var segments = store.timelineSegments(in: visibleRange, at: now)
        if let preview = model.resizingPreview {
            segments.removeAll { $0.entry.id == preview.id }
            segments += store.timelineSegments(for: preview, in: visibleRange, at: now)
        }
        // Recorded work stays above untracked reservations where their ranges overlap.
        return segments.sorted { ($0.kind == .recorded ? 1 : 0) < ($1.kind == .recorded ? 1 : 0) }
    }

    @ViewBuilder private func entrySegment(_ segment: EntrySegment, width: CGFloat) -> some View {
        if let task = store.task(id: segment.entry.taskID) {
            let entry = segment.entry
            let lane = lanes[entry.id] ?? TimelineLane()
            let blockHeight = lane.count == 1 ? 46.0 : max(1, 46.0 / Double(lane.count) - 2)
            let offsetY = stripTop + (stripHeight - 46) / 2 + Double(lane.index) * 46 / Double(lane.count)
            let selected = model.editingEntryID == entry.id || model.resizingEntryID == entry.id
            let left = max(0, position(segment.interval.start, width: width))
            let right = min(width, position(segment.interval.end, width: width))
            let shape = entryShape(from: segment.interval.start, to: segment.interval.end, width: width)
            let recorded = segment.kind == .recorded
            let color = segment.kind == .untracked ? Color.secondary : task.color.displayColor
            Button { model.editEntry(id: entry.id) } label: {
                shape
                    .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : color.opacity(recorded ? 0.23 : 0.08))
                    .overlay {
                        if selected { selectionStripes(color: color, shape: shape) }
                    }
                    .overlay {
                        shape.strokeBorder(color.opacity(recorded || selected || contrast == .increased ? 1 : 0.6),
                                           style: StrokeStyle(lineWidth: selected || contrast == .increased ? 2 : 1,
                                                              dash: recorded ? [] : [5, 3]))
                    }
                    .frame(width: max(0, right - left), height: blockHeight)
                    .clipped()
            }
            .buttonStyle(.plain)
            .offset(x: left, y: offsetY)
            .help(entryDescription(entry, task: task))
            .accessibilityLabel(segment.kind == .planned ? "Planned: \(task.name)" : entryDescription(entry, task: task))
            // One title for the whole entry, even where Now divides its drawing style.
            if segment.interval.start == max(entry.start, visibleRange.start) {
                let labelRight = min(width, position(entry.end ?? now, width: width))
                if labelRight - left > 42 && blockHeight >= 12 {
                    HStack(spacing: 3) {
                        if store.isLinkedToCalendar(id: entry.id) { Image(systemName: "calendar") }
                        Text(task.name)
                    }.font(.caption.weight(.medium)).lineLimit(1)
                        .foregroundStyle(.primary).padding(.horizontal, 6)
                        .frame(width: labelRight - left, height: blockHeight, alignment: .leading)
                        .offset(x: left, y: offsetY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var selectionRange: DateInterval? {
        guard model.resizingEntryID == nil else { return nil }
        if let range = model.drawnRange { return range }
        guard let selection = model.entrySelection else { return nil }
        return DateInterval(start: selection.start, end: max(selection.start, selection.end ?? now))
    }

    private func entryShape(from start: Date, to end: Date, width: CGFloat) -> UnevenRoundedRectangle {
        // Match the Now marker's half-width so visually touching edges join squarely.
        let leading: CGFloat = abs(position(start, width: width) - position(now, width: width)) <= 0.75 ? 0 : 4
        let trailing: CGFloat = abs(position(end, width: width) - position(now, width: width)) <= 0.75 ? 0 : 4
        return UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                      bottomTrailingRadius: trailing, topTrailingRadius: trailing)
    }

    private func selectionStripes(color: Color, shape: UnevenRoundedRectangle) -> some View {
        Canvas { context, size in
            var stripes = Path()
            for x in stride(from: -size.height, through: size.width, by: 16) {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
            }
            context.stroke(stripes, with: .color(color.opacity(contrast == .increased ? 0.5 : 0.25)), lineWidth: 5)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func position(_ date: Date, width: CGFloat) -> CGFloat {
        model.timeline.fraction(for: date, now: now) * width
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
        let start = model.timeFormat.string(from: entry.start, includeDate: true)
        let end = entry.end.map { model.timeFormat.string(from: $0, includeDate: true) } ?? "now, tracking"
        return "\(task.inputText), \(start) to \(end)"
    }
}
