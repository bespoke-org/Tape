import AppKit
import LineCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var store: TrackingStore?
    private(set) var errorMessage: String?
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
