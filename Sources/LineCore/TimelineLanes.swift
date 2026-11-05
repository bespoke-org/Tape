import Foundation

/// Layout only: overlapping calendar blocks share the existing strip, never tracked duration.
public struct TimelineLane: Equatable, Sendable {
    public var index: Int
    public var count: Int
    public init(index: Int = 0, count: Int = 1) { self.index = index; self.count = count }

    public static func layout(_ entries: [TimeEntry], now: Date) -> [UUID: TimelineLane] {
        var result: [UUID: TimelineLane] = [:]
        var group: [(UUID, Int)] = []
        var ends: [Date] = []
        func finish() {
            for (id, index) in group { result[id] = TimelineLane(index: index, count: ends.count) }
            group = []; ends = []
        }
        for entry in entries.sorted(by: { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start }) {
            if let last = ends.max(), entry.start >= last { finish() }
            let index = ends.firstIndex { $0 <= entry.start } ?? ends.count
            if index == ends.count { ends.append(entry.end ?? now) }
            else { ends[index] = entry.end ?? now }
            group.append((entry.id, index))
        }
        finish()
        return result
    }
}
