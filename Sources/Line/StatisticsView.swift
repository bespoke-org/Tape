import AppKit
import LineCore
import Observation
import SwiftUI

@MainActor
@Observable
final class StatisticsSelection {
    var period: StatisticsPeriod = .week
    var anchor = Date.now
    var grouping: StatisticsGrouping = .tags
    var filter: StatisticsFilter?
    var search = ""

    func move(_ direction: Int, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        let range = period.interval(containing: anchor, calendar: calendar)
        guard direction < 0 || range.end <= now else { return }
        anchor = direction < 0 ? range.start.addingTimeInterval(-1) : range.end
    }

    func select(_ filter: StatisticsFilter) {
        self.filter = self.filter == filter ? nil : filter
    }

    func showDay(_ date: Date) {
        anchor = date
        period = .day
    }
}

struct StatisticsView: View {
    let model: AppModel
    @Bindable var selection: StatisticsSelection
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let report = StatisticsReport(tasks: model.store?.tasks ?? [], entries: model.store?.entries ?? [],
                                          interval: selection.period.interval(containing: selection.anchor),
                                          now: context.date, filter: selection.filter)
            GeometryReader { geometry in
                let compact = geometry.size.height < 520
                VStack(spacing: compact ? 12 : 16) {
                    if model.store == nil {
                        ContentUnavailableView {
                            Label("Statistics unavailable", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(model.errorMessage ?? "Could not load tracking data.")
                        } actions: {
                            Button("Try Again") { model.load() }
                        }
                    } else {
                        summary(report, now: context.date, compact: compact)
                            .fixedSize(horizontal: false, vertical: true)
                        breakdown(report, compact: compact)
                    }
                }
                .padding(compact ? 12 : 20)
                .frame(maxWidth: 1_100, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func summary(_ report: StatisticsReport, now: Date, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                    Text("Time tracked")
                        .font(.body)
                        .accessibilityHidden(true)
                    Text(Self.duration(report.selectedTotal))
                        .font(.system(size: compact ? 28 : 32, weight: .regular))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityLabel("Time tracked: \(Self.duration(report.selectedTotal))")
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: compact ? 4 : 6) {
                    HStack(spacing: 8) {
                        Picker("Period", selection: $selection.period) {
                            Text("Day").tag(StatisticsPeriod.day)
                            Text("Week").tag(StatisticsPeriod.week)
                            Text("Month").tag(StatisticsPeriod.month)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel("Statistics period")
                        HStack(spacing: 6) {
                            Button { selection.move(-1) } label: { Text(Image(systemName: "chevron.left")) }
                                .accessibilityLabel("Previous statistics period")
                            Button(selection.period == .day ? "Today" : selection.period == .week ? "This week" : "This month") {
                                selection.anchor = now
                            }
                            .accessibilityLabel("Current statistics period")
                            Button { selection.move(1) } label: { Text(Image(systemName: "chevron.right")) }
                                .disabled(report.interval.end > now)
                                .accessibilityLabel("Next statistics period")
                        }
                        .fixedSize()
                    }
                    Text(periodLabel(report.interval))
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .controlSize(.regular)
            if selection.period == .day {
                dayChart(report, compact: compact)
            } else {
                dailyChart(report, now: now, compact: compact)
            }

        }
        .statisticsCard(padding: compact ? 12 : 18, background: .background.secondary)
    }

    private func dailyChart(_ report: StatisticsReport, now: Date, compact: Bool) -> some View {
        let maximum = max(4 * 3_600, ceil((report.days.map(\.total).max() ?? 0) / 7_200) * 7_200)
        let height: CGFloat = compact ? 60 : 140
        let tickCount = compact ? 2 : 4
        return GeometryReader { geometry in
            let plotWidth = max(1, geometry.size.width - 32)
            let slot = plotWidth / CGFloat(max(1, report.days.count))
            ZStack(alignment: .topLeading) {
                ForEach(0...tickCount, id: \.self) { tick in
                    let y = height * CGFloat(tickCount - tick) / CGFloat(tickCount)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: plotWidth, y: y))
                    }
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                    Text("\((maximum / 3_600 * Double(tick) / Double(tickCount)).formatted(.number.precision(.fractionLength(0...1))))h")
                        .font(.caption2).foregroundStyle(.secondary)
                        .position(x: plotWidth + 18, y: y)
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(report.days) { day in
                        let segments = report.segments(in: day.interval, grouping: selection.grouping)
                        Button { selection.showDay(day.interval.start) } label: {
                            VStack(spacing: 8) {
                                VStack(spacing: 0) {
                                    if day.total > day.selected {
                                        chartBlock(barShape(top: true, bottom: segments.isEmpty), color: .gray)
                                            .frame(height: height * (day.total - day.selected) / maximum)
                                    }
                                    ForEach(segments.reversed()) { segment in
                                        chartBlock(barShape(top: segment.id == segments.last?.id && day.total <= day.selected,
                                                            bottom: segment.id == segments.first?.id),
                                                   color: segment.color?.displayColor ?? .gray)
                                            .frame(height: height * segment.duration / maximum)
                                    }
                                }
                                .frame(width: max(2, slot * 0.6))
                                .frame(height: height, alignment: .bottom)
                                Text(dayLabel(day.interval.start))
                                    .font(.caption2)
                                    .foregroundStyle(Calendar.autoupdatingCurrent.isDateInToday(day.interval.start) ? Color.blue : Color.secondary)
                                    .lineLimit(1)
                                    .frame(height: 16)
                            }
                            .frame(width: slot)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(day.interval.start > now)
                        .help(barDescription(day, segments: segments))
                        .accessibilityLabel("Explore \(day.interval.start.formatted(date: .complete, time: .omitted)), \(Self.duration(day.selected))")
                    }
                }
                .frame(width: plotWidth)
            }
            .padding(.top, 6)
        }
        .frame(height: height + 34)
    }

    private func barShape(top: Bool, bottom: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: top ? 3 : 0,
                               bottomLeadingRadius: bottom ? 3 : 0,
                               bottomTrailingRadius: bottom ? 3 : 0,
                               topTrailingRadius: top ? 3 : 0)
    }

