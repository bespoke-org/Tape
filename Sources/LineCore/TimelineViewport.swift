import Foundation

/// Time navigation independent of rendering cadence and native input events.
public struct TimelineViewport {
    public static let defaultSpan: TimeInterval = 4 * 60 * 60
    public private(set) var span: TimeInterval
    private var browsingCenter: Date?
    public var isFollowingNow: Bool { browsingCenter == nil }

    public init(span: TimeInterval = defaultSpan) {
        self.span = Self.usableSpan(span)
    }

    // Internal rendering limits, not additional user-facing settings.
    public static func usableSpan(_ span: TimeInterval) -> TimeInterval {
        guard span.isFinite else { return defaultSpan }
        return min(max(span, 5 * 60), 90 * 24 * 60 * 60)
    }

    public func range(at now: Date) -> DateInterval {
        let center = browsingCenter ?? now
        return DateInterval(start: center.addingTimeInterval(-span / 2), duration: span)
    }

    public mutating func scroll(points: Double, width: Double, now: Date) {
        guard points.isFinite, points != 0, width.isFinite, width > 0 else { return }
        browsingCenter = (browsingCenter ?? now).addingTimeInterval(-points / width * span)
    }

    public mutating func followNow() {
        browsingCenter = nil
    }

    public func date(at fraction: Double, now: Date) -> Date {
        range(at: now).start.addingTimeInterval(fraction * span)
    }

    public func fraction(for date: Date, now: Date) -> Double {
        date.timeIntervalSince(range(at: now).start) / span
    }

    public mutating func zoom(factor: Double, anchorFraction: Double, now: Date) {
        guard factor.isFinite, factor > 0, anchorFraction.isFinite else { return }
        let anchorFraction = min(max(anchorFraction, 0), 1)
        let anchor = date(at: anchorFraction, now: now)
        span = Self.usableSpan(span / factor)
        if !isFollowingNow {
            browsingCenter = anchor.addingTimeInterval((0.5 - anchorFraction) * span)
        }
    }

    public func ticks(at now: Date, width: Double, calendar: Calendar = .current) -> [Date] {
        guard width.isFinite, width > 0 else { return [] }
        let steps: [(seconds: Double, component: Calendar.Component, value: Int)] = [
            (60, .minute, 1), (300, .minute, 5), (900, .minute, 15), (1_800, .minute, 30),
            (3_600, .hour, 1), (10_800, .hour, 3), (21_600, .hour, 6), (43_200, .hour, 12),
            (86_400, .day, 1), (604_800, .day, 7), (2_592_000, .month, 1)
        ]
        let step = steps.first { $0.seconds >= span * 72 / width } ?? steps.last!
        let alignment: Calendar.Component = switch step.component {
        case .minute: .hour
        case .hour: .day
        case .day where step.value == 7: .weekOfYear
        default: step.component
        }
        let visible = range(at: now)
        let base = calendar.dateInterval(of: alignment, for: visible.start)?.start ?? visible.start
        let count = calendar.dateComponents([step.component], from: base, to: visible.start).value(for: step.component) ?? 0
        var tick = calendar.date(byAdding: step.component, value: count / step.value * step.value, to: base) ?? base
        var result: [Date] = []
        // Calendar increments preserve local boundaries across daylight-saving changes.
        for _ in 0..<200 {
            if tick > visible.end { break }
            if tick >= visible.start { result.append(tick) }
            guard let next = calendar.date(byAdding: step.component, value: step.value, to: tick), next > tick else { break }
            tick = next
        }
        return result
    }

    public static func tickLabel(for date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.component(.hour, from: date) == 0 && calendar.component(.minute, from: date) == 0 {
            return date.formatted(format.month(.abbreviated).day())
        }
        return date.formatted(format.hour().minute())
    }
}
