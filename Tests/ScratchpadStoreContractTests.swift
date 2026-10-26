// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VMStatisticsCompat

enum ScratchpadStoreContractTests {
    static func run(_ suite: TestSuite) {
        ScratchpadExportContract.run(suite)
        ScratchpadSaveContract.run(suite)
        let manager = FileManager.default
        let now = Date(timeIntervalSince1970: 1_784_000_000)

        func fixture(_ check: (URL, UserDefaults, inout ScratchpadStore) throws -> Void) {
            let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let vault = root.appendingPathComponent("Vault")
            let container = root.appendingPathComponent("Container")
            let suiteName = "com.vorssaint.tests.scratchpad.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer {
                try? manager.removeItem(at: root)
                defaults.removePersistentDomain(forName: suiteName)
            }
            do {
                try manager.createDirectory(at: vault, withIntermediateDirectories: true)
                try manager.createDirectory(at: container, withIntermediateDirectories: true)
                var store = ScratchpadStore(vaultURL: vault,
                                            defaults: defaults,
                                            privateContainerURL: container)
                try check(vault, defaults, &store)
            } catch {
                suite.expect(false, "scratchpad vault fixture completes: \(error)")
            }
        }

        suite.expect(ScratchpadVaultSupport.sanitizedFileStem("  Work/Ideas: 1  ") == "Work-Ideas- 1"
                && ScratchpadVaultSupport.sanitizedFileStem("...") == "Note"
                && ScratchpadVaultSupport.sanitizedFileStem(String(repeating: "x", count: 60)).count
                    == ScratchpadDocument.maximumNameLength,
               "note file names stay one line, safe for the vault and bounded")
        let pathVault = URL(fileURLWithPath: "/tmp/Vault", isDirectory: true)
        suite.expect(ScratchpadVaultSupport.relativePath(
                of: URL(fileURLWithPath: "/tmp/Vault/Notes/Today.md"), in: pathVault) == "Notes/Today.md"
                && ScratchpadVaultSupport.relativePath(
                    of: URL(fileURLWithPath: "/tmp/Vault/Notes/Today.txt"), in: pathVault) == nil
                && ScratchpadVaultSupport.relativePath(
                    of: URL(fileURLWithPath: "/tmp/Other/Today.md"), in: pathVault) == nil
                && ScratchpadVaultSupport.fileURL(forRelativePath: "../Other.md", in: pathVault) == nil
                && ScratchpadVaultSupport.fileURL(forRelativePath: "/etc/passwd.md", in: pathVault) == nil,
               "only Markdown files inside the chosen vault can become notes")

        fixture { vault, _, store in
            for path in ["b.md", "A note.md", "Projects/Plan.md", "Projects/Deep/Idea.md", "Empty/readme.txt",
                         ".obsidian/workspace.md", "image.png", "10 Later.md", "2 Soon.md"] {
                let url = vault.appendingPathComponent(path)
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "x".write(to: url, atomically: true, encoding: .utf8)
            }
            let tree = ScratchpadVaultSupport.noteTree(in: vault)
            suite.expect(tree.map(\.name) == ["Projects", "2 Soon", "10 Later", "A note", "b"],
                   "the note list puts folders first, sorts as Finder does, and skips hidden, empty and non-Markdown entries")
            suite.expect(tree.first?.children?.map(\.name) == ["Deep", "Plan"]
                    && tree.first?.children?.first?.children?.map(\.path) == ["Projects/Deep/Idea.md"],
                   "folders nest with each note's path relative to the vault")
            _ = try store.load()
            let listed = tree.first { $0.name == "A note" }!
            let opened = ScratchpadVaultSupport.fileURL(forRelativePath: listed.path, in: vault)
                .flatMap { store.openNote(at: $0, in: store.lastSavedDocument!) }
            suite.expect(opened?.pads.last?.path == "A note.md" && opened?.selectedID == opened?.pads.last?.id,
                   "a note picked from the list opens as the selected tab")
        }

        fixture { vault, defaults, _ in
            defaults.set(vault.path, forKey: DefaultsKey.scratchpadVaultPath)
            suite.expect(ScratchpadVaultSupport.resolvedVaultURL(defaults: defaults)?.path == vault.path,
                   "the chosen vault is found again from its stored path")
            defaults.removeObject(forKey: DefaultsKey.scratchpadVaultPath)
            suite.expect(ScratchpadVaultSupport.resolvedVaultURL(defaults: defaults) == nil,
                   "without a vault or bookmark there is nowhere to keep notes")
        }

