// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One piece of Markdown the live editor draws formatted, as Obsidian's Live
/// Preview does. The text itself never changes: syntax is only hidden from
/// layout (`hidden`) or kept for its width and drawn over (`drawn`, a bullet's
/// dot or a task's box), and both come back as typed source while the caret
/// is in `reveal`.
struct ScratchpadLiveElement: Equatable {
    enum Kind: Equatable {
        case heading(level: Int)
        case bold
        case italic
        case strikethrough
        case highlight
        case inlineCode
        case link(url: String)
        case wikilink(target: String)
        case tag
        case bullet
        /// `box` is the UTF-16 offset of the task's `[`, as
        /// `ScratchpadSupport.taskToggleEdit` takes it.
        case task(checked: Bool, box: Int)
        case quote
        case codeBlock
        case thematicBreak
        case frontmatter
        /// `$inline$` or a `$$display$$` block, drawn typeset over `replaced`.
        case math(tex: String, display: Bool)
        /// `![[image.png]]` or `![](image.png)`, drawn as the image.
        case embed(target: String)
        /// `%%hidden from reading%%`.
        case comment
        /// The `[!note]` line of a callout.
        case callout(type: String)
        /// A `| table | row |`, set in a fixed width so its columns line up
        /// while the caret is in it.
        case table
        /// A whole table, header and delimiter row included, drawn as a grid.
        case tableBlock(rows: [[String]])
    }

    var kind: Kind
    /// Everything the element styles, markers included.
    var range: NSRange
    /// The text the element formats, without its markers.
    var content: NSRange
    var hidden: [NSRange] = []
    var drawn: [NSRange] = []
    var reveal: NSRange
    /// Inline marks and whole lines show their source with the caret at
    /// either edge, so it never sits on a hidden character. A bullet or box
    /// keeps its width and stays drawn with the caret just after it, where
    /// the item's text starts, as in Obsidian.
    var revealsAtEdges = true
    /// The one character an image stands on while the element is formatted:
    /// it takes the image's size and the rest of `range` is hidden.
    var replaced: NSRange?
}

enum ScratchpadLiveMarkdown {
    /// Obsidian's default heading scale, H1 to H6.
    static let headingScale: [CGFloat] = [1.618, 1.462, 1.318, 1.188, 1.076, 1.0]

    static func headingSize(level: Int, base: CGFloat) -> CGFloat {
        (base * headingScale[min(max(level, 1), headingScale.count) - 1]).rounded()
    }

    static func isRevealed(_ element: ScratchpadLiveElement, by selections: [NSRange]) -> Bool {
        let reveal = element.reveal
        return selections.contains { selection in
            if element.revealsAtEdges {
                return selection.location <= NSMaxRange(reveal) && NSMaxRange(selection) >= reveal.location
            }
            if selection.length == 0 {
                return selection.location >= reveal.location && selection.location < NSMaxRange(reveal)
            }
            return NSIntersectionRange(selection, reveal).length > 0
        }
    }

    /// The characters laid out as nothing for this selection.
    static func hiddenCharacters(in elements: [ScratchpadLiveElement],
                                 selections: [NSRange],
                                 isReady: (ScratchpadLiveElement) -> Bool = { _ in true }) -> IndexSet {
        var hidden = IndexSet()
        // An image not drawn yet leaves its source showing rather than a gap.
        for element in elements where !element.hidden.isEmpty && !isRevealed(element, by: selections)
            && (element.replaced == nil || isReady(element)) {
            for range in element.hidden where range.length > 0 {
                hidden.insert(integersIn: range.location..<NSMaxRange(range))
            }
        }
        return hidden
    }

    // MARK: - Lists