    private func barDescription(_ day: StatisticsDay, segments: [StatisticsRow]) -> String {
        let heading = "\(day.interval.start.formatted(date: .abbreviated, time: .omitted)): \(Self.duration(day.selected))"
        let shares = segments.map { "\(displayName($0)): \(Self.duration($0.duration))" }.joined(separator: "\n")
        let note = selection.grouping == .tags && selection.filter?.grouping != .tags
            ? "\nChart shares divide each session equally among its tags." : ""
        return heading + (shares.isEmpty ? "" : "\n" + shares + note)
    }

    private func dayChart(_ report: StatisticsReport, compact: Bool) -> some View {
        let trackY: CGFloat = compact ? 10 : 44
        let trackHeight: CGFloat = compact ? 20 : 42
        return GeometryReader { geometry in
            let width = geometry.size.width
            let range = report.interval
            let ticks = [0, 6, 12, 18].compactMap { hour in
                Calendar.autoupdatingCurrent.date(bySettingHour: hour, minute: 0, second: 0, of: range.start)
            } + [range.end]
            ZStack(alignment: .topLeading) {
                ForEach(0..<5) { index in
                    let time = ticks[index]
                    let fraction = time.timeIntervalSince(range.start) / range.duration
                    Rectangle().fill(Color.primary.opacity(0.09))
                        .frame(width: 1, height: compact ? 32 : 110).offset(x: width * fraction, y: 10)
                    Text(model.timeFormat.string(from: time))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 70, alignment: index == 0 ? .leading : index == 4 ? .trailing : .center)
                        .position(x: index == 0 ? 35 : index == 4 ? width - 35 : width * fraction, y: compact ? 52 : 140)
                }
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05))
                    .frame(height: trackHeight).offset(y: trackY)
                ForEach(report.sessions) { session in
                    let x = session.interval.start.timeIntervalSince(range.start) / range.duration * width
                    let length = session.duration / range.duration * width
                    Button { selection.select(.task(session.task.id)) } label: {
                        chartBlock(RoundedRectangle(cornerRadius: 3), color: session.task.color.displayColor,
                                   isSelected: selection.filter == .task(session.task.id))
                            .opacity(selection.filter?.matches(session.task) ?? true ? 1 : 0.2)
                            .frame(width: max(1, length - 1), height: trackHeight)
                    }
                    .buttonStyle(.plain)
                    .offset(x: x, y: trackY)
                    .help(sessionDescription(session))
                    .accessibilityLabel(sessionDescription(session))
                }
                if report.sessions.isEmpty {
                    Text("No tracked time on this day")
                        .foregroundStyle(.secondary)
                        .frame(width: width, height: trackHeight).offset(y: trackY)
                }
            }
        }
        .frame(height: compact ? 64 : 165)
    }

    private func chartBlock<S: InsettableShape>(_ shape: S, color: Color, isSelected: Bool = false) -> some View {
        shape
            .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : color.opacity(0.23))
            .overlay {
                shape.strokeBorder(color, lineWidth: contrast == .increased || isSelected ? 2 : 1)
            }
    }

    private func breakdown(_ report: StatisticsReport, compact: Bool) -> some View {
        let rows = report.rows(grouping: selection.grouping, search: selection.search)
        let heading = (selection.grouping == .tasks ? "Tasks" : "Tags") +
            (selection.filter.map { $0.grouping != selection.grouping ? " in " + filterName($0) : "" } ?? "")
        return VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                Picker("Group by", selection: $selection.grouping) {
                    Text("Tasks").tag(StatisticsGrouping.tasks)
                    Text("Tags").tag(StatisticsGrouping.tags)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("Statistics grouping")
                Spacer(minLength: 12)
                StatisticsSearchField(text: $selection.search)
                    .frame(maxWidth: 180)
                    .accessibilityLabel("Search statistics")
            }
            Table(rows, selection: Binding<StatisticsFilter?>(
                get: { rows.contains(where: { $0.id == selection.filter }) ? selection.filter : nil },
                set: { value in
                    let grouping = selection.grouping
                    let previous = selection.filter
                    let canClear = rows.contains { $0.id == previous }
                    // AppKit delivers selection while handling its delegate callback.
                    // Apply the filter afterwards, since it can rebuild the row data.
                    DispatchQueue.main.async {
                        guard selection.grouping == grouping else { return }
                        if let value {
                            selection.filter = value
                        } else if canClear && selection.filter == previous {
                            selection.filter = nil
                        }
                    }
                }
            )) {
                TableColumn(heading) { row in
                    HStack(spacing: 10) {
                        Circle().fill(row.color?.displayColor ?? .gray).frame(width: 8, height: 8)
                        Text(displayName(row)).lineLimit(1).truncationMode(.middle)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(displayName(row)), \(Self.duration(row.duration))")
                    .help(displayName(row))
                }
                .width(min: 100, ideal: 240)
                TableColumn("Time") { row in
                    Text(Self.duration(row.duration)).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 80, ideal: 100, max: 120)
            }
            .tableStyle(.bordered)
            .alternatingRowBackgrounds()
            .accessibilityLabel("Statistics breakdown")
            .onExitCommand { selection.filter = nil }
            .overlay {
                if rows.isEmpty {
                    Text(selection.search.isEmpty ? "No tracked time in this period" : "No matches")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 60, maxHeight: .infinity)
        }
        .statisticsCard(padding: compact ? 12 : 18, background: Color(nsColor: .controlBackgroundColor))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds > 0 && seconds < 60 { return "<1m" }
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)m")
    }

    private func tagDisplayName(_ tag: String) -> String {
        String(tag.prefix(1)).localizedUppercase + String(tag.dropFirst())
    }

    private func displayName(_ row: StatisticsRow) -> String {
        if case .tag(let tag) = row.id { return tagDisplayName(tag) }
        return row.name
    }

    private func filterName(_ filter: StatisticsFilter) -> String {
        switch filter {
        case .task(let id): model.store?.task(id: id)?.name ?? "Deleted task"
        case .tag(let tag): tagDisplayName(tag)
        case .untagged: "Untagged"
        }
    }

    private func periodLabel(_ interval: DateInterval) -> String {
        if selection.period == .day { return interval.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
        if selection.period == .month { return interval.start.formatted(.dateTime.month(.wide).year()) }
        return interval.start.formatted(.dateTime.month(.abbreviated).day()) + " – " +
            interval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func dayLabel(_ date: Date) -> String {
        if selection.period == .week { return date.formatted(.dateTime.weekday(.abbreviated)) }
        let day = Calendar.autoupdatingCurrent.component(.day, from: date)
        return day == 1 || day.isMultiple(of: 5) ? "\(day)" : ""
    }

    private func sessionDescription(_ session: StatisticsSession) -> String {
        "\(session.task.inputText), \(model.timeFormat.string(from: session.interval.start))–\(model.timeFormat.string(from: session.interval.end)), \(Self.duration(session.duration))"
    }
}

private struct StatisticsSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search"
        field.setAccessibilityLabel("Search statistics")
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        @objc func searchChanged(_ field: NSSearchField) {
            text.wrappedValue = field.stringValue
        }
    }
}

private extension View {
    func statisticsCard<S: ShapeStyle>(padding: CGFloat = 18, background: S) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
    }
}