        fixture { vault, _, store in
            suite.expect(!store.save(ScratchpadDocument.initial(defaultName: "Scratchpad")),
                   "a note cannot be saved before the vault has been read")
            let loaded = try store.load()
            let firstURL = vault.appendingPathComponent("Todo.md")
            suite.expect(loaded.pads.count == 1
                    && loaded.pads[0].name == "Todo"
                    && loaded.pads[0].path == "Todo.md"
                    && manager.fileExists(atPath: firstURL.path),
                   "a vault with no open notes opens its Todo.md, creating it when missing")
            var edited = loaded
            edited.updateSelectedText("# First note", modifiedAt: now)
            suite.expect(store.save(edited)
                    && (try? String(contentsOf: firstURL, encoding: .utf8)) == "# First note",
                   "typing writes the note straight into its Markdown file")
            let reopened = try store.load()
            suite.expect(reopened.pads.map(\.text) == ["# First note"],
                   "the open note comes back from the file")
        }

        fixture { vault, _, store in
            let loaded = try store.load()
            guard let withSecond = store.createNote(named: "Ideas", in: loaded) else {
                suite.expect(false, "a new note is created")
                return
            }
            let secondURL = vault.appendingPathComponent("Ideas.md")
            suite.expect(withSecond.pads.map(\.name) == ["Todo", "Ideas"]
                    && withSecond.selectedID == withSecond.pads[1].id
                    && manager.fileExists(atPath: secondURL.path),
                   "a new tab is a new note file in the vault")
            var edited = withSecond
            edited.pads[1].text = "Second"
            suite.expect(store.save(edited), "the second note's text reaches its file")
            guard let renamed = store.renameNote(edited.pads[1].id, to: "Plans", in: edited) else {
                suite.expect(false, "a note is renamed")
                return
            }
            let renamedURL = vault.appendingPathComponent("Plans.md")
            suite.expect(renamed.pads[1].name == "Plans"
                    && renamed.pads[1].path == "Plans.md"
                    && !manager.fileExists(atPath: secondURL.path)
                    && (try? String(contentsOf: renamedURL, encoding: .utf8)) == "Second",
                   "renaming a tab renames its file and keeps the text")
            suite.expect(store.renameNote(renamed.pads[1].id, to: "Todo", in: renamed) == nil
                    && manager.fileExists(atPath: renamedURL.path),
                   "a name already in the vault cannot be taken")
            guard let closed = store.closeNote(renamed.pads[1].id, in: renamed) else {
                suite.expect(false, "a note is closed")
                return
            }
            suite.expect(closed.pads.count == 1
                    && manager.fileExists(atPath: renamedURL.path),
                   "closing a tab leaves the note file in the vault")
            suite.expect(store.closeNote(closed.pads[0].id, in: closed) == nil,
                   "the last open note cannot be closed")
        }

        fixture { vault, _, store in
            let notes = vault.appendingPathComponent("Notes")
            try manager.createDirectory(at: notes, withIntermediateDirectories: true)
            let noteURL = notes.appendingPathComponent("Existing.md")
            try "# Existing".write(to: noteURL, atomically: true, encoding: .utf8)
            try "ignore".write(to: notes.appendingPathComponent("Scan.txt"),
                               atomically: true, encoding: .utf8)
            let loaded = try store.load()
            guard let opened = store.openNote(at: noteURL, in: loaded) else {
                suite.expect(false, "an existing vault note opens")
                return
            }
            suite.expect(opened.pads.contains { $0.path == "Notes/Existing.md"
                    && $0.name == "Existing" && $0.text == "# Existing" },
                   "any Markdown file in the vault can be read in the pad")
            suite.expect(store.openNote(at: notes.appendingPathComponent("Scan.txt"),
                                        in: opened) == nil,
                   "a text file that is not Markdown cannot be opened")
            let outside = manager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
            try "outside".write(to: outside, atomically: true, encoding: .utf8)
            defer { try? manager.removeItem(at: outside) }
            suite.expect(store.openNote(at: outside, in: opened) == nil,
                   "a Markdown file outside the chosen vault cannot be opened")
            let reopened = try store.load()
            suite.expect(reopened.pads.map(\.path) == opened.pads.map(\.path),
                   "the open notes and their order come back after reopening")
        }

