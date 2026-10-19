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

    func beginDrawing(at fraction: Double) -> Bool {
        guard let store else { return false }
        let instant = Date.now
        let start = timeline.date(at: fraction, now: instant)
        guard !store.entries.contains(where: { $0.start <= start && ($0.end ?? instant) > start }) else { return false }
        cancelEntry()
        timeline.pauseFollowing(at: instant)
        drawingStart = start
        return true
    }

    func updateDrawing(to fraction: Double) {
        guard let start = drawingStart else { return }
        let end = timeline.date(at: min(max(fraction, 0), 1), now: .now)
        drawnRange = DateInterval(start: min(start, end), end: max(start, end))
    }

    func finishDrawing(at fraction: Double, tolerance: Double) {
        guard let start = drawingStart, let store else { return }
        let instant = Date.now
        let end = timeline.date(at: min(max(fraction, 0), 1), now: instant)
        // Make the thin Now marker hittable without changing minute snapping elsewhere.
        let reachesNow = abs(max(start, end).timeIntervalSince(instant)) <= timeline.span * tolerance
        drawingStart = nil
        drawnRange = nil
        do {
            entrySelection = try store.prepareEntry(from: start, to: end, reachesNow: reachesNow)
        } catch {
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
        drawingStart = nil
        drawnRange = nil
        entrySelection = nil
        entryError = nil
    }

    func saveTimelineScale() {
        guard let store, timeline.span != store.timelineSpan else { return }
        perform { try store.setTimelineSpan(timeline.span) }
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
