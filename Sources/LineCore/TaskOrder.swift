import Foundation

public enum TaskOrder: String, Codable, CaseIterable, Sendable {
    case recentlyUsed
    case alphabetical
    case mostUsed

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .recentlyUsed
    }

    func sorted(_ tasks: [TrackedTask], entries: [TimeEntry]) -> [TrackedTask] {
        var latest: [UUID: Date] = [:]
        var counts: [UUID: Int] = [:]
        if self != .alphabetical {
            for entry in entries {
                latest[entry.taskID] = max(latest[entry.taskID] ?? .distantPast, entry.start)
                counts[entry.taskID, default: 0] += 1
            }
        }
        return tasks.sorted { first, second in
            switch self {
            case .recentlyUsed:
                let a = latest[first.id] ?? .distantPast
                let b = latest[second.id] ?? .distantPast
                if a != b { return a > b }
            case .mostUsed:
                let a = counts[first.id, default: 0]
                let b = counts[second.id, default: 0]
                if a != b { return a > b }
            case .alphabetical:
                break
            }
            let comparison = first.name.localizedStandardCompare(second.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return first.id.uuidString < second.id.uuidString
        }
    }
}
