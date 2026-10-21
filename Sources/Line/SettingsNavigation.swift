import Observation

enum SettingsPage: String, CaseIterable, Hashable {
    case general, statistics, about

    var title: String {
        switch self {
        case .statistics: "Statistics"
        case .general: "General"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .statistics: "chart.bar"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
    var menuTitle: String {
        switch self {
        case .statistics: "Statistics"
        case .general: "General Settings"
        case .about: "About DayTape"
        }
    }

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
