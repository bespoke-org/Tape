import AppKit
import LineCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var store: TrackingStore?
    private(set) var errorMessage: String?
    var timeline = TimelineViewport()
    private(set) var entrySelection: EntrySelection?
    private(set) var drawnRange: DateInterval?
    private(set) var entryError: String?
    private(set) var isOverwriting = false
    private(set) var editingEntryID: UUID?
    private(set) var resizingEntryID: UUID?
    private var resizingEdge: EntryEdge?
    private var drawingStart: Date?
    var isDrawing: Bool { drawingStart != nil }
    private let storeURL: URL
    var onChange: (() -> Void)?

    init(storeURL: URL) {
        self.storeURL = storeURL
        load()
    }

    func load() {
        perform {
            store = try TrackingStore(url: storeURL)
        }
    }

    func start(_ name: String) -> Bool {
        perform { try store?.startTask(named: name) }
    }

    func stop() -> Bool {
        perform { try store?.stop() }
    }

    func checkpoint() {
        guard store?.runningEntry != nil else { return }
        perform { try store?.checkpoint() }
    }

    func preparePopover() {
        cancelEntry()
        timeline = TimelineViewport(span: store?.timelineSpan ?? TimelineViewport.defaultSpan)
    }

    func editEntry(id: UUID) {
        guard store?.entries.contains(where: { $0.id == id }) == true else { return }
        cancelEntry()
        editingEntryID = id
    }

    func selectEntry(at fraction: Double, minimumWidth: Double) {
        guard let store else { return }
        let instant = Date.now
        // Match the visible blocks, including the two-point minimum for short entries.
        // Later entries draw on top and win at shared boundaries.
        let visible = store.entries(overlapping: timeline.range(at: instant), now: instant)
        if let entry = visible.reversed().first(where: {
            let left = max(0, timeline.fraction(for: $0.start, now: instant))
            let right = min(1, timeline.fraction(for: $0.end ?? instant, now: instant))
            return fraction >= left && fraction < max(left + minimumWidth, right)
        }) {
            editEntry(id: entry.id)
        }
    }

    func saveEntry(id: UUID, taskID: UUID, start: Date, end: Date?) -> Bool {
        guard let store else { return false }
        return performEntryEdit { try store.updateEntry(id: id, taskID: taskID, start: start, end: end) }
    }

    func reassignEntry(id: UUID, taskName: String) -> Bool {
        guard let store else { return false }
        return performEntryEdit { try store.reassignEntry(id: id, taskName: taskName) }
    }

    func clearEntryError() {
        entryError = nil
    }

    func saveTaskColor(id: UUID, color: TaskColor) -> Bool {
        guard let store else { return false }
        return performEntryEdit { try store.setTaskColor(id: id, color: color) }
    }

    func deleteEntry(id: UUID) -> Bool {
        guard let store else { return false }
        let deleted = performEntryEdit { try store.deleteEntry(id: id) }
        if deleted { cancelEntry() }
        return deleted
    }

    func resizeEdge(at fraction: Double, tolerance: Double) -> EntryEdge? {
        resizeTarget(at: fraction, tolerance: tolerance, now: .now)?.1
    }

    private func resizeTarget(at fraction: Double, tolerance: Double, now instant: Date) -> (UUID, EntryEdge, Double)? {
        guard let store else { return nil }
        let visible = store.entries(overlapping: timeline.range(at: instant), now: instant)
        let pointedEntryID = visible.reversed().first {
            timeline.fraction(for: $0.start, now: instant) <= fraction &&
                fraction < timeline.fraction(for: $0.end ?? instant, now: instant)
        }?.id ?? editingEntryID
        let edges = visible.flatMap { entry -> [(UUID, EntryEdge, Double)] in
            guard let end = entry.end else { return [] }
            return [(entry.id, .start, timeline.fraction(for: entry.start, now: instant)),
                    (entry.id, .end, timeline.fraction(for: end, now: instant))]
        }.filter { $0.2 >= 0 && $0.2 <= 1 && abs($0.2 - fraction) <= tolerance }
        return edges.min(by: {
            let firstDistance = abs($0.2 - fraction)
            let secondDistance = abs($1.2 - fraction)
            if firstDistance == secondDistance {
                return $0.0 == pointedEntryID && $1.0 != pointedEntryID
            }
            return firstDistance < secondDistance
        })
    }

    func beginResizing(at fraction: Double, tolerance: Double) -> EntryEdge? {
        let instant = Date.now
        guard let nearest = resizeTarget(at: fraction, tolerance: tolerance, now: instant) else { return nil }
        cancelEntry()
        timeline.pauseFollowing(at: instant)
        resizingEntryID = nearest.0
        resizingEdge = nearest.1
        return nearest.1
    }

    func updateResizing(to fraction: Double) {
        guard let id = resizingEntryID, let edge = resizingEdge, let store else { return }
        let date = timeline.date(at: min(max(fraction, 0), 1), now: .now)
        if let selection = try? store.prepareResize(id: id, edge: edge, to: date), let end = selection.end {
            drawnRange = DateInterval(start: selection.start, end: end)
        } else {
            drawnRange = nil
        }
    }

    func finishResizing(at fraction: Double) {
        guard let id = resizingEntryID, let edge = resizingEdge, let store,
              let entry = store.entries.first(where: { $0.id == id }) else { cancelEntry(); return }
        let date = timeline.date(at: min(max(fraction, 0), 1), now: .now)
        cancelEntry()
        do {
            let selection = try store.prepareResize(id: id, edge: edge, to: date)
            _ = saveEntry(id: id, taskID: entry.taskID, start: selection.start, end: selection.end)
        } catch TrackingError.emptyInterval {
            // Dragging an edge through the other edge abandons the resize.
        } catch {
            entryError = error.localizedDescription
        }
    }

    func beginDrawing(at fraction: Double, overwriting: Bool) -> Bool {
        guard let store else { return false }
        let instant = Date.now
        let start = timeline.date(at: fraction, now: instant)
        guard overwriting || !store.entries.contains(where: { $0.start <= start && ($0.end ?? instant) > start }) else { return false }
        cancelEntry()
        isOverwriting = overwriting
        timeline.pauseFollowing(at: instant)
        drawingStart = start
        return true
    }

    func updateDrawing(to fraction: Double) {
        guard let start = drawingStart, let store else { return }
        let instant = Date.now
        let end = timeline.date(at: min(max(fraction, 0), 1), now: instant)
        if let selection = try? store.prepareEntry(from: start, to: end, snap: timeline.entrySnap, overwriting: isOverwriting) {
            drawnRange = DateInterval(start: selection.start, end: selection.end ?? instant)
        } else {
            drawnRange = nil
        }
    }

    func finishDrawing(at fraction: Double, tolerance: Double) {
        guard let start = drawingStart, let store else { return }
        let instant = Date.now
        let end = timeline.date(at: min(max(fraction, 0), 1), now: instant)
        // Make the thin Now marker hittable without changing snapping elsewhere.
        let reachesNow = abs(max(start, end).timeIntervalSince(instant)) <= timeline.span * tolerance
        drawingStart = nil
        drawnRange = nil
        do {
            entrySelection = try store.prepareEntry(from: start, to: end, reachesNow: reachesNow,
                                                   snap: timeline.entrySnap, overwriting: isOverwriting)
        } catch TrackingError.emptyInterval {
            cancelEntry()
        } catch {
            isOverwriting = false
            entryError = error.localizedDescription
        }
    }

    func createSelectedEntry(named name: String) -> Bool {
        guard let selection = entrySelection, let store else { return false }
        do {
            try store.createEntry(named: name, selection: selection)
            cancelEntry()
            errorMessage = nil
            onChange?()
            return true
        } catch {
            entryError = error.localizedDescription
            return false
        }
    }

    func cancelEntry() {
        editingEntryID = nil
        resizingEntryID = nil
        resizingEdge = nil
        isOverwriting = false
        drawingStart = nil
        drawnRange = nil
        entrySelection = nil
        entryError = nil
    }

    func saveTimelineScale() {
        guard let store, timeline.span != store.timelineSpan else { return }
        perform { try store.setTimelineSpan(timeline.span) }
    }

    private func performEntryEdit(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            entryError = nil
            errorMessage = nil
            onChange?()
            return true
        } catch {
            entryError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func perform(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            errorMessage = nil
            onChange?()
            return true
        } catch {
            errorMessage = error.localizedDescription
            onChange?()
            return false
        }
    }
}