        fixture { vault, _, store in
            let loaded = try store.load()
            let url = vault.appendingPathComponent(loaded.pads[0].path)
            try "From Obsidian".write(to: url, atomically: true, encoding: .utf8)
            var edited = loaded
            edited.updateSelectedText("Typed here", modifiedAt: now)
            suite.expect(!store.save(edited)
                    && (try? String(contentsOf: url, encoding: .utf8)) == "From Obsidian",
                   "an autosave never overwrites a note Obsidian changed meanwhile")
            let reloaded = try store.load()
            suite.expect(reloaded.pads[0].text == "From Obsidian",
                   "reopening the pad shows the text Obsidian wrote")
        }

        fixture { vault, _, store in
            let loaded = try store.load()
            guard let both = store.createNote(named: "Ideas", in: loaded) else {
                suite.expect(false, "a second note is created")
                return
            }
            let todoURL = vault.appendingPathComponent("Todo.md")
            let ideasURL = vault.appendingPathComponent("Ideas.md")
            try "Synced by iCloud".write(to: ideasURL, atomically: true, encoding: .utf8)
            var edited = both
            edited.pads[0].text = "- [ ] milk"
            suite.expect(store.save(edited)
                    && (try? String(contentsOf: todoURL, encoding: .utf8)) == "- [ ] milk"
                    && (try? String(contentsOf: ideasURL, encoding: .utf8)) == "Synced by iCloud",
                   "a note rewritten outside while its tab sat unedited is not a failed save of the others")
        }

        fixture { vault, _, store in
            let loaded = try store.load()
            guard let both = store.createNote(named: "Ideas", in: loaded) else {
                suite.expect(false, "a second note is created")
                return
            }
            let todoURL = vault.appendingPathComponent("Todo.md")
            let ideasURL = vault.appendingPathComponent("Ideas.md")
            try "From Obsidian".write(to: ideasURL, atomically: true, encoding: .utf8)
            var edited = both
            edited.pads[1].text = "Typed here"
            suite.expect(!store.save(edited)
                    && (try? String(contentsOf: ideasURL, encoding: .utf8)) == "From Obsidian",
                   "typing over a note Obsidian changed meanwhile is still refused")
            edited.pads[0].text = "Later edit"
            edited.pads[1].text = both.pads[1].text
            suite.expect(store.save(edited)
                    && (try? String(contentsOf: todoURL, encoding: .utf8)) == "Later edit",
                   "one refused note does not make later edits of another note fail")
        }

        fixture { vault, _, store in
            let todoURL = vault.appendingPathComponent("Todo.md")
            try "- [ ] milk".write(to: todoURL, atomically: true, encoding: .utf8)
            let loaded = try store.load()
            suite.expect(loaded.pads.map(\.text) == ["- [ ] milk"]
                    && (try? String(contentsOf: todoURL, encoding: .utf8)) == "- [ ] milk",
                   "an existing Todo.md opens as it is instead of being replaced")
        }

        fixture { vault, defaults, _ in
            let root = vault.deletingLastPathComponent()
            let other = root.appendingPathComponent("Other")
            let outside = root.appendingPathComponent("Loose")
            try manager.createDirectory(at: other, withIntermediateDirectories: true)
            try manager.createDirectory(at: outside, withIntermediateDirectories: true)
            let inside = vault.appendingPathComponent("Inside.md")
            let loose = outside.appendingPathComponent("Loose.md")
            try "in".write(to: inside, atomically: true, encoding: .utf8)
            try "out".write(to: loose, atomically: true, encoding: .utf8)
            defaults.set(["Todo.md"], forKey: DefaultsKey.scratchpadOpenNotes)
            let folder = ScratchpadVaultSupport.adoptLocation(other, currentVault: vault, defaults: defaults)
            suite.expect(folder?.path == other.standardizedFileURL.path
                    && defaults.stringArray(forKey: DefaultsKey.scratchpadOpenNotes) == [],
                   "a chosen folder becomes the vault and lets go of the old vault's tabs")
            defaults.set(["Todo.md"], forKey: DefaultsKey.scratchpadOpenNotes)
            let same = ScratchpadVaultSupport.adoptLocation(inside, currentVault: vault, defaults: defaults)
            suite.expect(same?.path == vault.standardizedFileURL.path
                    && defaults.stringArray(forKey: DefaultsKey.scratchpadOpenNotes) == ["Todo.md", "Inside.md"]
                    && defaults.string(forKey: DefaultsKey.scratchpadSelectedNote) == "Inside.md",
                   "a note inside the vault opens in place as the selected tab")
            let parent = ScratchpadVaultSupport.adoptLocation(loose, currentVault: vault, defaults: defaults)
            suite.expect(parent?.path == outside.standardizedFileURL.path
                    && defaults.stringArray(forKey: DefaultsKey.scratchpadOpenNotes) == ["Loose.md"],
                   "a note outside the vault opens in place with its folder as the vault")
        }

