// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Formats the scratchpad's Markdown in place, as Obsidian's Live Preview does:
/// the file stays plain Markdown, and only its drawing changes. Attributes come
/// from `ScratchpadLiveMarkdown` after every edit; which syntax is hidden
/// follows the caret, so the line or mark being edited shows as typed.
///
/// TextKit 1 on purpose: hiding characters from layout is a layout manager
/// delegate call there, and TextKit 2 has no equivalent that keeps the caret,
/// find bar and undo of a plain NSTextView.
final class ScratchpadLiveStyler: NSObject, NSTextStorageDelegate, NSLayoutManagerDelegate {
    static let linkKey = NSAttributedString.Key("VorssaintScratchpadLink")
    static let wikilinkKey = NSAttributedString.Key("VorssaintScratchpadWikilink")

    var baseSize: CGFloat
    var textColor: NSColor
    weak var textView: ScratchpadLiveTextView?
    private(set) var elements: [ScratchpadLiveElement] = []
    private(set) var revealed: [Bool] = []
    private var hidden = IndexSet()
    /// Characters whose hidden state changed during an edit, waiting for the
    /// layout manager to finish it before their glyphs can be invalidated.
    private var pendingInvalidation = IndexSet()
    /// A typeset formula or embedded image, standing on one character.
    struct Picture {
        let image: NSImage
        let size: NSSize
        /// On a line of its own, centred for math, rather than in the text.
        let block: Bool
        let centered: Bool
    }
    /// The pictures showing now, by the character each stands on.
    private(set) var pictures: [Int: Picture] = [:]
    /// Where `![[name.png]]` points; the pad answers from its vault.
    var resolveEmbed: ((String) -> URL?)?
    private var renderObserver: NSObjectProtocol?

