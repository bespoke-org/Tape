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

                    ForEach(store.plannedSegments(in: visibleRange, at: now).filter {
                        !model.isResizingEnd || $0.plan.runningEntryID != model.resizingEntryID
                    }) { segment in
                        if let task = store.task(id: segment.plan.taskID) {
                            let plan = segment.plan
                            let selected = model.editingEntryID == plan.id || model.resizingEntryID == plan.id
                            let preview = model.resizingEntryID == plan.id && segment.interval.end == plan.end ? model.drawnRange : nil
                            let leftDate = preview.map { plan.state == .active ? max(now, $0.start) : $0.start } ?? segment.interval.start
                            let left = max(0, position(leftDate, width: width))
                            let rightDate = preview?.end ?? segment.interval.end
                            let right = min(width, position(rightDate, width: width))
                            let shape = entryShape(from: leftDate, to: rightDate, width: width)
                            let blockWidth = max(2, right - left)
                            let color = segment.isMissed ? Color.secondary : task.color.displayColor
                            Button { model.editEntry(id: plan.id) } label: {
                                shape
                                    .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : color.opacity(0.08))
                                    .overlay {
                                        shape
                                            .strokeBorder(color.opacity(contrast == .increased || selected ? 1 : 0.6),
                                                          style: StrokeStyle(lineWidth: selected || contrast == .increased ? 2 : 1, dash: [5, 3]))
                                    }
                                    .overlay(alignment: .leading) {
                                        if blockWidth > 42 {
                                            Text(task.name).font(.caption.weight(.medium)).lineLimit(1)
                                                .foregroundStyle(.secondary).padding(.horizontal, 6)
                                        }
                                    }
                                    .frame(width: blockWidth, height: 46)
                            }
                            .buttonStyle(.plain)
                            .offset(x: left, y: stripTop + (stripHeight - 46) / 2)
                            .help("\(segment.label): \(task.inputText), \(model.timeFormat.string(from: plan.start, includeDate: true)) to \(model.timeFormat.string(from: plan.end, includeDate: true))")
                            .accessibilityLabel("\(segment.label): \(task.name)")
                        }
                    }

                    ForEach(visibleEntries) { entry in
                        if let task = store.task(id: entry.taskID) {
                            let isSelected = model.editingEntryID == entry.id || model.resizingEntryID == entry.id
                            let preview = model.resizingEntryID == entry.id ? model.drawnRange : nil
                            let start = preview?.start ?? entry.start
                            let end = min(preview?.end ?? entry.end ?? now, now)
                            let left = max(0, position(start, width: width))
                            let right = min(width, position(end, width: width))
                            let shape = entryShape(from: start, to: end, width: width)
                            let entryWidth = max(2, right - left)
                            Button { model.editEntry(id: entry.id) } label: {
                                shape
                                    .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : task.color.displayColor.opacity(0.23))
                                    .overlay {
                                        if isSelected {
                                            selectionStripes(color: task.color.displayColor, shape: shape)
                                        }
                                    }
                                    .overlay {
                                        shape
                                            .strokeBorder(task.color.displayColor, lineWidth: contrast == .increased || isSelected ? 2 : 1)
                                    }
                                    .overlay(alignment: .leading) {
                                        if entryWidth > 42 {
                                            Text(task.name).font(.caption.weight(.medium)).lineLimit(1)
                                                .foregroundStyle(.primary)
                                                .padding(.horizontal, 6)
                                        }
                                    }
                                    .frame(width: entryWidth, height: 46)
                            }
                                .buttonStyle(.plain)
                                .zIndex(model.resizingEntryID == entry.id ? 1 : 0)
                                .offset(x: left, y: stripTop + (stripHeight - 46) / 2)
                                .help(entryDescription(entry, task: task))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(entryDescription(entry, task: task))
                            if let preview, preview.end > now {
                                let futureLeft = max(0, position(now, width: width))
                                let futureRight = min(width, position(preview.end, width: width))
                                if futureRight > futureLeft {
                                    let futureShape = entryShape(from: now, to: preview.end, width: width)
                                    futureShape.fill(task.color.displayColor.opacity(0.08))
                                        .overlay {
                                            futureShape.strokeBorder(task.color.displayColor.opacity(0.6),
                                                                     style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                        }
                                        .frame(width: futureRight - futureLeft, height: 46)
                                        .offset(x: futureLeft, y: stripTop + (stripHeight - 46) / 2)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }

                    if let selection = selectionRange {
                        let left = max(0, position(selection.start, width: width))
                        let right = min(width, position(selection.end, width: width))
                        if right > left {
                            let shape = entryShape(from: selection.start, to: selection.end, width: width)
                            shape
                                .fill(Color.gray.opacity(reduceTransparency ? 0.35 : 0.18))
                                .overlay {
                                    selectionStripes(color: .gray, shape: shape)
                                }
                                .overlay {
                                    shape
                                        .strokeBorder(Color.gray, lineWidth: 2)
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
                    })
                    .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Timeline, \(dateContext), \(model.timeline.isFollowingNow ? "following now" : "browsing")")
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
