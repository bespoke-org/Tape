import AppKit
import LineCore
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let sidebarSeparator = NSToolbarItem.Identifier("Tape.SidebarSeparator")
    private static let navigation = NSToolbarItem.Identifier("Tape.Navigation")
    private static let settingsTitle = NSToolbarItem.Identifier("Tape.SettingsTitle")
    private let navigation = SettingsNavigation()
    let statisticsSelection = StatisticsSelection()
    private let statisticsController: StatisticsHostingController
    private let generalController: SettingsHostingController
    private let aboutController: NSHostingController<AboutView>
    private weak var navigationControl: NSSegmentedControl?
    private weak var pageTitle: NSTextField?

    init(model: AppModel) {
        statisticsController = StatisticsHostingController(rootView: StatisticsView(model: model, selection: statisticsSelection))
        statisticsController.sizingOptions = []
        generalController = SettingsHostingController(rootView: SettingsView(model: model))
        aboutController = NSHostingController(rootView: AboutView(dataURL: model.dataURL))
        generalController.sizingOptions = []
        aboutController.sizingOptions = []
        let split = MainSplitViewController()
        let sidebarController = NSHostingController(rootView: MainSidebar(navigation: navigation))
        sidebarController.sizingOptions = []
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 260
        sidebar.canCollapse = true
        sidebar.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: generalController))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Tape"
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
        let frameName = "Tape.MainWindow\(suffix)"
        super.init(window: window)
        navigation.onChange = { [weak self] in self?.showSelectedPage() }
        shouldCascadeWindows = false
        let frameKey = "NSWindow Frame \(frameName)"
        let legacyFrameKey = "NSWindow Frame DayTape.MainWindow\(suffix)"
        if UserDefaults.standard.string(forKey: frameKey) == nil,
           let savedFrame = UserDefaults.standard.string(forKey: legacyFrameKey) {
            UserDefaults.standard.set(savedFrame, forKey: frameKey)
        }
        windowFrameAutosaveName = frameName
        window.setFrameUsingName(frameName)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "Tape.MainWindow")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .toggleSidebar, Self.sidebarSeparator, Self.navigation, Self.settingsTitle, .flexibleSpace]
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
                control.setEnabled(false, forSegment: index)
            }
            control.sizeToFit()
            control.target = self
            control.action = #selector(navigate(_:))
            navigationControl = control
            updateNavigationControls()
            item.view = control
            item.label = "Back and Forward"
            item.isBordered = false
            item.autovalidates = false
            return item
        }
        if identifier == Self.settingsTitle {
            let item = NSToolbarItem(itemIdentifier: identifier)
            let title = NSTextField(labelWithString: navigation.page.title)
            title.font = .systemFont(ofSize: 15, weight: .semibold)
            item.view = title
            item.label = navigation.page.title
            pageTitle = title
            item.isBordered = false
            return item
        }
        return nil
    }

    private func showSelectedPage() {
        guard let window, let split = window.contentViewController as? NSSplitViewController else { return }
        let controller: NSViewController = switch navigation.page {
        case .statistics: statisticsController
        case .general: generalController
        case .about: aboutController
        }
        if let current = split.splitViewItems.last, current.viewController !== controller {
            split.removeSplitViewItem(current)
            split.addSplitViewItem(NSSplitViewItem(viewController: controller))
        }
        pageTitle?.stringValue = navigation.page.title
        pageTitle?.sizeToFit()
        updateNavigationControls()
    }

    private func updateNavigationControls() {
        navigationControl?.setEnabled(navigation.canGoBack, forSegment: 0)
        navigationControl?.setEnabled(navigation.canGoForward, forSegment: 1)
    }

    @objc private func navigate(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { navigation.goBack() }
        else if sender.selectedSegment == 1 { navigation.goForward() }
    }

    func present(page: SettingsPage? = nil) {
        if let page { navigation.select(page) }
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

private final class MainSplitViewController: NSSplitViewController {
    private weak var sidebarResponder: NSView?

    override func toggleSidebar(_ sender: Any?) {
        guard let sidebar = splitViewItems.first, let window = view.window else { return }
        if !sidebar.isCollapsed {
            let responder = window.firstResponder as? NSView
            sidebarResponder = responder?.isDescendant(of: sidebar.viewController.view) == true ? responder : nil
            super.toggleSidebar(sender)
            return
        }

        let previousResponder = window.firstResponder
        NSAnimationContext.runAnimationGroup { _ in
            super.toggleSidebar(sender)
        } completionHandler: { [weak self, weak window, weak previousResponder] in
            guard let self, let window, !sidebar.isCollapsed,
                  let responder = self.sidebarResponder else { return }
            self.sidebarResponder = nil
            // Restore focus only if the user hasn't focused another control while unfolding.
            guard window.firstResponder === previousResponder, responder.window === window else { return }
            window.makeFirstResponder(responder)
        }
    }
}

private struct MainSidebar: View {
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        List(selection: Binding<SettingsPage?>(get: { navigation.page }, set: { page in
            if let page { navigation.select(page) }
        })) {
            ForEach(SettingsPage.allCases, id: \.self) { page in
                Label {
                    Text(page.title)
                } icon: {
                    SettingsSidebarIcon(page: page)
                }
                    .tag(page)
            }
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsSidebarIcon: View {
    let page: SettingsPage

    private var color: Color {
        switch page {
        case .general: .gray
        case .statistics: .orange
        case .about: .blue
        }
    }

    var body: some View {
        Image(systemName: page.symbol)
            .resizable()
            .scaledToFit()
            .symbolVariant(.none)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 13, height: 13)
            .frame(width: 20, height: 20)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

private final class StatisticsHostingController: NSHostingController<StatisticsView> {
    private weak var tableView: NSTableView?
    private var clickMonitor: Any?

    override func viewDidAppear() {
        super.viewDidAppear()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let table = self.tableView, event.window === self.view.window,
                  event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty else { return event }
            let point = table.convert(event.locationInWindow, from: nil)
            let row = table.row(at: point)
            guard table.visibleRect.contains(point), row >= 0, row == table.selectedRow else { return event }
            // AppKit normally keeps an already selected row selected. Consume only
            // this repeat click so its default handling cannot immediately reselect it.
            table.window?.makeFirstResponder(table)
            table.deselectAll(nil)
            self.rootView.selection.filter = nil
            return nil
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        removeTableBorder(in: view)
    }

    private func removeTableBorder(in view: NSView) {
        if let table = view as? NSTableView, let scroll = table.enclosingScrollView {
            tableView = table
            if scroll.borderType != .noBorder { scroll.borderType = .noBorder }
        }
        view.subviews.forEach { removeTableBorder(in: $0) }
    }
}

private final class SettingsHostingController: NSHostingController<SettingsView> {
    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else { return }
            @MainActor func refreshSwitches(in view: NSView) {
                if view is NSSwitch {
                    refreshNativeControlLayout(view)
                } else {
                    view.subviews.forEach { refreshSwitches(in: $0) }
                }
            }
            refreshSwitches(in: self.view)
        }
    }
}

// macOS 26 can leave a native control's thumb drawing layer empty on first
// presentation. Refresh the subtree after attachment, without changing its value.
@MainActor
private func refreshNativeControlLayout(_ control: NSView) {
    @MainActor func invalidateLayout(_ view: NSView) {
        view.needsLayout = true
        view.subviews.forEach(invalidateLayout)
    }
    invalidateLayout(control)
    control.layoutSubtreeIfNeeded()
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

    private func statisticsDayStartLabel(_ hour: Int) -> String {
        // Use a fixed UTC date so a missing local DST hour still has a menu item.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour))!
        return model.timeFormat.string(from: date, calendar: calendar)
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
                Picker("Time format", selection: Binding(get: { model.timeFormat }, set: { model.setTimeFormat($0) })) {
                    Text("System").tag(TimeFormat.system)
                    Text("12-hour").tag(TimeFormat.twelveHour)
                    Text("24-hour").tag(TimeFormat.twentyFourHour)
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Time format")
                .disabled(model.store == nil)
            }
            Section("Tracking") {
                Picker(selection: Binding(get: { model.taskOrder }, set: { model.setTaskOrder($0) })) {
                    Text("Recently used").tag(TaskOrder.recentlyUsed)
                    Text("Alphabetical").tag(TaskOrder.alphabetical)
                    Text("Most used").tag(TaskOrder.mostUsed)
                } label: {
                    Text("Task order")
                    Text("Order of task suggestions when creating or editing entries.")
                        .foregroundStyle(.secondary)
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Task order")
                .help("Order task suggestions when creating or editing entries. Most used counts entries.")
                .disabled(model.store == nil)
                Toggle(isOn: Binding(get: { model.automaticResumeEnabled }, set: { model.setAutomaticResumeEnabled($0) })) {
                    Text("Automatic resume")
                    Text("Resume the interrupted task after unlocking or waking.")
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Automatic resume")
                .disabled(model.store == nil)
                LabeledContent {
                    ResumeCountdownField(model: model)
                    .disabled(model.store == nil || !model.automaticResumeEnabled)
                } label: {
                    Text("Resume countdown")
                    Text("Time before tracking resumes after unlocking or waking.")
                        .foregroundStyle(.secondary)
                }
                LabeledContent {
                    ShortBreakPicker(model: model)
                        .disabled(model.store == nil || !model.automaticResumeEnabled)
                } label: {
                    Text("Short-break threshold")
                    Text("Include shorter breaks in the same entry. Choose Never to always start a new entry.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Statistics") {
                Picker(selection: Binding(get: { model.statisticsDayStartHour }, set: { model.setStatisticsDayStartHour($0) })) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(statisticsDayStartLabel(hour)).tag(hour)
                    }
                } label: {
                    Text("Day starts at")
                    Text("Earlier hours count toward the previous day in statistics.")
                        .foregroundStyle(.secondary)
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Day starts at")
                .disabled(model.store == nil)
            }
            Section("Startup") {
                Toggle(isOn: Binding(get: { model.loginItem.isEnabled }, set: { model.loginItem.setEnabled($0) })) {
                    Text("Launch at login")
                    Text("Open Tape in the menu bar when you log in.")
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Launch at login")
                if model.loginItem.needsApproval {
                    LabeledContent("Allow Tape in Login Items to enable launch at login.") {
                        Button("Open System Settings…") { model.loginItem.showSystemSettings() }
                    }
                }
                if let message = model.loginItem.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
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
        .onAppear { model.loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.loginItem.refresh()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ShortBreakPicker: View {
    let model: AppModel
    private static let presets = [0, 30, 60, 120, 300, 600, 900, 1_800, 3_600]
    private static func label(_ seconds: Int) -> String {
        if seconds == 0 { return "Never" }
        if seconds == 60 { return "1 minute" }
        if seconds.isMultiple(of: 60) { return "\(seconds / 60) minutes" }
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    var body: some View {
        Picker("Short-break threshold", selection: Binding(
            get: { model.shortBreakSeconds },
            set: { model.setShortBreakSeconds($0) }
        )) {
            ForEach(Self.presets, id: \.self) { seconds in
                Text(Self.label(seconds)).tag(seconds)
            }
            if !Self.presets.contains(model.shortBreakSeconds) {
                Text(Self.label(model.shortBreakSeconds)).tag(model.shortBreakSeconds)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityLabel("Short-break threshold")
    }
}

private struct ResumeCountdownField: View {
    let model: AppModel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 52)
                .focused($isFocused)
                .accessibilityLabel("Resume countdown")
                .help("Enter 1–60 seconds.")
                .onChange(of: text) { _, value in
                    let digits = value.filter { $0 >= "0" && $0 <= "9" }
                    if digits != value { text = digits }
                }
                .onSubmit { save() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { save() }
                }
            Text("seconds")
                .foregroundStyle(Color.primary)
        }
        .fixedSize()
        .onAppear { text = String(model.resumeCountdownSeconds) }
        .onDisappear { save() }
        .onChange(of: model.resumeCountdownSeconds) { _, value in
            if !isFocused { text = String(value) }
        }
    }

    private func save() {
        if !text.isEmpty {
            let digits = text.drop { $0 == "0" }
            let value = digits.isEmpty ? 0 : Int(digits) ?? TrackingStore.resumeCountdownRange.upperBound
            model.setResumeCountdownSeconds(value)
        }
        text = String(model.resumeCountdownSeconds)
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
        // Keep the native track unfilled on both sides of the selected preset.
        slider.neutralValue = slider.doubleValue
        slider.setAccessibilityValueDescription(Self.label(for: hours))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            refreshNativeControlLayout(self.slider)
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
