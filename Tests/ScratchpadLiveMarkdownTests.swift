// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The live editor draws Markdown the way Obsidian's Live Preview does: what
/// is hidden has to be exactly the syntax, never the text, and the source has
/// to come back wherever the caret is, or the caret would sit on characters
/// nobody can see.
enum ScratchpadLiveMarkdownTests {
    static func run(_ suite: TestSuite) {
        func visible(_ text: String, caret: Int?) -> String {
            let elements = ScratchpadLiveMarkdown.elements(in: text)
            let selections = caret.map { [NSRange(location: $0, length: 0)] } ?? []
            let hidden = ScratchpadLiveMarkdown.hiddenCharacters(in: elements, selections: selections)
            let units = Array(text.utf16).enumerated().filter { !hidden.contains($0.offset) }.map(\.element)
            return String(utf16CodeUnits: units, count: units.count)
        }
        func kinds(_ text: String) -> [ScratchpadLiveElement.Kind] {
            ScratchpadLiveMarkdown.elements(in: text).map(\.kind)
        }

        suite.run("scratchpad live markdown hides syntax away from the caret") {
            suite.expect(visible("# Title", caret: nil) == "Title", "heading marker hidden")
            suite.expect(visible("# Title", caret: 3) == "# Title", "heading source on its own line")
            suite.expect(visible("a **b** c", caret: 0) == "a b c", "bold markers hidden")
            suite.expect(visible("a **b** c", caret: 2) == "a **b** c", "bold source with the caret at its edge")
            suite.expect(visible("*i* and _j_", caret: nil) == "i and j", "both italics hidden")
            suite.expect(visible("~~x~~ ==y==", caret: nil) == "x y", "strikethrough and highlight")
            suite.expect(visible("`a*b*c`", caret: nil) == "a*b*c", "code span keeps its stars as text")
            suite.expect(visible("[site](https://example.com)", caret: nil) == "site", "link shows its text")
            suite.expect(visible("see [[Other note]]", caret: 0) == "see Other note", "wikilink drops brackets")
            suite.expect(visible("[[Other note|alias]]", caret: nil) == "alias", "wikilink alias replaces target")
            suite.expect(visible(#"\*not italic\*"#, caret: nil) == #"\*not italic\*"#, "escaped stars stay")
            suite.expect(visible("snake_case_name", caret: nil) == "snake_case_name", "intraword underscores stay")
        }

        suite.run("scratchpad live markdown nests marks") {
            suite.expect(visible("***both***", caret: nil) == "both", "bold italic hides all six stars")
            suite.expect(visible("**bold *and italic***", caret: nil) == "bold and italic",
                         "italic inside bold")
            let marks = kinds("***both***")
            suite.expect(marks.contains(.bold) && marks.contains(.italic), "bold italic is both")
        }

        suite.run("scratchpad live markdown lists and tasks") {
            suite.expect(visible("- [ ] buy milk", caret: nil) == "[ ] buy milk",
                         "task bullet hidden, box kept for its drawn checkbox")
            suite.expect(visible("- [ ] buy milk", caret: 0) == "- [ ] buy milk", "task source at its marker")
            suite.expect(visible("- [ ] buy milk", caret: 6) == "[ ] buy milk",
                         "caret in the task's text keeps the box drawn")
            suite.expect(kinds("- [x] done") == [.task(checked: true, box: 2)], "checked task names its box")
            suite.expect(kinds("  * item") == [.bullet], "indented bullet")
            suite.expect(kinds("---") == [.thematicBreak], "rule, not a bullet")
            suite.expect(kinds("> quoted") == [.quote], "quote")
            suite.expect(kinds("#tag and #2024") == [.tag], "a tag needs a non-digit")
        }

        suite.run("scratchpad live markdown blocks") {
            let fenced = "```swift\nlet a = **b**\n```\nafter **c**"
            let elements = ScratchpadLiveMarkdown.elements(in: fenced)
            suite.expect(elements.first?.kind == .codeBlock, "fenced block found")
            suite.expect(elements.filter { $0.kind == .bold }.count == 1, "no inline marks inside code")
            suite.expect(visible(fenced, caret: nil) == "\nlet a = **b**\n\nafter c",
                         "fences hidden while the caret is outside the block")
            suite.expect(kinds("```\nunclosed") == [.codeBlock], "unclosed fence runs to the end")
            suite.expect(kinds("---\ntags: a\n---\n# H").first == .frontmatter, "frontmatter on the first line")
            suite.expect(!kinds("text\n---\nmore").contains(.frontmatter), "rule later is not frontmatter")
            suite.expect(kinds("###### six") == [.heading(level: 6)], "six levels")
            suite.expect(kinds("####### seven").isEmpty, "seven is a paragraph")
            suite.expect(kinds("#nospace") == [.tag], "no space is a tag, not a heading")
        }

        suite.run("scratchpad live markdown list indent") {
            func indent(_ text: String, _ caret: Int, outdent: Bool = false) -> (String, Int)? {
                guard let edit = ScratchpadLiveMarkdown.listIndentEdit(
                    in: text, selection: NSRange(location: caret, length: 0), outdent: outdent) else { return nil }
                return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement),
                        edit.selection.location)
            }
            let nested = indent("- a\n- b", 7)
            suite.expect(nested?.0 == "- a\n\t- b" && nested?.1 == 8, "tab nests the item under the caret")
            let back = indent("- a\n\t- b", 8, outdent: true)
            suite.expect(back?.0 == "- a\n- b" && back?.1 == 7, "shift-tab un-nests it")
            suite.expect(indent("plain", 2) == nil, "tab outside a list is an ordinary tab")
            suite.expect(indent("- a", 3, outdent: true) == nil, "nothing to un-nest leaves the key alone")
            let spaces = indent("    1. x", 8, outdent: true)
            suite.expect(spaces?.0 == "1. x" && spaces?.1 == 4, "four spaces are one level")
        }
    }
}