    init(baseSize: CGFloat, textColor: NSColor) {
        self.baseSize = baseSize
        self.textColor = textColor
        super.init()
        renderObserver = NotificationCenter.default.addObserver(
            forName: ScratchpadMathRenderer.didRender, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restyleAll() }
        }
    }

    deinit {
        if let renderObserver { NotificationCenter.default.removeObserver(renderObserver) }
    }

    /// The colour formulas are typeset in, fixed for the editor's appearance.
    private var resolvedTextColor: NSColor {
        var resolved = textColor
        (textView?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            resolved = NSColor(cgColor: textColor.cgColor) ?? textColor
        }
        return resolved
    }

    /// The picture an element draws as, or nil while it is not ready (or is
    /// not a picture), which leaves its source showing.
    @MainActor
    func picture(for element: ScratchpadLiveElement) -> Picture? {
        let renderer = ScratchpadMathRenderer.shared
        switch element.kind {
        case .math(let tex, let display):
            guard let image = renderer.image(tex: tex, display: display, fontSize: baseSize,
                                             color: resolvedTextColor) else { return nil }
            return Picture(image: image, size: image.size, block: display && isAlone(element), centered: true)
        case .tableBlock(let rows):
            guard let image = renderer.image(table: rows, fontSize: baseSize, color: resolvedTextColor) else { return nil }
            return Picture(image: image, size: image.size, block: true, centered: false)
        case .embed(let target):
            let url: URL? = target.hasPrefix("http://") || target.hasPrefix("https://")
                ? URL(string: target) : resolveEmbed?(target)
            guard let url, let image = renderer.image(embed: url) else { return nil }
            let width = max(40, (textView?.textContainer?.size.width ?? 300) - 16)
            let scale = min(1, width / max(image.size.width, 1), 360 / max(image.size.height, 1))
            return Picture(image: image,
                           size: NSSize(width: (image.size.width * scale).rounded(),
                                        height: (image.size.height * scale).rounded()),
                           block: isAlone(element), centered: false)
        default:
            return nil
        }
    }

    /// Whether nothing but space shares the element's lines.
    private func isAlone(_ element: ScratchpadLiveElement) -> Bool {
        guard let text = textView?.string as NSString?, NSMaxRange(element.range) <= text.length else { return false }
        let lines = text.lineRange(for: element.range)
        let before = text.substring(with: NSRange(location: lines.location, length: element.range.location - lines.location))
        let after = text.substring(with: NSRange(location: NSMaxRange(element.range),
                                                 length: NSMaxRange(lines) - NSMaxRange(element.range)))
        return (before + after).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Hidden characters and pictures for `selections`, together, so the two
    /// can never disagree about which elements are formatted.
    @MainActor
    private func formatting(for selections: [NSRange]) -> (hidden: IndexSet, pictures: [Int: Picture]) {
        var ready: [Int: Picture] = [:]
        for element in elements {
            guard let replaced = element.replaced, !ScratchpadLiveMarkdown.isRevealed(element, by: selections),
                  let picture = picture(for: element) else { continue }
            ready[replaced.location] = picture
        }
        let hidden = ScratchpadLiveMarkdown.hiddenCharacters(in: elements, selections: selections) { element in
            element.replaced.map { ready[$0.location] != nil } ?? true
        }
        return (hidden, ready)
    }

    var baseFont: NSFont { .systemFont(ofSize: baseSize) }

    /// Obsidian's TeX colours, a shade deeper on a light pad so they still read.
    static let mathCommand = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.98, green: 0.36, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.80, green: 0.16, blue: 0.22, alpha: 1)
    }
    static let mathLetters = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.33, green: 0.80, blue: 0.80, alpha: 1)
            : NSColor(srgbRed: 0.05, green: 0.52, blue: 0.55, alpha: 1)
    }
    static let mathNumber = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.62, blue: 0.35, alpha: 1)
            : NSColor(srgbRed: 0.75, green: 0.40, blue: 0.08, alpha: 1)
    }
    var mutedColor: NSColor { Self.faded(textColor, 0.45) }
    var codeBackground: NSColor { Self.faded(textColor, 0.08) }

    /// `color` at `alpha`, resolved each time it is drawn. `withAlphaComponent`
    /// on a system colour fixes it to whichever appearance is current when it
    /// is made, which leaves white syntax on a light pad when the Mac is dark.
    static func faded(_ color: NSColor, _ alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved = color
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor(cgColor: color.cgColor) ?? color
            }
            return resolved.withAlphaComponent(resolved.alphaComponent * alpha)
        }
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        // A nested item steps in by two letters, as Obsidian indents, rather
        // than AppKit's default 28 points per tab.
        style.tabStops = []
        style.defaultTabInterval = (baseSize * 2).rounded()
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: textColor, .paragraphStyle: paragraphStyle]
    }

    // MARK: - Styling

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        var previous = hidden
        let oldEnd = NSMaxRange(editedRange) - delta
        previous.remove(integersIn: editedRange.location..<max(editedRange.location, oldEnd))
        previous.shift(startingAt: oldEnd, by: delta)
        restyle(textStorage)
        // The text view still holds the selection from before the edit. Moved
        // past the edit it stays where it was: a checkbox clicked on another
        // line must not reveal its own line for even one layout pass, which
        // left a box drawn in the middle of the text. A caret inside the edit
        // goes to its end, where typing and pasting leave it.
        let selections = (textView?.selectedRanges.map(\.rangeValue) ?? []).map { selection -> NSRange in
            if selection.location >= oldEnd { return NSRange(location: selection.location + delta, length: selection.length) }
            if NSMaxRange(selection) < editedRange.location { return selection }
            return NSRange(location: NSMaxRange(editedRange), length: 0)
        }
        let formatted = MainActor.assumeIsolated { formatting(for: selections) }
        hidden = formatted.hidden
        pictures = formatted.pictures
        pendingInvalidation.shift(startingAt: oldEnd, by: delta)
        pendingInvalidation.formUnion(previous.symmetricDifference(hidden))
        revealed = []
    }

    /// Restyles the whole note. Notes are small enough that one pass per edit
    /// costs less than tracking which blocks an edit can reach: a typed ```
    /// changes every line after it.
    func restyle(_ storage: NSTextStorage) {
        elements = ScratchpadLiveMarkdown.elements(in: storage.string)
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes(baseAttributes, range: full)
        for element in elements { apply(element, to: storage) }
    }

    /// Restyles outside an edit, after a size or colour change.
    func restyleAll() {
        guard let storage = textView?.textStorage else { return }
        storage.beginEditing()
        restyle(storage)
        storage.endEditing()
        textView?.typingAttributes = baseAttributes
        hidden = IndexSet()
        pictures = [:]
        revealed = []
        if let layout = textView?.layoutManager {
            layout.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: storage.length),
                                    changeInLength: 0, actualCharacterRange: nil)
        }
        refresh()
    }

    private func apply(_ element: ScratchpadLiveElement, to storage: NSTextStorage) {
        func add(_ key: NSAttributedString.Key, _ value: Any, _ range: NSRange) {
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
            storage.addAttribute(key, value: value, range: range)
        }
        func addTrait(_ trait: NSFontTraitMask, _ range: NSRange) {
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                let font = (value as? NSFont) ?? baseFont
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
            }
        }
        let mono = NSFont.monospacedSystemFont(ofSize: max(9, baseSize - 1), weight: .regular)

        switch element.kind {
        case .heading(let level):
            let size = ScratchpadLiveMarkdown.headingSize(level: level, base: baseSize)
            add(.font, NSFont.systemFont(ofSize: size, weight: .bold), element.range)
        case .bold:
            addTrait(.boldFontMask, element.content)
        case .italic:
            addTrait(.italicFontMask, element.content)
        case .strikethrough:
            add(.strikethroughStyle, NSUnderlineStyle.single.rawValue, element.content)
        case .highlight:
            add(.backgroundColor, Self.faded(.systemYellow, 0.35), element.content)
        case .inlineCode:
            add(.font, mono, element.range)
            add(.backgroundColor, codeBackground, element.content)
        case .link(let url):
            add(.foregroundColor, NSColor.controlAccentColor, element.content)
            add(.underlineStyle, NSUnderlineStyle.single.rawValue, element.content)
            add(Self.linkKey, url, element.content)
        case .wikilink(let target):
            add(.foregroundColor, NSColor.controlAccentColor, element.content)
            add(Self.wikilinkKey, target, element.content)
        case .tag:
            add(.foregroundColor, NSColor.controlAccentColor, element.range)
            add(.backgroundColor, Self.faded(.controlAccentColor, 0.15), element.range)
        case .bullet:
            break
        case .task(let checked, _):
            if checked {
                add(.foregroundColor, mutedColor, element.content)
                add(.strikethroughStyle, NSUnderlineStyle.single.rawValue, element.content)
            }
        case .quote:
            break
        case .codeBlock:
            add(.font, mono, element.range)
        case .thematicBreak:
            break
        case .frontmatter:
            add(.font, mono, element.range)
            add(.foregroundColor, mutedColor, element.range)
        case .math:
            add(.font, mono, element.range)
        case .embed:
            break
        case .comment:
            add(.foregroundColor, Self.faded(textColor, 0.35), element.range)
        case .callout:
            addTrait(.boldFontMask, element.content)
            add(.foregroundColor, NSColor.controlAccentColor, element.content)
        case .table:
            add(.font, mono, element.range)
        case .tableBlock:
            break
        }
        // What shows while the caret is in it is syntax, not text. A
        // picture's source is all hidden, so only its markers are dimmed.
        if element.replaced != nil {
            add(.foregroundColor, mutedColor, element.range)
            if element.content != element.range { add(.foregroundColor, Self.faded(textColor, 0.85), element.content) }
        } else {
            for range in element.hidden + element.drawn { add(.foregroundColor, mutedColor, range) }
        }
        // TeX being typed is coloured as Obsidian colours it: commands red,
        // letters teal, numbers orange, brackets and scripts dimmed.
        if case .math = element.kind {
            for (range, token) in ScratchpadLiveMarkdown.mathTokens(in: storage.string, range: element.content) {
                switch token {
                case .command: add(.foregroundColor, Self.mathCommand, range)
                case .letters: add(.foregroundColor, Self.mathLetters, range)
                case .number: add(.foregroundColor, Self.mathNumber, range)
                case .punctuation: add(.foregroundColor, mutedColor, range)
                }
            }
        }
    }

    // MARK: - Revealing

    /// Shows the source where the selection is and hides it everywhere else.
    func refresh() {
        guard let textView, let layout = textView.layoutManager, let storage = textView.textStorage else { return }
        // A selection change can arrive while the storage is still mid-edit;
        // invalidating glyphs then reads offsets the layout has not caught up to.
        guard storage.editedMask.isEmpty else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        let selections = textView.selectedRanges.map(\.rangeValue)
        let nowRevealed = elements.map { ScratchpadLiveMarkdown.isRevealed($0, by: selections) }
        let formatted = MainActor.assumeIsolated { formatting(for: selections) }
        let nowHidden = formatted.hidden
        var changed = pendingInvalidation.union(nowHidden.symmetricDifference(hidden))
        // A picture that came or went changes its line's glyphs too.
        for index in Set(formatted.pictures.keys).symmetricDifference(pictures.keys) { changed.insert(index) }
        pictures = formatted.pictures
        pendingInvalidation = IndexSet()
        hidden = nowHidden
        changed.remove(integersIn: storage.length..<Int.max)
        // Whole lines, never a slice of one: a line laid out again only from
        // its hidden characters on kept glyph positions from before, and drew
        // its checkbox and strikethrough where the text no longer was.
        let text = storage.string as NSString
        var lines = IndexSet()
        for range in changed.rangeView {
            let paragraph = text.paragraphRange(for: NSRange(location: range.lowerBound, length: range.count))
            lines.insert(integersIn: paragraph.location..<NSMaxRange(paragraph))
        }
        for range in lines.rangeView {
            let characters = NSRange(location: range.lowerBound, length: range.count)
            layout.invalidateGlyphs(forCharacterRange: characters, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: characters, actualCharacterRange: nil)
            layout.invalidateDisplay(forCharacterRange: characters)
        }
        if nowRevealed != revealed {
            revealed = nowRevealed
            // Bullets, boxes and bars keep their characters for the width and
            // draw over them, so the characters themselves go clear.
            let full = NSRange(location: 0, length: storage.length)
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            for (element, isRevealed) in zip(elements, nowRevealed) where !isRevealed {
                for range in element.drawn where NSMaxRange(range) <= storage.length {
                    layout.addTemporaryAttribute(.foregroundColor, value: NSColor.clear, forCharacterRange: range)
                }
            }
        }
        textView.needsDisplay = true
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>,
                       font: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard !hidden.isEmpty || !pictures.isEmpty, glyphRange.length > 0 else { return 0 }
        let first = characterIndexes[0]
        let last = characterIndexes[glyphRange.length - 1]
        guard first <= last, hidden.intersects(integersIn: first..<(last + 1))
                || pictures.keys.contains(where: { $0 >= first && $0 <= last }) else { return 0 }
        var adjusted = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        for index in 0..<glyphRange.length {
            let character = characterIndexes[index]
            // A picture's character becomes a control glyph, which the
            // layout gives the picture's size below.
            if pictures[character] != nil {
                adjusted[index] = .controlCharacter
            } else if hidden.contains(character) {
                adjusted[index] = .null
            }
        }
        adjusted.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: characterIndexes,
                                    font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    /// A line holding a picture grows to its height; the layout leaves a
    /// control glyph's box out of the line's height.
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        guard !pictures.isEmpty else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let needed = pictures.filter { NSLocationInRange($0.key, characters) }
            .map { $0.value.size.height + ($0.value.block ? 10 : 4) }.max() ?? 0
        let extra = needed - lineFragmentRect.pointee.height
        guard extra > 0 else { return false }
        lineFragmentRect.pointee.size.height += extra
        lineFragmentUsedRect.pointee.size.height += extra
        baselineOffset.pointee += extra / 2
        return true
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        pictures[charIndex] != nil ? .whitespace : action
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       boundingBoxForControlGlyphAt glyphIndex: Int,
                       for textContainer: NSTextContainer,
                       proposedLineFragment proposedRect: NSRect,
                       glyphPosition: NSPoint,
                       characterIndex charIndex: Int) -> NSRect {
        guard let picture = pictures[charIndex] else { return .zero }
        // A block takes the rest of its line, so nothing sits beside it and
        // it can be centred in it.
        let width = picture.block
            ? max(picture.size.width, proposedRect.width - glyphPosition.x - 2 * textContainer.lineFragmentPadding)
            : picture.size.width + 2
        return NSRect(x: glyphPosition.x, y: 0, width: width, height: picture.size.height + (picture.block ? 8 : 2))
    }
}

