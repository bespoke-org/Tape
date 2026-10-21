import Observation

enum SettingsPage: String, CaseIterable, Hashable {
    case general, about

    var title: String { self == .general ? "General" : "About" }
    var symbol: String { self == .general ? "gearshape" : "info.circle" }
    var menuTitle: String { self == .general ? "General Settings…" : "About DayTape" }
}

@MainActor
@Observable
final class SettingsNavigation {
    private(set) var page: SettingsPage = .general
    private var backHistory: [SettingsPage] = []
    private var forwardHistory: [SettingsPage] = []
    var onChange: (() -> Void)?

    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }

    func select(_ page: SettingsPage) {
        guard page != self.page else { return }
        backHistory.append(self.page)
        forwardHistory.removeAll()
        self.page = page
        onChange?()
    }

    func goBack() {
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(page)
        page = previous
        onChange?()
    }

    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(page)
        page = next
        onChange?()
    }
}
