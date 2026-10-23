import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemSettings {
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        status = readStatus()
    }

    func refresh() { status = readStatus() }

    func setEnabled(_ enabled: Bool) {
        refresh()
        errorMessage = nil
        if enabled && needsApproval {
            openSettings()
            return
        }
        do {
            if enabled && !isEnabled {
                try register()
            } else if !enabled && (isEnabled || needsApproval) {
                try unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        if enabled && status == .notFound && errorMessage == nil {
            errorMessage = "macOS could not find Tape’s login item. Reopen Tape from Finder and try again."
        }
    }

    func showSystemSettings() { openSettings() }
}