        fixture { vault, defaults, store in
            let legacyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
            let legacy = """
            {"pads":[{"id":"\(legacyID.uuidString)","name":"Old note","text":"Remember this"}],"selectedID":"\(legacyID.uuidString)"}
            """
            defaults.set(Data(legacy.utf8), forKey: DefaultsKey.scratchpadDocument)
            suite.expect(store.importLegacyNotes(defaultName: "Scratchpad") == 1
                    && (try? String(contentsOf: vault.appendingPathComponent("Old note.md"),
                                    encoding: .utf8)) == "Remember this"
                    && defaults.stringArray(forKey: DefaultsKey.scratchpadOpenNotes) == ["Old note.md"]
                    && defaults.bool(forKey: DefaultsKey.scratchpadLegacyImported),
                   "the old private notes are imported once as Markdown files")
            suite.expect(defaults.data(forKey: DefaultsKey.scratchpadDocument) == Data(legacy.utf8),
                   "leftover private notes stay untouched as a fallback")
            suite.expect(store.importLegacyNotes(defaultName: "Scratchpad") == 0,
                   "the same private notes are not imported twice")
        }

        fixture { vault, _, store in
            let legacyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
            let legacy = """
            {"pads":[{"id":"\(legacyID.uuidString)","name":"Private pad","text":"From the container"}],"selectedID":"\(legacyID.uuidString)"}
            """
            guard let container = store.privateContainerURL else {
                suite.expect(false, "the private container is available to import")
                return
            }
            try Data(legacy.utf8).write(to: container.appendingPathComponent("Scratchpad.json"))
            suite.expect(store.importLegacyNotes(defaultName: "Scratchpad") == 1
                    && (try? String(contentsOf: vault.appendingPathComponent("Private pad.md"),
                                    encoding: .utf8)) == "From the container"
                    && manager.fileExists(atPath: container.appendingPathComponent("Scratchpad.json").path),
                   "notes kept in the private container are imported and their original is kept")
        }

        fixture { _, defaults, _ in
            var unavailable = ScratchpadStore(vaultURL: nil, defaults: defaults)
            suite.expect((try? unavailable.load()) == nil
                    && !unavailable.save(ScratchpadDocument.initial(defaultName: "Scratchpad"))
                    && defaults.stringArray(forKey: DefaultsKey.scratchpadOpenNotes) == nil,
                   "no vault means no note is read or written")
        }
    }
}

