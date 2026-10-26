// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's Obsidian editor answers Obsidian's keys and draws what
/// Obsidian draws: each key is one text edit, and math, tables and embeds
/// stand on one character whose source comes back under the caret.
enum ScratchpadObsidianEditingTests {
    static func run(_ suite: TestSuite) {
        typealias Editing = ScratchpadObsidianEditing
        func applied(_ edit: ScratchpadMarkEdit?, to text: String) -> String {
            guard let edit else { return text }
            return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
        func key(_ character: String, shift: Bool = false) -> Editing.Command? {
            Editing.command(charactersIgnoringModifiers: character, command: true, shift: shift,
                            option: false, control: false)
        }

        suite.run("obsidian editor maps Obsidian's default hotkeys") {
            suite.expect(key("b") == .mark(.bold), "Command-B bold")
            suite.expect(key("i") == .mark(.italic), "Command-I italic")
            suite.expect(key("k") == .mark(.link), "Command-K link")
            suite.expect(key("l") == .toggleChecklist, "Command-L checkbox")
            suite.expect(key("d") == .deleteLine, "Command-D delete paragraph")
            suite.expect(key("]") == .indent, "Command-] indent")
            suite.expect(key("[") == .outdent, "Command-[ unindent")
            suite.expect(key("/") == .wrap("%%"), "Command-/ comment")
            suite.expect(key("e") == .toggleReading, "Command-E reading view")
            suite.expect(key("m", shift: true) == .wrap("$"), "Shift-Command-M math")
            suite.expect(Editing.command(charactersIgnoringModifiers: "b", command: true, shift: false,
                                         option: true, control: false) == nil, "Option leaves the key alone")
            suite.expect(Editing.command(charactersIgnoringModifiers: "b", command: false, shift: false,
                                         option: false, control: false) == nil, "plain typing is not a command")
        }

        suite.run("obsidian editor indents, checks and deletes lines") {
            let indent = Editing.edit(for: .indent, in: "plain line", selection: NSRange(location: 3, length: 0))
            suite.expect(applied(indent, to: "plain line") == "\tplain line", "Command-] indents a line that is not a list")
            suite.expect(indent?.selection == NSRange(location: 4, length: 0), "caret moves with its text")
            let outdent = Editing.edit(for: .outdent, in: "\t\tx", selection: NSRange(location: 2, length: 0))
            suite.expect(applied(outdent, to: "\t\tx") == "\tx", "Command-[ takes one level off")

            func check(_ text: String) -> String {
                applied(Editing.edit(for: .toggleChecklist, in: text, selection: NSRange(location: (text as NSString).length, length: 0)), to: text)
            }
            suite.expect(check("buy milk") == "- [ ] buy milk", "a plain line becomes a task")
            suite.expect(check("- buy milk") == "- [ ] buy milk", "a bullet gains a box")
            suite.expect(check("- [ ] buy milk") == "- [x] buy milk", "an open box is checked")
            suite.expect(check("- [x] buy milk") == "- [ ] buy milk", "a checked box opens again")
            suite.expect(check("\t1. step") == "\t1. [ ] step", "a numbered item keeps its number and indent")
            let caret = Editing.edit(for: .toggleChecklist, in: "abc", selection: NSRange(location: 1, length: 0))
            suite.expect(caret?.selection == NSRange(location: 7, length: 0), "caret stays on its letter")

            let text = "one\ntwo\nthree"
            let middle = Editing.edit(for: .deleteLine, in: text, selection: NSRange(location: 5, length: 0))
            suite.expect(applied(middle, to: text) == "one\nthree", "Command-D deletes the line and its break")
            let last = Editing.edit(for: .deleteLine, in: text, selection: NSRange(location: 10, length: 0))
            suite.expect(applied(last, to: text) == "one\ntwo", "the last line takes the break before it")
        }

        suite.run("obsidian editor pairs brackets and wraps selections") {
            let open = Editing.typingEdit("(", in: "a ", selection: NSRange(location: 2, length: 0))
            suite.expect(applied(open, to: "a ") == "a ()" && open?.selection == NSRange(location: 3, length: 0),
                         "a bracket opens with its closer")
            suite.expect(Editing.typingEdit("(", in: "word", selection: NSRange(location: 0, length: 0)) == nil,
                         "no partner in front of a word")
            let wiki = Editing.typingEdit("[", in: "[]", selection: NSRange(location: 1, length: 0))
            suite.expect(applied(wiki, to: "[]") == "[[]]", "a second [ makes a wikilink's brackets")
            let over = Editing.typingEdit("]", in: "[x]", selection: NSRange(location: 2, length: 0))
            suite.expect(applied(over, to: "[x]") == "[x]" && over?.selection == NSRange(location: 3, length: 0),
                         "typing the closer steps over it")
            let wrap = Editing.typingEdit("=", in: "mark me", selection: NSRange(location: 5, length: 2))
            suite.expect(applied(wrap, to: "mark me") == "mark =me=", "a marker wraps the selection")
            suite.expect(Editing.typingEdit("a", in: "x", selection: NSRange(location: 0, length: 1)) == nil,
                         "letters still replace a selection")
            let back = Editing.deletePairEdit(in: "f()", selection: NSRange(location: 2, length: 0))
            suite.expect(applied(back, to: "f()") == "f", "Backspace in an empty pair takes both")

            let highlight = Editing.edit(for: .wrap("=="), in: "so bright", selection: NSRange(location: 3, length: 6))
            suite.expect(applied(highlight, to: "so bright") == "so ==bright==", "highlight wraps")
            let undone = Editing.edit(for: .wrap("=="), in: "so ==bright==", selection: NSRange(location: 5, length: 6))
            suite.expect(applied(undone, to: "so ==bright==") == "so bright", "and a second press unwraps")
        }

        suite.run("obsidian editor completes wikilinks from the caret") {
            let query = Editing.wikilinkQuery(in: "see [[Proj", caret: 10)
            suite.expect(query?.query == "Proj" && query?.range == NSRange(location: 6, length: 4), "query after [[")
            suite.expect(Editing.wikilinkQuery(in: "see [[Done]] x", caret: 14) == nil, "closed links are not completed")
            suite.expect(Editing.wikilinkQuery(in: "[[a|b", caret: 5) == nil, "the alias is not a note name")
            let names = Editing.wikilinkCompletions(for: "pro", among: ["Todo", "Improve", "Projects", "projects"])
            suite.expect(names.first?.lowercased() == "projects" && names.last == "Improve",
                         "names starting with the query come before names containing it")
        }

        suite.run("obsidian editor draws math, tables, embeds and callouts") {
            func elements(_ text: String) -> [ScratchpadLiveElement] { ScratchpadLiveMarkdown.elements(in: text) }
            let inline = elements("so $E = mc^2$ ok").first { if case .math = $0.kind { return true }; return false }
            suite.expect(inline?.kind == .math(tex: "E = mc^2", display: false), "inline math")
            suite.expect(inline?.replaced == NSRange(location: 3, length: 1), "stands on its opening $")
            suite.expect(!elements("costs $5 and $10").contains { if case .math = $0.kind { return true }; return false },
                         "prices are not math")
            suite.expect(!elements("`$x$`").contains { if case .math = $0.kind { return true }; return false },
                         "code keeps its dollars")
            suite.expect(!elements("$a_b_c$").contains { $0.kind == .italic }, "underscores in math are not italics")
            let block = elements("$$\n\\frac{1}{2}\n$$\nafter")
            suite.expect(block.first?.kind == .math(tex: "\\frac{1}{2}", display: true), "a $$ block")
            let hidden = ScratchpadLiveMarkdown.hiddenCharacters(in: block, selections: [])
            suite.expect(hidden.count == 16, "everything but its first character hides")
            let notReady = ScratchpadLiveMarkdown.hiddenCharacters(in: block, selections: []) { _ in false }
            suite.expect(notReady.isEmpty, "a formula not typeset yet keeps its source")
            let revealed = ScratchpadLiveMarkdown.hiddenCharacters(in: block, selections: [NSRange(location: 4, length: 0)])
            suite.expect(revealed.isEmpty, "the caret in it shows the source")

            let table = elements("| a | b |\n|---|:-:|\n| 1 | x\\|y |\nnext")
            suite.expect(table.first?.kind == .tableBlock(rows: [["a", "b"], ["1", "x|y"]]), "a table's cells")
            suite.expect(elements("| not | a table |").allSatisfy { if case .tableBlock = $0.kind { return false }; return true },
                         "a row without a delimiter stays text")

            suite.expect(elements("![[photo.png]]").first?.kind == .embed(target: "photo.png"), "image embed")
            suite.expect(elements("![[Other note]]").contains { $0.kind == .wikilink(target: "Other note") },
                         "a note embed stays a link")
            suite.expect(elements("![alt](pics/a%20b.jpg)").first?.kind == .embed(target: "pics/a b.jpg"),
                         "Markdown image")
            let callout = elements("> [!warning] Careful")
            suite.expect(callout.contains { $0.kind == .callout(type: "warning") }, "callout")
            suite.expect(elements("a %%hidden%% b").contains { $0.kind == .comment }, "comment")
            suite.expect(elements("go to https://example.com/x.").contains { $0.kind == .link(url: "https://example.com/x") },
                         "bare URL, without its full stop")
        }
    }
}