/// Draws what stands in for syntax: a bullet's dot, a task's box, a quote's
/// bar, a rule's line and the panel behind a code block.
final class ScratchpadLiveLayoutManager: NSLayoutManager {
    weak var styler: ScratchpadLiveStyler?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let styler, let container = textContainers.first else { return }
        for element in styler.elements where element.kind == .codeBlock {
            // From the opening fence's line break: a line that starts with
            // hidden glyphs reports the line above as its first fragment.
            let start = min(element.hidden.first.map(NSMaxRange) ?? element.range.location, NSMaxRange(element.range))
            let glyphs = glyphRange(forCharacterRange: NSRange(location: start, length: NSMaxRange(element.range) - start),
                                    actualCharacterRange: nil)
            guard NSIntersectionRange(glyphs, glyphsToShow).length > 0 || glyphs.length == 0 else { continue }
            var block = NSRect.null
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in block = block.union(rect) }
            guard !block.isNull else { continue }
            let inset = container.lineFragmentPadding
            let panel = NSRect(x: block.minX + origin.x + inset - 4, y: block.minY + origin.y,
                               width: block.width - 2 * inset + 8, height: block.height)
            styler.codeBackground.setFill()
            NSBezierPath(roundedRect: panel, xRadius: 5, yRadius: 5).fill()
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let styler else { return }
        let shown = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for (character, picture) in styler.pictures where NSLocationInRange(character, shown) {
            drawPicture(picture, at: character, origin: origin)
        }
        guard styler.revealed.count == styler.elements.count else { return }
        for (element, isRevealed) in zip(styler.elements, styler.revealed) where !isRevealed {
            for range in element.drawn where NSIntersectionRange(range, shown).length > 0 {
                draw(element.kind, over: range, at: origin, styler: styler)
            }
        }
    }

    private func drawPicture(_ picture: ScratchpadLiveStyler.Picture, at character: Int, origin: NSPoint) {
        guard let storage = textStorage, character < storage.length else { return }
        let glyph = glyphIndexForCharacter(at: character)
        guard glyph < numberOfGlyphs else { return }
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let position = location(forGlyphAt: glyph)
        let size = picture.size
        var rect: NSRect
        if picture.block {
            let used = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let x = picture.centered ? used.minX + (max(used.width, size.width) - size.width) / 2
                                     : line.minX + position.x
            rect = NSRect(x: x, y: line.minY + (line.height - size.height) / 2, width: size.width, height: size.height)
        } else {
            // Centred on the middle of a lowercase letter, as text in the
            // line around a formula is.
            let font = (storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let middle = line.minY + position.y - font.xHeight / 2
            let y = min(max(line.minY, middle - size.height / 2), line.maxY - size.height)
            rect = NSRect(x: line.minX + position.x + 1, y: y, width: size.width, height: size.height)
        }
        rect = rect.offsetBy(dx: origin.x, dy: origin.y)
        picture.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: nil)
    }

    /// The rectangle `glyphs` cover on their line, measured from the glyphs'
    /// own positions. `boundingRect(forGlyphRange:in:)` reports glyphs that
    /// follow hidden ones far along the line with no width, which drew a
    /// task's box in the middle of its text.
    func span(of glyphs: NSRange) -> NSRect? {
        guard glyphs.length > 0, NSMaxRange(glyphs) <= numberOfGlyphs else { return nil }
        var lineGlyphs = NSRange()
        let line = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &lineGlyphs)
        let start = location(forGlyphAt: glyphs.location).x
        let end = NSMaxRange(glyphs) < NSMaxRange(lineGlyphs)
            ? location(forGlyphAt: NSMaxRange(glyphs)).x
            : lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil).maxX - line.minX
        return NSRect(x: line.minX + start, y: line.minY, width: max(0, end - start), height: line.height)
    }

    /// Where `range` sits, with the vertical centre of a lowercase letter on
    /// its line, which is where Obsidian centres its bullets and boxes.
    private func geometry(of range: NSRange, at origin: NSPoint) -> (rect: NSRect, line: NSRect, middle: CGFloat)? {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length else { return nil }
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard var rect = span(of: glyphs) else { return nil }
        let line = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let baseline = line.minY + location(forGlyphAt: glyphs.location).y
        let font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        rect = rect.offsetBy(dx: origin.x, dy: origin.y)
        return (rect, line.offsetBy(dx: origin.x, dy: origin.y), baseline + origin.y - font.xHeight / 2)
    }

    private func draw(_ kind: ScratchpadLiveElement.Kind, over range: NSRange,
                      at origin: NSPoint, styler: ScratchpadLiveStyler) {
        guard let place = geometry(of: range, at: origin) else { return }
        switch kind {
        case .bullet:
            let diameter = max(4, styler.baseSize * 0.36)
            styler.mutedColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: place.rect.midX - diameter / 2, y: place.middle - diameter / 2,
                                        width: diameter, height: diameter)).fill()
        case .task(let checked, _):
            let side = (styler.baseSize * 1.1).rounded()
            let configuration = NSImage.SymbolConfiguration(pointSize: side, weight: .regular)
                .applying(checked
                    ? NSImage.SymbolConfiguration(paletteColors: [.white, .controlAccentColor])
                    : NSImage.SymbolConfiguration(hierarchicalColor: styler.mutedColor))
            guard let image = NSImage(systemSymbolName: checked ? "checkmark.square.fill" : "square",
                                      accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return }
            let size = image.size
            image.draw(in: NSRect(x: place.rect.midX - size.width / 2, y: place.middle - size.height / 2,
                                  width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        case .quote:
            ScratchpadLiveStyler.faded(.controlAccentColor, 0.8).setFill()
            NSRect(x: place.rect.minX + 1, y: place.line.minY, width: 2.5, height: place.line.height).fill()
        case .thematicBreak:
            guard let container = textContainers.first else { return }
            let inset = container.lineFragmentPadding
            ScratchpadLiveStyler.faded(styler.textColor, 0.15).setFill()
            NSRect(x: place.line.minX + inset, y: place.line.midY.rounded() - 0.5,
                   width: place.line.width - 2 * inset, height: 1).fill()
        default:
            break
        }
    }
}