    private static let listItem = regex(#"^[ \t]*(?:>[ \t]*)*(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)"#)

    /// Tab and Shift-Tab on list items nest and un-nest them, as in Obsidian:
    /// a tab goes in at (or one level comes off) the start of every line the
    /// selection touches. Nil when any of those lines is not a list item, and
    /// Tab then types a tab as anywhere else.
    static func listIndentEdit(in text: String, selection: NSRange, outdent: Bool)
        -> (range: NSRange, replacement: String, selection: NSRange)? {
        lineIndentEdit(in: text, selection: selection, outdent: outdent, requiresList: true)
    }

    /// Command-] and Command-[ indent any line, list item or not.
    static func lineIndentEdit(in text: String, selection: NSRange, outdent: Bool, requiresList: Bool)
        -> (range: NSRange, replacement: String, selection: NSRange)? {
        let ns = text as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        let block = ns.lineRange(for: selection)
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: block, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append(range)
        }
        if lines.isEmpty { lines = [NSRange(location: block.location, length: 0)] }
        guard !requiresList || lines.allSatisfy({ listItem.firstMatch(in: text, options: [.anchored], range: $0) != nil })
        else { return nil }

        let replacement = NSMutableString(string: ns.substring(with: block))
        var start = selection.location
        var end = NSMaxRange(selection)
        // From the last line up, so earlier offsets stay valid while editing.
        for line in lines.reversed() {
            let local = line.location - block.location
            var removed = 0
            if outdent {
                let lead = ns.substring(with: line).prefix(while: { $0 == " " || $0 == "\t" })
                if lead.hasPrefix("\t") { removed = 1 } else { removed = min(lead.count, 4) }
                guard removed > 0 else { continue }
                replacement.deleteCharacters(in: NSRange(location: local, length: removed))
            } else {
                replacement.insert("\t", at: local)
            }
            let delta = outdent ? -removed : 1
            // A caret inside the removed indent lands where the line now starts.
            if start > line.location { start = max(line.location, start + delta) }
            if end > line.location || (end == line.location && selection.length == 0) {
                end = max(line.location, end + delta)
            }
        }
        if selection.length == 0 { start = end }
        let replaced = replacement as String
        guard replaced != ns.substring(with: block) else { return nil }
        return (block, replaced, NSRange(location: start, length: max(0, end - start)))
    }

    // MARK: - Parsing

    static func elements(in text: String) -> [ScratchpadLiveElement] {
        let ns = text as NSString
        var elements: [ScratchpadLiveElement] = []
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append(range)
        }

        var index = 0
        // Obsidian's properties: a `---` block on the very first line.
        if let first = lines.first, first.location == 0, ns.substring(with: first) == "---",
           let close = lines.dropFirst().firstIndex(where: { ["---", "..."].contains(ns.substring(with: $0)) }) {
            let range = NSRange(location: 0, length: NSMaxRange(lines[close]))
            elements.append(ScratchpadLiveElement(kind: .frontmatter, range: range, content: range, reveal: range))
            index = close + 1
        }