/// The production export method runs against inert window and panel doubles.
/// No system dialog opens, and writes stay inside a disposable directory.
enum ScratchpadExportContract {
    final class Window {
        struct Level { let rawValue: Int }
        var level = Level(rawValue: 26)
        var isVisible = true
        var focusCount = 0
        func makeKey() { focusCount += 1 }
    }
    final class Application {
        var keyWindow: Window?
        var currentEvent: Event?
        struct Event { let window: Window? }
        func activate(ignoringOtherApps: Bool) {}
    }
    final class Panel {
        static var latest: Panel?
        var allowedContentTypes: [UTType] = []
        var canCreateDirectories = false
        var isExtensionHidden = true
        var nameFieldStringValue = ""
        var url: URL?
        var parent: Window?
        var level = Window.Level(rawValue: 0)
        var hidesOnDeactivate = true
        var standalone = false
        var focused = false
        var modalCalls = 0
        var response: NSApplication.ModalResponse = .cancel
        var completion: ((NSApplication.ModalResponse) -> Void)?
        init() { Self.latest = self }
        func runModal() -> NSApplication.ModalResponse { modalCalls += 1; return response }
        func beginSheetModal(for parent: Window,
                             completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            self.parent = parent
            completion = completionHandler
        }
        func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            standalone = true
            completion = completionHandler
        }
        func makeKeyAndOrderFront(_ sender: Any?) { focused = true }
        func finish(_ response: NSApplication.ModalResponse) {
            let callback = completion
            completion = nil
            callback?(response)
        }
    }
    enum Queue {
        static var main: Queue.Type { Self.self }
        static var jobs: [() -> Void] = []
        static func async(execute action: @escaping () -> Void) { jobs.append(action) }
        static func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    final class Island {
        static let shared = Island()
        var presentationWindow: Window?
    }
    enum HUD {
        static var errors = 0
        static func show(icon: String, message: String) { errors += 1 }
    }
    class Fixture {
        typealias NSSavePanel = Panel
        typealias NSWindow = Window
        typealias DispatchQueue = Queue
        typealias NotchService = Island
        typealias QuickToolHUD = HUD
        static let padID = UUID()
        var NSApp = Application()
        var panel: Window?
        var document: ScratchpadDocument? = ScratchpadDocument.initial(
            defaultName: "Notes", id: Fixture.padID, text: "Notes to export")
        var selectedPadID: UUID? = Fixture.padID
        /// Like the service, every edit lands in the document's selected pad.
        var text = "Notes to export" {
            didSet { document?.updateSelectedText(text, modifiedAt: Date()) }
        }
        var modalInteractionActive = false
        var flushes = 0
        func flushSave() { flushes += 1 }
    }

    static func run(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Queue.jobs = []
            Panel.latest = nil
            Island.shared.presentationWindow = nil
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for host in ["island key", "island event", "island menu", "floating", "floating while island key"] {
                for response in [NSApplication.ModalResponse.cancel, .OK] {
                    let service = Service()
                    let island = Window()
                    let floating = Window()
                    Island.shared.presentationWindow = island
                    service.panel = floating
                    service.NSApp.keyWindow = host == "island key" || host == "floating while island key" ? island : floating
                    if host == "island event" {
                        service.NSApp.currentEvent = Application.Event(window: island)
                    } else if host == "island menu" {
                        service.NSApp.currentEvent = Application.Event(window: Window())
                    }
                    let fromIsland = host.hasPrefix("island")
                    let destination = root.appendingPathComponent("notes.txt")
                    try "Previous file".write(to: destination, atomically: true, encoding: .utf8)
                    service.exportText(suggestedName: "Notes.txt", from: fromIsland ? island : nil)
                    guard let panel = Panel.latest else {
                        suite.expect(false, "export prepares its save panel")
                        continue
                    }
                    suite.expect(service.modalInteractionActive && service.flushes == 1,
                                 "export protects its document while a dialog is pending")
                    service.exportText(suggestedName: "Duplicate.txt")
                    suite.expect(Panel.latest === panel, "a pending export cannot open a second dialog")
                    panel.url = destination
                    panel.response = response
                    service.text = "A later edit"
                    if !fromIsland {
                        suite.expect(panel.parent == nil, "the floating pad retains its independent dialog")
                        Queue.drain()
                        suite.expect(panel.modalCalls == 1 && floating.focusCount == 1 && island.focusCount == 0,
                                     "floating-pad export returns focus only to its own host")
                    } else {
                        suite.expect(panel.parent == nil && panel.standalone && panel.focused && panel.modalCalls == 0
                                     && panel.level.rawValue > island.level.rawValue && !panel.hidesOnDeactivate,
                                     "island export opens its own dialog above its host instead of attaching or opening behind it")
                        panel.finish(response)
                        suite.expect(island.focusCount == 0, "completion defers focus until dismissal finishes")
                        Queue.drain()
                        suite.expect(island.focusCount == 1 && floating.focusCount == 0,
                                     "island export returns focus to the island even when its menu supplied the event")
                    }
                    suite.expect(!service.modalInteractionActive, "completion releases the export guard")
                    let saved = try String(contentsOf: destination, encoding: .utf8)
                    suite.expect(saved == (response == .OK ? "A later edit" : "Previous file"),
                                 "export writes the pad as it is when the save is confirmed and cancellation never writes")
                }
            }
            try editsWhileOpen(suite, root: root)
            let service = Service()
            let island = Window()
            Island.shared.presentationWindow = island
            service.NSApp.keyWindow = island
            service.exportText(suggestedName: "Notes.txt", from: island)
            island.isVisible = false
            Panel.latest?.finish(.cancel)
            Queue.drain()
            suite.expect(island.focusCount == 0 && !service.modalInteractionActive,
                         "closing the island during export does not resurrect its window")
            Panel.latest = nil
            service.exportText(suggestedName: "Hidden.txt", from: island)
            suite.expect(Panel.latest == nil && !service.modalInteractionActive,
                         "an action delivered after its host disappeared cannot open a dialog")
        } catch {
            suite.expect(false, "export fixture completes: \(error)")
        }
    }

    /// The island's dialog does not block its pad. Choosing another tab
    /// meanwhile still saves the pad that asked; closing that pad reports the
    /// failed export and writes nothing.
    private static func editsWhileOpen(_ suite: TestSuite, root: URL) throws {
        let island = Window()
        Island.shared.presentationWindow = island
        let switching = Service()
        let chosen = root.appendingPathComponent("chosen.txt")
        switching.exportText(suggestedName: "Notes.txt", from: island)
        switching.document = switching.document?.addingPad(defaultName: "Notes")
        switching.text = "Another pad"
        Panel.latest?.url = chosen
        Panel.latest?.finish(.OK)
        Queue.drain()
        let exported = try String(contentsOf: chosen, encoding: .utf8)
        suite.expect(exported == "Notes to export", "choosing another tab during export still saves the pad that asked")

        let closing = Service()
        let kept = root.appendingPathComponent("kept.txt")
        try "Previous file".write(to: kept, atomically: true, encoding: .utf8)
        closing.exportText(suggestedName: "Notes.txt", from: island)
        let added = closing.document?.addingPad(defaultName: "Notes")
        closing.document = added?.removing(Fixture.padID)
        let failures = HUD.errors
        Panel.latest?.url = kept
        Panel.latest?.finish(.OK)
        Queue.drain()
        let untouched = try String(contentsOf: kept, encoding: .utf8)
        suite.expect(untouched == "Previous file" && HUD.errors == failures + 1,
                     "a pad closed while its dialog is open reports the failed export and writes nothing")
    }
}

