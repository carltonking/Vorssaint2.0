// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Obsidian's editing keys for the live editor, as pure text edits: the
/// editor only maps a key to a command and applies the edit it gets back, so
/// one Command-Z takes each one back and the tests need no text view.
enum ScratchpadObsidianEditing {
    enum Command: Equatable {
        case mark(ScratchpadMark)
        /// A pair of markers with no button of its own: `==`, `%%`, `$`.
        case wrap(String)
        case toggleChecklist
        case deleteLine
        case indent
        case outdent
        case toggleReading
    }

    /// Obsidian's default editor hotkeys, plus Shift-Command X, H and M for
    /// strikethrough, highlight and math, which it leaves unbound. Command-K,
    /// Command-E and the brackets are taken from the island only while this
    /// editor has the keyboard.
    static func command(charactersIgnoringModifiers: String?, command: Bool,
                        shift: Bool, option: Bool, control: Bool) -> Command? {
        guard command, !option, !control, let key = charactersIgnoringModifiers?.lowercased() else { return nil }
        if shift {
            switch key {
            case "x": return .mark(.strikethrough)
            case "h": return .wrap("==")
            case "m": return .wrap("$")
            default: return nil
            }
        }
        switch key {
        case "b": return .mark(.bold)
        case "i": return .mark(.italic)
        case "k": return .mark(.link)
        case "l": return .toggleChecklist
        case "d": return .deleteLine
        case "]": return .indent
        case "[": return .outdent
        case "/": return .wrap("%%")
        case "e": return .toggleReading
        default: return nil
        }
    }

    static func edit(for command: Command, in text: String, selection: NSRange) -> ScratchpadMarkEdit? {
        let ns = text as NSString
        guard selection.location >= 0, NSMaxRange(selection) <= ns.length else { return nil }
        switch command {
        case .mark(let mark):
            return ScratchpadSupport.edit(applying: mark, to: text, selection: selection)
        case .wrap(let marker):
            return ScratchpadSupport.toggleWrap(marker, in: text, selection: selection)
        case .toggleChecklist:
            return checklistEdit(in: text, selection: selection)
        case .deleteLine:
            return deleteLineEdit(in: ns, selection: selection)
        case .indent, .outdent:
            return ScratchpadLiveMarkdown.lineIndentEdit(in: text, selection: selection,
                                                         outdent: command == .outdent, requiresList: false)
                .map { ScratchpadMarkEdit(range: $0.range, replacement: $0.replacement, selection: $0.selection) }
        case .toggleReading:
            return nil
        }
    }

    // MARK: - Lines

