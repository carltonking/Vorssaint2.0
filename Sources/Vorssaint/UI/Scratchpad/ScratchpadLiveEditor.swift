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

    init(baseSize: CGFloat, textColor: NSColor) {
        self.baseSize = baseSize
        self.textColor = textColor
    }

    var baseFont: NSFont { .systemFont(ofSize: baseSize) }
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
        hidden = ScratchpadLiveMarkdown.hiddenCharacters(in: elements, selections: selections)
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
        }
        // What shows while the caret is in it is syntax, not text.
        for range in element.hidden + element.drawn { add(.foregroundColor, mutedColor, range) }
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
        let nowHidden = ScratchpadLiveMarkdown.hiddenCharacters(in: elements, selections: selections)
        var changed = pendingInvalidation.union(nowHidden.symmetricDifference(hidden))
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
        guard !hidden.isEmpty, glyphRange.length > 0 else { return 0 }
        let first = characterIndexes[0]
        let last = characterIndexes[glyphRange.length - 1]
        guard first <= last, hidden.intersects(integersIn: first..<(last + 1)) else { return 0 }
        var adjusted = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        for index in 0..<glyphRange.length where hidden.contains(characterIndexes[index]) {
            adjusted[index] = .null
        }
        adjusted.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: characterIndexes,
                                    font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
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
        guard let styler, styler.revealed.count == styler.elements.count else { return }
        let shown = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for (element, isRevealed) in zip(styler.elements, styler.revealed) where !isRevealed {
            for range in element.drawn where NSIntersectionRange(range, shown).length > 0 {
                draw(element.kind, over: range, at: origin, styler: styler)
            }
        }
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
    private var pointerArea: NSTrackingArea?

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