/// The production save path runs against a store that can be made to fail.
enum ScratchpadSaveContract {
    final class Store {
        var succeeds = false
        var creates = false
        var writes = 0
        var createsRequested = 0
        var notesCreated = 0
        func save(_ document: ScratchpadDocument) -> Bool {
            writes += 1
            return succeeds
        }
        func createNote(named: String, in document: ScratchpadDocument) -> ScratchpadDocument? {
            createsRequested += 1
            guard creates else { return nil }
            notesCreated += 1
            return document.addingPad(defaultName: named, path: "note-\(notesCreated).md")
        }
    }
    enum HUD {
        static var messages: [String] = []
        static func show(icon: String, message: String) { messages.append(message) }
    }
    class Fixture {
        typealias QuickToolHUD = HUD
        var store = Store()
        var pendingSave: DispatchWorkItem?
        var hasLoaded = true
        var saveFailed = false
        var document: ScratchpadDocument? = .initial(defaultName: "Notes", text: "Unsaved notes")
        var applied = 0
        func apply(_ document: ScratchpadDocument, focus: Bool = false) {
            self.document = document
            applied += 1
        }
    }

    static func run(_ suite: TestSuite) {
        defer { HUD.messages = [] }
        let service = Service()
        let message = FeatureStrings.scratchpad(L10n.shared.language).saveFailed
        service.flushSave()
        suite.expect(service.saveFailed, "a failed autosave marks the pad as unsaved")
        service.createPad(defaultName: "Notes")
        suite.expect(service.saveFailed && service.store.createsRequested == 1 && service.store.writes == 1,
                     "a failed new note keeps the warning in place")
        suite.expect(service.applied == 0 && service.document?.pads.count == 1,
                     "a tab action whose file could not be created leaves the notes as they were")
        service.commitEdits()
        suite.expect(HUD.messages == [message], "a failed write as the pad or the island closes shows the HUD")
        service.store.creates = true
        service.store.succeeds = true
        service.createPad(defaultName: "Notes")
        suite.expect(!service.saveFailed && service.applied == 1 && service.document?.pads.count == 2,
                     "a created note clears the warning and opens its tab")
        service.commitEdits()
        suite.expect(HUD.messages.count == 1, "a successful write on close shows no HUD")
    }
}