/// The scratchpad's editor: a plain text view on its own TextKit 1 stack, which
/// also answers a click on a drawn checkbox or a formatted link.
final class ScratchpadLiveTextView: NSTextView {
    private(set) var styler: ScratchpadLiveStyler?
    /// The text system belongs to its storage, which nothing else holds on to.
    private var liveStorage: NSTextStorage?
    var onToggleTask: ((Int) -> Void)?
    var onOpenWikilink: ((String) -> Void)?
    var wikilinkNames: (() -> [String])?
    private var pointerArea: NSTrackingArea?
    /// True while AppKit's completion list is putting a name in, so the text
    /// change that makes does not ask for the list again.
    private var insertingCompletion = false

    /// A scroll view laid out as `NSTextView.scrollableTextView()` lays one
    /// out, around the live editor.
    static func scrollable(fontSize: CGFloat, textColor: NSColor) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let storage = NSTextStorage()
        let layout = ScratchpadLiveLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: scroll.contentSize.width,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let textView = ScratchpadLiveTextView(frame: NSRect(origin: .zero, size: scroll.contentSize),
                                              textContainer: container)
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let styler = ScratchpadLiveStyler(baseSize: fontSize, textColor: textColor)
        styler.textView = textView
        storage.delegate = styler
        layout.delegate = styler
        layout.styler = styler
        textView.styler = styler
        textView.liveStorage = storage
        textView.typingAttributes = styler.baseAttributes
        scroll.documentView = textView
        return scroll
    }

    override func setSelectedRanges(_ ranges: [NSValue],
                                    affinity: NSSelectionAffinity,
                                    stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // Mid-drag the text would shift under the pointer; it settles once
        // the drag ends.
        if !stillSelecting { styler?.refresh() }
    }

    override func didChangeText() {
        super.didChangeText()
        typingAttributes = styler?.baseAttributes ?? typingAttributes
        styler?.refresh()
    }

    // MARK: - Wikilinks

    /// The note names for the `[[` the caret is in, or nil outside one.
    func wikilinkCompletions() -> [String]? {
        let caret = selectedRange()
        guard caret.length == 0, let names = wikilinkNames,
              let query = ScratchpadObsidianEditing.wikilinkQuery(in: string, caret: caret.location) else { return nil }
        return ScratchpadObsidianEditing.wikilinkCompletions(for: query.query, among: names())
    }

    /// Typing inside `[[` opens the list of notes, as Obsidian's suggester does.
    func offerWikilinkCompletions() {
        guard !insertingCompletion, window?.firstResponder === self, !hasMarkedText(),
              let names = wikilinkCompletions(), !names.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wikilinkCompletions()?.isEmpty == false else { return }
            self.complete(nil)
        }
    }

    override var rangeForUserCompletion: NSRange {
        let caret = selectedRange()
        if caret.length == 0,
           let query = ScratchpadObsidianEditing.wikilinkQuery(in: string, caret: caret.location) {
            return query.range
        }
        return super.rangeForUserCompletion
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange,
                                   movement: Int, isFinal flag: Bool) {
        insertingCompletion = true
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        insertingCompletion = false
        // Chosen with Return or Tab: the caret steps out past the `]]`.
        guard flag, movement == NSReturnTextMovement || movement == NSTabTextMovement else { return }
        let text = string as NSString
        let caret = selectedRange().location
        if caret + 2 <= text.length, text.substring(with: NSRange(location: caret, length: 2)) == "]]" {
            setSelectedRange(NSRange(location: caret + 2, length: 0))
        }
    }

    /// Command-Return on a link or wikilink opens it; false when the caret
    /// is on neither.
    func followLinkAtCaret() -> Bool {
        guard let styler else { return false }
        let caret = selectedRange().location
        for element in styler.elements where element.range.location <= caret && caret <= NSMaxRange(element.range) {
            switch element.kind {
            case .link(let address):
                if let url = URL(string: address), url.scheme != nil { NSWorkspace.shared.open(url) }
                return true
            case .wikilink(let name):
                onOpenWikilink?(name)
                return true
            default:
                continue
            }
        }
        return false
    }

    // MARK: - Clicks

    private enum Target {
        case task(Int)
        case link(String)
        case wikilink(String)
    }

    /// What a click at `point` acts on: a drawn box, or the text of a link
    /// that is showing formatted rather than as source.
    private func target(at point: NSPoint) -> Target? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
              let styler, storage.length > 0, styler.revealed.count == styler.elements.count else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: inContainer, in: container, fractionOfDistanceThroughGlyph: nil)
        guard glyph < layout.numberOfGlyphs,
              let rect = (layout as? ScratchpadLiveLayoutManager)?.span(of: NSRange(location: glyph, length: 1)),
              rect.insetBy(dx: -2, dy: 0).contains(inContainer) else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        for (element, isRevealed) in zip(styler.elements, styler.revealed) where !isRevealed {
            switch element.kind {
            case .task(_, let box) where element.drawn.contains(where: { NSLocationInRange(character, $0) }):
                return .task(box)
            case .link(let url) where NSLocationInRange(character, element.content):
                return .link(url)
            case .wikilink(let name) where NSLocationInRange(character, element.content):
                return .wikilink(name)
            default:
                continue
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1,
              let target = target(at: convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
        switch target {
        case .task(let box):
            onToggleTask?(box)
            styler?.refresh()
        case .link(let address):
            if let url = URL(string: address), url.scheme != nil { NSWorkspace.shared.open(url) }
        case .wikilink(let name):
            onOpenWikilink?(name)
        }
    }

    /// NSTextView puts its I-beam back on every move over editable text,
    /// past any cursor rect, so the hand over a box or link is set here.
    private func pointer(for event: NSEvent) -> Bool {
        guard target(at: convert(event.locationInWindow, from: nil)) != nil else { return false }
        NSCursor.pointingHand.set()
        return true
    }

    override func cursorUpdate(with event: NSEvent) {
        if !pointer(for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        if !pointer(for: event) { super.mouseMoved(with: event) }
    }

    /// The area added last time goes before the next one, or they pile up and
    /// each move runs the hit test once per area.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }
}
