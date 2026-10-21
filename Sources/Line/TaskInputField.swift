import AppKit
import SwiftUI
import Observation
import LineCore

@MainActor
@Observable
final class TaskTagCompletion {
    private(set) var text = ""
    private(set) var token: TagCompletionToken?
    private(set) var suggestions: [String] = []
    private(set) var selectedIndex: Int?
    private var dismissed = false
    private var selection = NSRange(location: 0, length: 0)
    var accept: ((String) -> Void)?

    var isVisible: Bool { !dismissed && token != nil && !suggestions.isEmpty }
    var selectedTag: String? {
        guard isVisible, let selectedIndex, suggestions.indices.contains(selectedIndex) else { return nil }
        return suggestions[selectedIndex]
    }

    func refresh(text: String, selection: NSRange, tags: [String]) {
        let changed = text != self.text || selection != self.selection
        if changed {
            self.text = text
            self.selection = selection
            dismissed = false
            selectedIndex = nil
        }
        let token = TagCompletionToken(text: text, selection: selection)
        if self.token != token { self.token = token }
        let suggestions = token.map { token in tags.filter { $0.hasPrefix(token.prefix) } } ?? []
        if self.suggestions != suggestions {
            self.suggestions = suggestions
            selectedIndex = nil
        }
    }

    func move(_ delta: Int) -> Bool {
        guard isVisible else { return false }
        selectedIndex = selectedIndex.map { min(max($0 + delta, 0), suggestions.count - 1) }
            ?? (delta > 0 ? 0 : suggestions.count - 1)
        return true
    }

    @discardableResult
    func dismiss() -> Bool {
        guard isVisible else { return false }
        dismissed = true
        selectedIndex = nil
        return true
    }

    func query(for value: String) -> String {
        guard value == text, let token else { return value }
        return token.removing(from: value)
    }
}

/// Retains the native field editor while owning completion-related key commands.
struct TaskInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let tags: [String]
    let completion: TaskTagCompletion
    let accessibilityLabel: String
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = InputTextField()
        field.isBordered = false
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "Name a task, add :tags"
        field.setAccessibilityLabel(accessibilityLabel)
        field.toolTip = "Add tags with :tag. Tags apply to every entry for the task."
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.field = field
        field.onWindowAttached = { [weak coordinator = context.coordinator] in coordinator?.updateFocus() }
        completion.accept = { [weak coordinator = context.coordinator] tag in coordinator?.accept(tag) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            if let editor = field.currentEditor() as? NSTextView {
                editor.string = text
                editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            }
        }
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.updateFocus()
        }
    }

    private final class InputTextField: NSTextField {
        var onWindowAttached: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                DispatchQueue.main.async { [weak self] in self?.onWindowAttached?() }
            }
        }
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TaskInputField
        weak var field: NSTextField?
        private var isStyling = false

        private func styleTags() {
            guard !isStyling, let field else { return }
            let editor = field.currentEditor() as? NSTextView
            guard editor?.hasMarkedText() != true else { return }
            isStyling = true
            defer { isStyling = false }
            let text = editor?.string ?? field.stringValue
            let styled = NSMutableAttributedString(string: text, attributes: [
                .font: field.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ])
            for word in text.split(whereSeparator: \.isWhitespace) where word.hasPrefix(":") && !word.hasSuffix(":") {
                styled.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                    range: NSRange(word.startIndex..<word.endIndex, in: text))
            }
            if let storage = editor?.textStorage {
                // Change only attributes so selection, marked text, and undo history remain intact.
                storage.beginEditing()
                styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attributes, range, _ in
                    storage.addAttributes(attributes, range: range)
                }
                storage.endEditing()
            } else {
                field.attributedStringValue = styled
            }
        }

        func updateFocus() {
            guard let field, let window = field.window else { return }
            if parent.isFocused && field.currentEditor() == nil {
                window.makeFirstResponder(field)
            } else if !parent.isFocused && field.currentEditor() != nil {
                window.makeFirstResponder(nil)
            }
            refresh()
        }

        init(_ parent: TaskInputField) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged(_:)),
                                                   name: NSTextView.didChangeSelectionNotification, object: nil)
        }

        func refresh() {
            guard !isStyling else { return }
            styleTags()
            guard let field, let editor = field.currentEditor() as? NSTextView else { return }
            parent.completion.refresh(text: editor.string, selection: editor.selectedRange(), tags: parent.tags)
            if let selected = parent.completion.selectedTag {
                field.setAccessibilityHelp("Tag suggestion: :\(selected). Return or Tab to insert.")
            } else {
                field.setAccessibilityHelp("Type : to suggest tags. Use arrow keys to select a tag.")
            }
        }

        @objc private func selectionChanged(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, editor === field?.currentEditor() else { return }
            refresh()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
            if let editor = field?.currentEditor() as? NSTextView {
                editor.isAutomaticTextCompletionEnabled = false
                editor.isAutomaticQuoteSubstitutionEnabled = false
                editor.isAutomaticDashSubstitutionEnabled = false
            }
            refresh()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field else { return }
            parent.text = field.stringValue
            refresh()
        }

        func accept(_ tag: String) {
            guard let token = parent.completion.token, let field else { return }
            let result = token.replacing(in: parent.completion.text, with: tag)
            parent.text = result.text
            field.stringValue = result.text
            field.window?.makeFirstResponder(field)
            if let editor = field.currentEditor() as? NSTextView {
                editor.string = result.text
                editor.setSelectedRange(NSRange(location: result.caret, length: 0))
            }
            parent.isFocused = true
            refresh()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            // Let the input method finish composing before interpreting completion keys.
            guard !textView.hasMarkedText() else { return false }
            refresh()
            switch command {
            case #selector(NSResponder.moveDown(_:)):
                return parent.completion.move(1)
            case #selector(NSResponder.moveUp(_:)):
                return parent.completion.move(-1)
            case #selector(NSResponder.insertTab(_:)):
                guard let tag = parent.completion.selectedTag else { return false }
                accept(tag)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                if let tag = parent.completion.selectedTag { accept(tag) }
                else { parent.text = textView.string; parent.submit() }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if !parent.completion.dismiss() { parent.cancel() }
                return true
            default:
                return false
            }
        }
    }
}

struct TagCompletionList: View {
    let completion: TaskTagCompletion

    var body: some View {
        if completion.isVisible {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(completion.suggestions.enumerated()), id: \.element) { index, tag in
                            Button { completion.accept?(tag) } label: {
                                HStack {
                                    Text(":" + tag).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .background(completion.selectedIndex == index ? Color.accentColor.opacity(0.2) : .clear,
                                            in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Insert tag :\(tag)")
                            .accessibilityAddTraits(completion.selectedIndex == index ? .isSelected : [])
                            .id(tag)
                        }
                    }
                }
                .frame(height: min(CGFloat(completion.suggestions.count) * 30, 90))
                .onChange(of: completion.selectedTag) { _, tag in
                    if let tag { proxy.scrollTo(tag) }
                }
            }
        }
    }
}

struct TaskSuggestionLabel: View {
    let task: TrackedTask

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(task.color.displayColor).frame(width: 8, height: 8)
            Text(task.name).lineLimit(1).layoutPriority(1)
            if !task.tags.isEmpty {
                Text(task.tagText).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .contentShape(Rectangle())
        .help(task.inputText)
    }
}