        while index < lines.count {
            let line = lines[index]
            let lineText = ns.substring(with: line)
            if let fence = codeFence(in: lineText) {
                // An unclosed fence runs to the end of the note, as Obsidian
                // draws it while the closing one is still being typed.
                var end = lines.count - 1
                var closing: NSRange?
                for later in (index + 1)..<max(index + 1, lines.count) {
                    let candidate = ns.substring(with: lines[later])
                    if let other = codeFence(in: candidate), other.character == fence.character,
                       other.length >= fence.length, other.info.isEmpty {
                        end = later
                        closing = lines[later]
                        break
                    }
                }
                let range = NSRange(location: line.location, length: NSMaxRange(lines[end]) - line.location)
                let contentStart = min(NSMaxRange(line) + 1, NSMaxRange(range))
                let contentEnd = closing.map { max(contentStart, $0.location - 1) } ?? NSMaxRange(range)
                elements.append(ScratchpadLiveElement(
                    kind: .codeBlock, range: range,
                    content: NSRange(location: contentStart, length: contentEnd - contentStart),
                    hidden: [line] + (closing.map { [$0] } ?? []),
                    reveal: range))
                index = end + 1
                continue
            }
            if let table = tableBlock(ns, lines: lines, at: index) {
                elements.append(table.element)
                // Each row still parses, so a row being edited keeps its marks.
                for row in index...table.end { parseLine(ns, line: lines[row], into: &elements) }
                index = table.end + 1
                continue
            }
            if let block = mathBlock(ns, lines: lines, at: index) {
                elements.append(block.element)
                index = block.end + 1
                continue
            }
            parseLine(ns, line: line, into: &elements)
            index += 1
        }
        return elements
    }

    private static let tableDelimiter = regex(#"^[ \t]*\|?[ \t]*:?-{1,}:?[ \t]*(?:\|[ \t]*:?-{1,}:?[ \t]*)*\|?[ \t]*$"#)

    /// A table: a `|` row, a `|---|` delimiter row under it, then every
    /// `|` row after them.
    private static func tableBlock(_ ns: NSString, lines: [NSRange], at index: Int)
        -> (element: ScratchpadLiveElement, end: Int)? {
        func isRow(_ line: NSRange) -> Bool {
            ns.substring(with: line).trimmingCharacters(in: .whitespaces).hasPrefix("|")
        }
        guard index + 1 < lines.count, isRow(lines[index]),
              tableDelimiter.firstMatch(in: ns as String, options: [.anchored], range: lines[index + 1]) != nil,
              ns.substring(with: lines[index + 1]).contains("|") else { return nil }
        var end = index + 1
        while end + 1 < lines.count, isRow(lines[end + 1]) { end += 1 }
        let rows = ([index] + Array((index + 2)...max(index + 2, end)).filter { $0 <= end })
            .map { tableCells(ns.substring(with: lines[$0])) }
        let range = NSRange(location: lines[index].location, length: NSMaxRange(lines[end]) - lines[index].location)
        let element = ScratchpadLiveElement(
            kind: .tableBlock(rows: rows), range: range, content: range,
            hidden: [NSRange(location: range.location + 1, length: range.length - 1)],
            reveal: range, replaced: NSRange(location: range.location, length: 1))
        return (element, end)
    }

    /// A row's cells, without its outer pipes; `\|` stays in its cell.
    static func tableCells(_ row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in row.trimmingCharacters(in: .whitespaces) {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A `$$` block: from a line that opens with `$$` to the line that ends
    /// with it, or the one line when it does both. Unclosed, it stays text.
    private static func mathBlock(_ ns: NSString, lines: [NSRange], at index: Int)
        -> (element: ScratchpadLiveElement, end: Int)? {
        let first = ns.substring(with: lines[index]).trimmingCharacters(in: .whitespaces)
        guard first.hasPrefix("$$") else { return nil }
        var end = index
        if !(first.count >= 4 && first.hasSuffix("$$")) {
            guard let close = lines[(index + 1)...].firstIndex(where: {
                ns.substring(with: $0).trimmingCharacters(in: .whitespaces).hasSuffix("$$")
            }) else { return nil }
            end = close
        }
        let range = NSRange(location: lines[index].location, length: NSMaxRange(lines[end]) - lines[index].location)
        let source = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        let tex = String(source.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tex.isEmpty, range.length > 1 else { return nil }
        let open = ns.range(of: "$$", options: [], range: range)
        let close = ns.range(of: "$$", options: .backwards, range: range)
        let inner = NSRange(location: NSMaxRange(open), length: max(0, close.location - NSMaxRange(open)))
        let element = ScratchpadLiveElement(
            kind: .math(tex: tex, display: true), range: range, content: inner,
            hidden: [NSRange(location: range.location + 1, length: range.length - 1)],
            reveal: range, replaced: NSRange(location: range.location, length: 1))
        return (element, end)
    }

    private static func codeFence(in line: String) -> (character: Character, length: Int, info: String)? {
        let trimmed = line.drop(while: { $0 == " " })
        guard line.count - trimmed.count <= 3, let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix(while: { $0 == first })
        guard run.count >= 3 else { return nil }
        let info = trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return (first, run.count, info)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals checked by the tests; a typo must fail loudly.
        try! NSRegularExpression(pattern: pattern)
    }

    private static let thematicBreak = regex(#"^ {0,3}([-*_])[ \t]*(?:\1[ \t]*){2,}$"#)
    private static let heading = regex(#"^ {0,3}(#{1,6})(?:[ \t]+|$)"#)
    private static let quoteMarker = regex(#"^[ \t]{0,3}>[ \t]?"#)
    private static let task = regex(#"^([ \t]*)([-*+])([ \t]+)(\[([ xX])\])(?=[ \t]|$)"#)
    private static let bullet = regex(#"^([ \t]*)([-*+])([ \t]+)"#)
    private static let calloutMarker = regex(#"^\[!([A-Za-z][\w-]*)\][+-]?[ \t]*"#)

    private static func parseLine(_ ns: NSString, line: NSRange, into elements: inout [ScratchpadLiveElement]) {
        var rest = line
        func match(_ expression: NSRegularExpression) -> NSTextCheckingResult? {
            expression.firstMatch(in: ns as String, options: [.anchored], range: rest)
        }

        if let rule = thematicBreak.firstMatch(in: ns as String, options: [.anchored], range: line),
           rule.range.length == line.length {
            elements.append(ScratchpadLiveElement(kind: .thematicBreak, range: line, content: line,
                                                  drawn: [line], reveal: line))
            return
        }

        // Each `>` of a quote, nested or not, becomes a bar.
        var bars: [NSRange] = []
        while let quote = match(quoteMarker) {
            let marker = ns.range(of: ">", options: [], range: quote.range)
            bars.append(marker)
            rest = NSRange(location: NSMaxRange(quote.range), length: NSMaxRange(rest) - NSMaxRange(quote.range))
        }
        if !bars.isEmpty {
            elements.append(ScratchpadLiveElement(kind: .quote, range: line, content: rest,
                                                  drawn: bars, reveal: line))
            if let callout = match(calloutMarker) {
                let type = ns.substring(with: callout.range(at: 1)).lowercased()
                let title = NSRange(location: NSMaxRange(callout.range), length: NSMaxRange(rest) - NSMaxRange(callout.range))
                elements.append(ScratchpadLiveElement(kind: .callout(type: type), range: rest, content: title,
                                                      hidden: [callout.range], reveal: line))
                rest = title
            }
        }

        if ns.substring(with: rest).trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            elements.append(ScratchpadLiveElement(kind: .table, range: rest, content: rest, reveal: rest))
        }

        if let headingMatch = match(heading) {
            let marker = headingMatch.range
            let content = NSRange(location: NSMaxRange(marker), length: NSMaxRange(rest) - NSMaxRange(marker))
            elements.append(ScratchpadLiveElement(kind: .heading(level: headingMatch.range(at: 1).length),
                                                  range: rest, content: content,
                                                  hidden: [marker], reveal: line))
            rest = content
        } else if let taskMatch = match(task) {
            let bulletRange = NSRange(location: taskMatch.range(at: 2).location,
                                      length: taskMatch.range(at: 4).location - taskMatch.range(at: 2).location)
            let box = taskMatch.range(at: 4)
            let checked = ns.substring(with: taskMatch.range(at: 5)) != " "
            let contentStart = min(NSMaxRange(box) + 1, NSMaxRange(rest))
            let content = NSRange(location: contentStart, length: NSMaxRange(rest) - contentStart)
            elements.append(ScratchpadLiveElement(
                kind: .task(checked: checked, box: box.location),
                range: NSRange(location: bulletRange.location, length: NSMaxRange(rest) - bulletRange.location),
                content: content, hidden: [bulletRange], drawn: [box],
                reveal: NSRange(location: bulletRange.location, length: NSMaxRange(box) - bulletRange.location),
                revealsAtEdges: false))
            rest = content
        } else if let bulletMatch = match(bullet) {
            let marker = bulletMatch.range(at: 2)
            let reveal = NSRange(location: marker.location, length: NSMaxRange(bulletMatch.range) - marker.location)
            elements.append(ScratchpadLiveElement(kind: .bullet, range: reveal, content: marker,
                                                  drawn: [marker], reveal: reveal, revealsAtEdges: false))
            rest = NSRange(location: NSMaxRange(bulletMatch.range), length: NSMaxRange(rest) - NSMaxRange(bulletMatch.range))
        }

        parseInline(ns, in: rest, into: &elements)
    }

    // MARK: - Inline

    /// Stands in for characters an earlier pass claimed: one UTF-16 unit, so
    /// offsets stay put, and neither whitespace, a word character nor any
    /// marker, so later patterns can neither match it nor be stopped by it.
    private static let claimed: unichar = 0x1

    private static let escape = regex(#"\\[!-/:-@\[-`{-~]"#)
    private static let codeSpan = regex(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let wikilink = regex(#"(!?\[\[)([^\[\]|\n]+?)(\|[^\[\]\n]+?)?(\]\])"#)
    private static let link = regex(#"(!?\[)([^\[\]\n]+)(\]\(([^()\s]+)(?:[ \t]+"[^"\n]*")?\))"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let strike = regex(#"(~~)(?=\S)(.+?)(?<=\S)~~"#)
    private static let highlight = regex(#"(==)(?=\S)(.+?)(?<=\S)=="#)
    private static let starItalic = regex(#"(?<![*\w])(\*)(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)"#)
    private static let underscoreItalic = regex(#"(?<![_\w])(_)(?=[^\s_])(.+?)(?<=[^\s_])_(?![_\w])"#)
    private static let displayMath = regex(#"\$\$(?=\S)([^$\n]+?)(?<=\S)\$\$"#)
    private static let inlineMath = regex(#"(?<![$\\])\$(?=[^\s$])([^$\n]+?)(?<=[^\s$\\])\$(?![$\d])"#)
    private static let comment = regex(#"%%(.+?)%%"#)
    private static let bareURL = regex(#"(?<![\w(<\[/\x{1}])https?://[^\s<>()\[\]\x{1}]*[^\s<>()\[\].,;:!?'"\x{1}]"#)
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]
    private static let tag = regex(#"(?<![\w#&/\x{1}])#(?=[\p{L}\p{N}_/-]*[\p{L}_/-])[\p{L}\p{N}_/-]+"#)

    private static func parseInline(_ ns: NSString, in range: NSRange,
                                    into elements: inout [ScratchpadLiveElement]) {
        guard range.length > 0 else { return }
        let working = NSMutableString(string: ns.substring(with: range))
        let offset = range.location
        func shifted(_ local: NSRange) -> NSRange { NSRange(location: local.location + offset, length: local.length) }
        func claim(_ local: NSRange) {
            working.replaceCharacters(in: local, with: String(repeating: "\u{1}", count: local.length))
        }
        func matches(_ expression: NSRegularExpression) -> [NSTextCheckingResult] {
            expression.matches(in: working as String, range: NSRange(location: 0, length: working.length))
        }

        // An escaped character is plain text to every pass after this one.
        for match in matches(escape) { claim(match.range) }

        for match in matches(comment) {
            elements.append(ScratchpadLiveElement(kind: .comment, range: shifted(match.range),
                                                  content: shifted(match.range), reveal: shifted(match.range)))
            claim(match.range)
        }

        for match in matches(codeSpan) {
            let open = match.range(at: 1)
            let close = NSRange(location: NSMaxRange(match.range) - open.length, length: open.length)
            elements.append(ScratchpadLiveElement(kind: .inlineCode, range: shifted(match.range),
                                                  content: shifted(match.range(at: 2)),
                                                  hidden: [shifted(open), shifted(close)],
                                                  reveal: shifted(match.range)))
            claim(match.range)
        }

        // Math before every mark: `$a_b * c$` is TeX, not italics.
        for (expression, display) in [(displayMath, true), (inlineMath, false)] {
            for match in matches(expression) {
                let tex = working.substring(with: match.range(at: 1))
                let whole = shifted(match.range)
                elements.append(ScratchpadLiveElement(
                    kind: .math(tex: tex, display: display), range: whole, content: shifted(match.range(at: 1)),
                    hidden: [NSRange(location: whole.location + 1, length: whole.length - 1)],
                    reveal: whole, replaced: NSRange(location: whole.location, length: 1)))
                claim(match.range)
            }
        }

        for match in matches(wikilink) {
            let target = (working.substring(with: match.range(at: 2)) as String).trimmingCharacters(in: .whitespaces)
            if working.substring(with: match.range(at: 1)).hasPrefix("!"), isImage(target) {
                let whole = shifted(match.range)
                elements.append(embed(target, whole))
                claim(match.range)
                continue
            }
            let alias = match.range(at: 3)
            var hidden = [shifted(match.range(at: 1)), shifted(match.range(at: 4))]
            var content = shifted(match.range(at: 2))
            if alias.location != NSNotFound {
                // `[[note|shown]]` shows only the alias.
                hidden.append(NSRange(location: content.location, length: alias.location + 1 + offset - content.location))
                content = NSRange(location: alias.location + 1 + offset, length: alias.length - 1)
            }
            elements.append(ScratchpadLiveElement(kind: .wikilink(target: target), range: shifted(match.range),
                                                  content: content, hidden: hidden, reveal: shifted(match.range)))
            claim(match.range)
        }

        for match in matches(link) {
            let url = working.substring(with: match.range(at: 4))
            if working.substring(with: match.range(at: 1)).hasPrefix("!"), isImage(url) {
                elements.append(embed(url.removingPercentEncoding ?? url, shifted(match.range)))
                claim(match.range)
                continue
            }
            elements.append(ScratchpadLiveElement(kind: .link(url: url), range: shifted(match.range),
                                                  content: shifted(match.range(at: 2)),
                                                  hidden: [shifted(match.range(at: 1)), shifted(match.range(at: 3))],
                                                  reveal: shifted(match.range)))
            claim(match.range)
        }

        // Paired marks claim only their markers, so `**bold *and italic***`
        // still finds the italic inside.
        for (expression, kind) in [(bold, ScratchpadLiveElement.Kind.bold),
                                   (strike, .strikethrough),
                                   (highlight, .highlight),
                                   (starItalic, .italic),
                                   (underscoreItalic, .italic)] {
            for match in matches(expression) {
                let markerLength = match.range(at: 1).length
                let open = NSRange(location: match.range.location, length: markerLength)
                let close = NSRange(location: NSMaxRange(match.range) - markerLength, length: markerLength)
                // A match that grew into an earlier claim overlaps it.
                guard working.substring(with: open).utf16.allSatisfy({ $0 != claimed }),
                      working.substring(with: close).utf16.allSatisfy({ $0 != claimed }) else { continue }
                elements.append(ScratchpadLiveElement(kind: kind, range: shifted(match.range),
                                                      content: shifted(match.range(at: 2)),
                                                      hidden: [shifted(open), shifted(close)],
                                                      reveal: shifted(match.range)))
                claim(open)
                claim(close)
            }
        }

        for match in matches(bareURL) {
            let url = working.substring(with: match.range)
            elements.append(ScratchpadLiveElement(kind: .link(url: url), range: shifted(match.range),
                                                  content: shifted(match.range), reveal: shifted(match.range)))
            claim(match.range)
        }

        for match in matches(tag) {
            elements.append(ScratchpadLiveElement(kind: .tag, range: shifted(match.range),
                                                  content: shifted(match.range), reveal: shifted(match.range)))
        }
    }

    static func isImage(_ target: String) -> Bool {
        let name = target.split(separator: "|").first.map(String.init) ?? target
        return imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func embed(_ target: String, _ whole: NSRange) -> ScratchpadLiveElement {
        ScratchpadLiveElement(kind: .embed(target: target), range: whole, content: whole,
                              hidden: [NSRange(location: whole.location + 1, length: whole.length - 1)],
                              reveal: whole, replaced: NSRange(location: whole.location, length: 1))
    }

    enum MathToken: Equatable { case command, letters, number, punctuation }

    private static let mathToken = regex(#"(\\(?:[A-Za-z]+|.))|([A-Za-z]+)|([0-9]+(?:\.[0-9]+)?)|([{}()\[\]^_&|])"#)

    /// The pieces of TeX source to colour while a formula shows as source.
    static func mathTokens(in text: String, range: NSRange) -> [(NSRange, MathToken)] {
        guard range.length > 0, NSMaxRange(range) <= (text as NSString).length else { return [] }
        return mathToken.matches(in: text, range: range).compactMap { match in
            let kinds: [MathToken] = [.command, .letters, .number, .punctuation]
            for (index, kind) in kinds.enumerated() where match.range(at: index + 1).location != NSNotFound {
                return (match.range, kind)
            }
            return nil
        }
    }
}
