import Foundation

extension TrackingSnapshot {
    /// Converts legacy plans and records into entries without inventing tracked time.
    func unifyingEntries() throws -> TrackingSnapshot {
        var result = self
        let legacyPlans = plans ?? []
        var unified = legacyPlans.map { plan in
            TimeEntry(id: plan.runningEntryID ?? plan.id, taskID: plan.taskID, start: plan.start, end: plan.end,
                      state: EntryState(rawValue: plan.state.rawValue) ?? .missed, recorded: [])
        }
        var remaining: [TimeEntry] = []
        for record in entries {
            if let owner = legacyPlans.firstIndex(where: { $0.runningEntryID == record.id && $0.taskID == record.taskID }) {
                unified[owner].start = min(unified[owner].start, record.start)
                unified[owner].recorded.append(contentsOf: record.recorded)
                continue
            }
            var parts = record.recorded
            // Finished/paused plans are stronger evidence of ownership than skipped reservations.
            let owners = legacyPlans.indices.filter { legacyPlans[$0].taskID == record.taskID }.sorted {
                let a = legacyPlans[$0].state == .skipped || legacyPlans[$0].state == .missed
                let b = legacyPlans[$1].state == .skipped || legacyPlans[$1].state == .missed
                if a != b { return !a }
                return legacyPlans[$0].start < legacyPlans[$1].start
            }
            for owner in owners {
                let plan = legacyPlans[owner]
                // Open-ended manual work without a legacy link remains its own entry.
                parts = parts.flatMap { part -> [RecordedInterval] in
                    guard let end = part.end, part.start < plan.end, end > plan.start else { return [part] }
                    let start = max(part.start, plan.start)
                    let stop = min(end, plan.end)
                    unified[owner].recorded.append(RecordedInterval(id: part.id, start: start, end: stop))
                    var rest: [RecordedInterval] = []
                    if part.start < start { rest.append(RecordedInterval(start: part.start, end: start)) }
                    if stop < end { rest.append(RecordedInterval(start: stop, end: end)) }
                    return rest
                }
            }
            if !parts.isEmpty {
                var entry = record
                entry.recorded = parts
                entry.start = parts.first!.start
                entry.end = parts.last!.end
                remaining.append(entry)
            }
        }
        for index in unified.indices {
            unified[index].recorded.sort { $0.start < $1.start }
            if unified[index].state == .active && !unified[index].recorded.contains(where: { $0.end == nil }) {
                unified[index].state = .paused
            }
        }
        result.entries = (remaining + unified).sorted { $0.start < $1.start }
        result.plans = nil
        result.version = 3
        guard Set(result.entries.map(\.id)).count == result.entries.count else { throw TrackingError.unsupportedStoreVersion }
        return result
    }
}