    private static let taskMarker = try! NSRegularExpression(pattern: #"^([ \t]*(?:>[ \t]*)*)([-*+]|\d{1,9}[.)])([ \t]+)\[([ xX])\]"#)
    private static let listMarker = try! NSRegularExpression(pattern: #"^([ \t]*(?:>[ \t]*)*)([-*+]|\d{1,9}[.)])([ \t]+)"#)
    private static let leadingSpace = try! NSRegularExpression(pattern: #"^([ \t]*(?:>[ \t]*)*)"#)

    /// Command-L as in Obsidian: a plain line becomes an open task, a list
    /// item gains a box, and a box flips between open and done.
    static func checklistEdit(in text: String, selection: NSRange) -> ScratchpadMarkEdit? {
        let ns = text as NSString
        let block = ns.lineRange(for: selection)
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: block, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append(range)
        }
        if lines.isEmpty { lines = [NSRange(location: block.location, length: 0)] }
        let replacement = NSMutableString(string: ns.substring(with: block))
        var caret = selection.location
        for line in lines.reversed() {
            let local = line.location - block.location
            var insertAt = line.location
            var delta = 0
            if let task = taskMarker.firstMatch(in: text, options: [.anchored], range: line) {
                let mark = task.range(at: 4)
                let flipped = ns.substring(with: mark) == " " ? "x" : " "
                replacement.replaceCharacters(in: NSRange(location: mark.location - block.location, length: 1),
                                              with: flipped)
                continue
            } else if let item = listMarker.firstMatch(in: text, options: [.anchored], range: line) {
                insertAt = NSMaxRange(item.range)
                replacement.insert("[ ] ", at: insertAt - block.location)
                delta = 4
            } else {
                let lead = leadingSpace.firstMatch(in: text, options: [.anchored], range: line)?.range.length ?? 0
                insertAt = line.location + lead
                replacement.insert("- [ ] ", at: local + lead)
                delta = 6
            }
            if caret >= insertAt, NSLocationInRange(caret, NSRange(location: line.location, length: line.length + 1)) {
                caret += delta
            }
        }
        let replaced = replacement as String
        guard replaced != ns.substring(with: block) else { return nil }
        if selection.length > 0 || lines.count > 1 {
            return ScratchpadMarkEdit(range: block, replacement: replaced,
                                      selection: NSRange(location: block.location,
                                                         length: (replaced as NSString).length))
        }
        return ScratchpadMarkEdit(range: block, replacement: replaced, selection: NSRange(location: caret, length: 0))
    }

    /// Command-D: every line the selection touches goes, its line break with
    /// it, and the caret lands where the next line now starts.
    static func deleteLineEdit(in ns: NSString, selection: NSRange) -> ScratchpadMarkEdit? {
        guard ns.length > 0 else { return nil }
        var range = ns.lineRange(for: selection)
        // The last line has no break of its own, so it takes the one before.
        if NSMaxRange(range) == ns.length, range.location > 0,
           !(ns.substring(with: range).hasSuffix("\n")) {
            range = NSRange(location: range.location - 1, length: range.length + 1)
        }
        let caret = min(range.location, ns.length - range.length)
        return ScratchpadMarkEdit(range: range, replacement: "", selection: NSRange(location: max(0, caret), length: 0))
    }

    // MARK: - Pairs

    static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
    /// Typed over a selection these wrap it, as Obsidian's "Auto pair
    /// Markdown syntax" does, rather than replacing it.
    static let wrappers: Set<String> = ["*", "_", "~", "=", "`", "$", "%", "\"", "(", "[", "{"]

    /// What typing `typed` does beyond inserting itself: wrap the selection,
    /// open a bracket with its closer, or step over a closer already there.
    /// Nil when it is plain typing.
    static func typingEdit(_ typed: String, in text: String, selection: NSRange) -> ScratchpadMarkEdit? {
        let ns = text as NSString
        guard (typed as NSString).length == 1, NSMaxRange(selection) <= ns.length else { return nil }
        let next = NSMaxRange(selection) < ns.length ? ns.substring(with: NSRange(location: NSMaxRange(selection), length: 1)) : ""
        if selection.length > 0 {
            guard wrappers.contains(typed) else { return nil }
            let close = pairs[typed] ?? typed
            let selected = ns.substring(with: selection)
            return ScratchpadMarkEdit(range: selection, replacement: typed + selected + close,
                                      selection: NSRange(location: selection.location + 1, length: selection.length))
        }
        if pairs.values.contains(typed), next == typed {
            return ScratchpadMarkEdit(range: NSRange(location: selection.location, length: 0), replacement: "",
                                      selection: NSRange(location: selection.location + 1, length: 0))
        }
        if let close = pairs[typed] {
            // Only before space, a line end or another closer, so a bracket
            // typed in front of a word does not grow a stray partner.
            guard next.isEmpty || next == "\n" || next == " " || next == "\t" || pairs.values.contains(next) else { return nil }
            return ScratchpadMarkEdit(range: selection, replacement: typed + close,
                                      selection: NSRange(location: selection.location + 1, length: 0))
        }
        return nil
    }

    /// Backspace between a bracket and its closer takes both.
    static func deletePairEdit(in text: String, selection: NSRange) -> ScratchpadMarkEdit? {
        let ns = text as NSString
        guard selection.length == 0, selection.location > 0, selection.location < ns.length else { return nil }
        let before = ns.substring(with: NSRange(location: selection.location - 1, length: 1))
        let after = ns.substring(with: NSRange(location: selection.location, length: 1))
        guard pairs[before] == after else { return nil }
        return ScratchpadMarkEdit(range: NSRange(location: selection.location - 1, length: 2), replacement: "",
                                  selection: NSRange(location: selection.location - 1, length: 0))
    }

    // MARK: - Wikilinks

    /// The note name being typed inside `[[`, for completion: from just after
    /// the brackets to the caret, on one line, before any `|`, `#` or `]`.
    static func wikilinkQuery(in text: String, caret: Int) -> (range: NSRange, query: String)? {
        let ns = text as NSString
        guard caret >= 2, caret <= ns.length else { return nil }
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        var index = caret
        while index - 2 >= line.location {
            let unit = ns.character(at: index - 1)
            if unit == 91, ns.character(at: index - 2) == 91 {
                let range = NSRange(location: index, length: caret - index)
                return (range, ns.substring(with: range))
            }
            // ] | # end the name; a newline ends the line.
            if [93, 124, 35, 10].contains(unit) { return nil }
            index -= 1
        }
        return nil
    }

    /// Notes for a `[[` query: names that start with it first, then names
    /// containing it, each alphabetical, as Obsidian ranks them roughly.
    static func wikilinkCompletions(for query: String, among names: [String], limit: Int = 30) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let unique = Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !trimmed.isEmpty else { return Array(unique.prefix(limit)) }
        let starts = unique.filter { $0.range(of: trimmed, options: [.caseInsensitive, .anchored, .diacriticInsensitive]) != nil }
        let contains = unique.filter {
            $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil && !starts.contains($0)
        }
        return Array((starts + contains).prefix(limit))
    }
}
