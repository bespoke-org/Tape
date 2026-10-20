import AppKit
import LineCore
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let sidebarSeparator = NSToolbarItem.Identifier("DayTape.SidebarSeparator")
    private static let navigation = NSToolbarItem.Identifier("DayTape.Navigation")
    private static let settingsTitle = NSToolbarItem.Identifier("DayTape.SettingsTitle")

    init(model: AppModel) {
        let split = NSSplitViewController()
        let sidebarController = NSHostingController(rootView: MainSidebar())
        sidebarController.sizingOptions = []
        let settingsController = NSHostingController(rootView: SettingsView(model: model))
        settingsController.sizingOptions = []
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 260
        sidebar.canCollapse = false
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: settingsController))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "DayTape"
        window.titleVisibility = .hidden
        window.contentViewController = split
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        // Like System Settings, keep green-button zoom without a full-screen mode.
        // AeroSpace recognizes this native window behavior and floats it automatically.
        window.collectionBehavior = [.fullScreenNone]
        window.toolbarStyle = .unified
        window.center()
        // Development sessions must not overwrite the personal window position.
        let suffix = ProcessInfo.processInfo.environment["LINE_DATA_DIRECTORY"].map { ".\($0)" } ?? ""
        let frameName = "DayTape.MainWindow\(suffix)"
        super.init(window: window)
        shouldCascadeWindows = false
        windowFrameAutosaveName = frameName
        window.setFrameUsingName(frameName)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "DayTape.MainWindow")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarSeparator, Self.navigation, Self.settingsTitle, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == Self.sidebarSeparator,
           let split = window?.contentViewController as? NSSplitViewController {
            return NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: split.splitView, dividerIndex: 0)
        }
        if identifier == Self.navigation {
            let item = NSToolbarItem(itemIdentifier: identifier)
            let control = NSSegmentedControl()
            control.segmentCount = 2
            control.trackingMode = .momentary
            control.segmentStyle = .automatic
            for (index, direction) in [("Back", "chevron.backward"), ("Forward", "chevron.forward")].enumerated() {
                control.setImage(NSImage(systemSymbolName: direction.1, accessibilityDescription: direction.0), forSegment: index)
                control.setToolTip(direction.0, forSegment: index)
                control.setWidth(32, forSegment: index)
                // General is the only page, so there is no navigation history yet.
                control.setEnabled(false, forSegment: index)
            }
            control.sizeToFit()
            item.view = control
            item.label = "Back and Forward"
            item.isBordered = false
            item.autovalidates = false
            return item
        }
        if identifier == Self.settingsTitle {
            let item = NSToolbarItem(itemIdentifier: identifier)
            let title = NSTextField(labelWithString: "General")
            title.font = .systemFont(ofSize: 15, weight: .semibold)
            item.view = title
            item.label = "General"
            item.isBordered = false
            return item
        }
        return nil
    }

    func present() {
        guard let window else { return }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Changing activation policy also updates the Dock asynchronously.
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.saveFrame(usingName: windowFrameAutosaveName)
        NSApp.setActivationPolicy(.accessory)
    }

}

private struct MainSidebar: View {
    var body: some View {
        List(selection: .constant("general")) {
            Label("General", systemImage: "gearshape")
                .tag("general")
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsView: View {
    @Bindable var model: AppModel

    private var zoomDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Default zoom")
            Text("Visible time when you open or reset the timeline.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var zoomSlider: some View {
        ZoomPresetSlider(model: model)
            .frame(minWidth: 180, maxWidth: .infinity)
            .frame(height: 52)
    }

    var body: some View {
        Form {
            Section("Timeline") {
                HStack(alignment: .top, spacing: 16) {
                    zoomDescription.frame(minWidth: 100, idealWidth: 200, maxWidth: 200)
                    zoomSlider
                }
                .padding(.vertical, 4)
            }
            if let message = model.settingsError ?? (model.store == nil ? model.errorMessage : nil) {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    if model.store == nil {
                        Button("Try Again") { model.load() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ZoomPresetSlider: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> ZoomPresetControl {
        ZoomPresetControl()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ZoomPresetControl, context: Context) -> CGSize? {
        CGSize(width: max(180, proposal.width ?? 320), height: 52)
    }

    func updateNSView(_ view: ZoomPresetControl, context: Context) {
        view.onChange = { [weak view] hours in
            model.setDefaultZoomHours(hours)
            view?.setHours(model.defaultZoomHours)
        }
        view.setHours(model.defaultZoomHours)
        view.slider.isEnabled = model.store != nil
    }
}

private final class ZoomPresetControl: NSView {
    let slider = NSSlider(value: 3, minValue: 0, maxValue: Double(TrackingStore.defaultZoomPresets.count - 1), target: nil, action: nil)
    private var labels: [NSTextField] = []
    var onChange: ((Int) -> Void)?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 52) }

    static func label(for hours: Int) -> String {
        hours == 1 ? "1 hour" : "\(hours) hours"
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        slider.numberOfTickMarks = TrackingStore.defaultZoomPresets.count
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.tintProminence = .none
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(selectPreset)
        slider.setAccessibilityLabel("Default zoom")
        addSubview(slider)
        labels = TrackingStore.defaultZoomPresets.map { hours in
            let label = NSTextField(labelWithString: Self.label(for: hours))
            label.isHidden = ![1, 8, 24].contains(hours)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.alignment = .center
            label.sizeToFit()
            addSubview(label)
            return label
        }
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func setHours(_ hours: Int) {
        slider.doubleValue = Double(TrackingStore.defaultZoomPresets.firstIndex(of: hours) ?? 3)
        slider.setAccessibilityValueDescription(Self.label(for: hours))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            // macOS 26 can leave the native thumb's hosted drawing layer empty
            // on first presentation. Refresh its layout after window attachment.
            @MainActor func invalidateLayout(_ view: NSView) {
                view.needsLayout = true
                view.subviews.forEach(invalidateLayout)
            }
            invalidateLayout(self.slider)
            self.slider.layoutSubtreeIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        slider.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 26)
        // Tick rectangles are cached until drawing. Use the native thumb width
        // so labels also align during the first layout and window resizing.
        let inset = slider.knobThickness / 2
        for (index, label) in labels.enumerated() {
            let center = inset + (bounds.width - 2 * inset) * CGFloat(index) / CGFloat(labels.count - 1)
            let x = min(max(center - label.frame.width / 2, 0), bounds.width - label.frame.width)
            label.setFrameOrigin(NSPoint(x: x, y: 30))
        }
    }

    @objc private func selectPreset() {
        let index = min(max(Int(slider.doubleValue.rounded()), 0), TrackingStore.defaultZoomPresets.count - 1)
        onChange?(TrackingStore.defaultZoomPresets[index])
    }
}
