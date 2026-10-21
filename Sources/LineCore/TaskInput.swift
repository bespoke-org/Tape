import Foundation

/// Plain-text task input. Emoji-style :words: remain part of the name.
public struct TaskInput: Equatable, Sendable {
    public let name: String
    public let tags: [String]

    public init(_ text: String) {
        var words: [String] = []
        var tags: [String] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            if word.hasPrefix(":") && !word.hasSuffix(":") {
                tags.append(String(word.dropFirst()))
            } else {
                words.append(String(word))
            }
        }
        name = words.joined(separator: " ")
        self.tags = Self.normalizedTags(tags)
    }

    public static func tagKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().precomposedStringWithCanonicalMapping
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.map(tagKey).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func text(name: String, tags: [String]) -> String {
        ([name] + normalizedTags(tags).map { ":" + $0 }).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// UTF-16 ranges match the native text editor, including non-ASCII text.
public struct TagCompletionToken: Equatable, Sendable {
    public let range: NSRange
    public let prefix: String

    public init?(text: String, selection: NSRange) {
        guard selection.length == 0, let caret = Range(selection, in: text)?.lowerBound,
              caret > text.startIndex, !text[text.index(before: caret)].isWhitespace else { return nil }
        var start = caret
        while start > text.startIndex && !text[text.index(before: start)].isWhitespace {
            start = text.index(before: start)
        }
        var end = caret
        while end < text.endIndex && !text[end].isWhitespace { end = text.index(after: end) }
        let word = text[start..<end]
        guard word.hasPrefix(":"), word == ":" || !word.hasSuffix(":") else { return nil }
        range = NSRange(start..<end, in: text)
        prefix = TaskInput.tagKey(String(text[text.index(after: start)..<caret]))
    }

    public func replacing(in text: String, with tag: String) -> (text: String, caret: Int) {
        let replacement = ":" + tag + " "
        let result = (text as NSString).replacingCharacters(in: range, with: replacement)
        return (result, range.location + (replacement as NSString).length)
    }

    public func removing(from text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: "")
    }
}
