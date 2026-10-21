import AppKit
import SwiftUI

struct AboutView: View {
    let dataURL: URL

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    private var minimumSystem: String { Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "26.0" }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DayTape").font(.title2.weight(.semibold))
                        Text("Your day, on tape.").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Text("A native time tracker that lives in your Mac’s menu bar. Track tasks on a continuous timeline, make corrections, and pick up where you left off after a break.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("App information") {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
                LabeledContent("Requires", value: "macOS \(minimumSystem) or later")
                LabeledContent("License", value: "GPL-2.0-only")
                Link("Source Code", destination: URL(string: "https://github.com/mchernigin/daytape")!)
                Link("View License", destination: URL(string: "https://github.com/mchernigin/daytape/blob/main/LICENSE")!)
            }
            Section("Your data") {
                Text("Your tasks, time entries, and preferences stay on this Mac. No account or cloud sync.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show Data in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([dataURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: dataURL.path))
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
