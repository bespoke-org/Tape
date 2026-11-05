import SwiftUI
import LineCore

struct CalendarsView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let store = model.store, let service = model.calendars {
            Form {
                Section {
                    Toggle("Calendar integration", isOn: Binding(get: { store.calendarsEnabled }, set: { service.setEnabled($0) }))
                        .accessibilityLabel("Calendar integration")
                    Toggle("Automatically track calendar events", isOn: Binding(get: { store.automaticCalendarTracking }, set: { service.setAutomatic($0) }))
                        .accessibilityLabel("Automatically track calendar events")
                        .disabled(!store.calendarsEnabled)
                }
                if store.calendarsEnabled {
                    if service.accessGranted {
                        let accounts = Array(Set(service.calendars.map(\.account))).sorted()
                        if !accounts.isEmpty {
                            Section("Calendars") {
                                ForEach(accounts, id: \.self) { account in
                                    let calendars = service.calendars.filter { $0.account == account }
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(account)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .accessibilityAddTraits(.isHeader)
                                        ForEach(calendars) { calendar in
                                            Toggle(calendar.title, isOn: Binding(
                                                get: { store.selectedCalendarIDs.contains(calendar.id) },
                                                set: { service.setSelected(calendar.id, selected: $0) }))
                                                .toggleStyle(.checkbox)
                                                .accessibilityLabel(calendar.title)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        if service.calendars.isEmpty && !service.isRefreshing {
                            Text("Add an account in macOS Calendar to make its calendars available here.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Allow Tape to access calendars in System Settings → Privacy & Security → Calendars.")
                        Button("Open Calendar Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                }
                if let error = service.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .toggleStyle(.switch)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onAppear { service.refresh() }
        }
    }
}
