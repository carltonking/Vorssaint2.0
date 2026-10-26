// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The folder the notes live in is the user's Obsidian vault, so paths are
/// stored relative to it: moving the vault or opening notes on another Mac
/// keeps every tab pointing at the same file.
enum ScratchpadVaultSupport {
    static let markdownExtension = "md"
    /// The note the pad opens when no tab is left open: the vault's to-do
    /// list, created only if the vault does not have one yet.
    static let defaultNotePath = "Todo.md"

    /// The vault chosen in Settings, as a bookmark first (so a moved vault is
    /// found again) and as a plain path for the first launch after choosing.
    static func resolvedVaultURL(defaults: UserDefaults) -> URL? {
        let manager = FileManager.default
        if let data = defaults.data(forKey: DefaultsKey.scratchpadVaultBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                var isDirectory: ObjCBool = false
                if manager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return url.standardizedFileURL
                }
            }
        }
        guard let path = defaults.string(forKey: DefaultsKey.scratchpadVaultPath),
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return url
    }

    /// Applies a location picked in Settings and returns the vault it leads
    /// to. A folder becomes the vault; a Markdown file opens in place, in the
    /// current vault when it belongs to it and with its own folder as the
    /// vault otherwise. Tabs of another vault are let go, so a new folder opens
    /// its `Todo.md` instead of a fresh note named after the pad.
    static func adoptLocation(_ picked: URL, currentVault: URL?, defaults: UserDefaults) -> URL? {
        let picked = picked.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: picked.path, isDirectory: &isDirectory) else { return nil }
        let vault: URL
        var notePath: String?
        if isDirectory.boolValue {
            vault = picked
        } else {
            guard isMarkdownFile(picked) else { return nil }
            if let currentVault, let inside = relativePath(of: picked, in: currentVault) {
                vault = currentVault.standardizedFileURL
                notePath = inside
            } else {
                vault = picked.deletingLastPathComponent().standardizedFileURL
                notePath = picked.lastPathComponent
            }
        }
        let sameVault = currentVault?.standardizedFileURL.path == vault.path
        var open = sameVault ? (defaults.stringArray(forKey: DefaultsKey.scratchpadOpenNotes) ?? []) : []
        if let notePath {
            if !open.contains(notePath) {
                if open.count >= ScratchpadDocument.maximumPadCount { open.removeFirst() }
                open.append(notePath)
            }
            defaults.set(notePath, forKey: DefaultsKey.scratchpadSelectedNote)
        } else if !sameVault {
            defaults.removeObject(forKey: DefaultsKey.scratchpadSelectedNote)
        }
        defaults.set(open, forKey: DefaultsKey.scratchpadOpenNotes)
        defaults.set(vault.path, forKey: DefaultsKey.scratchpadVaultPath)
        return vault
    }

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope],
                              includingResourceValuesForKeys: nil,
                              relativeTo: nil)
    }

    static func isMarkdownFile(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(markdownExtension) == .orderedSame
    }

    /// A file name the vault can hold: one line, no path separators, and short
    /// enough for the tab strip. A name made entirely of dots or spaces falls
    /// back to a word rather than a hidden or empty file.
    static func sanitizedFileStem(_ name: String) -> String {
        let words = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let cleaned = words.joined(separator: " ")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let bounded = String(cleaned.prefix(ScratchpadDocument.maximumNameLength))
        return bounded.isEmpty ? "Note" : bounded
    }

    /// `.md` files in the vault are the only notes the pad can touch, so an
    /// open panel result from anywhere else is refused instead of written.
    static func relativePath(of url: URL, in vault: URL) -> String? {
        guard isMarkdownFile(url) else { return nil }
        let vaultPath = vault.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let prefix = vaultPath.hasSuffix("/") ? vaultPath : vaultPath + "/"
        guard filePath != vaultPath, filePath.hasPrefix(prefix) else { return nil }
        let relative = String(filePath.dropFirst(prefix.count))
        guard !relative.isEmpty,
              !relative.split(separator: "/").contains("..") else { return nil }
        return relative
    }

    static func fileURL(forRelativePath path: String, in vault: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }
        let url = vault.appendingPathComponent(path).standardizedFileURL
        guard relativePath(of: url, in: vault) == path else { return nil }
        return url
    }

    /// The vault's notes as Obsidian's file list shows them: folders first,
    /// then notes, each in Finder's order. Hidden folders (`.obsidian`,
    /// `.trash`) and folders holding no note at any depth are left out.
    static func noteTree(in vault: URL) -> [ScratchpadVaultNode] {
        noteTree(in: vault, vault: vault, depth: 0)
    }

    private static func noteTree(in folder: URL, vault: URL, depth: Int) -> [ScratchpadVaultNode] {
        // Deep enough for any vault laid out by hand, and a stop for a
        // symbolic link that leads back into itself.
        guard depth < 12, let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var folders: [ScratchpadVaultNode] = []
        var notes: [ScratchpadVaultNode] = []
        for url in entries {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let children = noteTree(in: url, vault: vault, depth: depth + 1)
                guard !children.isEmpty else { continue }
                let path = relativeFolderPath(of: url, in: vault)
                folders.append(ScratchpadVaultNode(name: url.lastPathComponent, path: path, children: children))
            } else if let path = relativePath(of: url, in: vault) {
                notes.append(ScratchpadVaultNode(name: url.deletingPathExtension().lastPathComponent,
                                                 path: path, children: nil))
            }
        }
        let order: (ScratchpadVaultNode, ScratchpadVaultNode) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return folders.sorted(by: order) + notes.sorted(by: order)
    }

    private static func relativeFolderPath(of url: URL, in vault: URL) -> String {
        let root = vault.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : url.lastPathComponent
    }

    /// The note a `[[wikilink]]` names, resolved as Obsidian resolves it: a
    /// path from the vault root when it has one, otherwise the note with that
    /// file name anywhere in the vault. A `#heading` or `^block` part only
    /// points inside the note. Nil when no such note exists yet.
    static func noteURL(forWikilink target: String, in vault: URL) -> URL? {
        let note = String(target.prefix(while: { $0 != "#" && $0 != "^" }))
            .trimmingCharacters(in: .whitespaces)
        guard !note.isEmpty else { return nil }
        let file = isMarkdownFile(URL(fileURLWithPath: note)) ? note : note + "." + markdownExtension
        let manager = FileManager.default
        if let direct = fileURL(forRelativePath: file, in: vault), manager.fileExists(atPath: direct.path) {
            return direct
        }
        let name = (file as NSString).lastPathComponent
        // Hidden folders are skipped, and with them `.obsidian` and `.trash`.
        guard let walker = manager.enumerator(at: vault, includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let url as URL in walker
        where url.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
            return url.standardizedFileURL
        }
        return nil
    }

    /// The file an `![[image.png]]` embed shows: a path from the vault root,
    /// or a file of that name anywhere in the vault. Never outside it.
    static func attachmentURL(forEmbed target: String, in vault: URL) -> URL? {
        let name = (target.split(separator: "|").first.map(String.init) ?? target)
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { return nil }
        let manager = FileManager.default
        let direct = vault.appendingPathComponent(name).standardizedFileURL
        if direct.path.hasPrefix(vault.standardizedFileURL.path + "/"), manager.fileExists(atPath: direct.path) {
            return direct
        }
        let file = (name as NSString).lastPathComponent
        guard let walker = manager.enumerator(at: vault, includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let url as URL in walker where url.lastPathComponent.caseInsensitiveCompare(file) == .orderedSame {
            return url.standardizedFileURL
        }
        return nil
    }

    /// Every note's name in a tree, for `[[` completion.
    static func noteNames(in tree: [ScratchpadVaultNode]) -> [String] {
        tree.flatMap { node in node.children.map(noteNames(in:)) ?? [node.name] }
    }

    /// A note name that does not replace an existing file, preferring the
    /// plain name and numbering after it.
    static func uniqueFileURL(named name: String,
                              in vault: URL,
                              reserved: Set<String> = []) -> URL {
        let stem = sanitizedFileStem(name)
        let manager = FileManager.default
        var candidate = vault.appendingPathComponent("\(stem).md").standardizedFileURL
        var number = 2
        while manager.fileExists(atPath: candidate.path) || reserved.contains(candidate.path) {
            candidate = vault.appendingPathComponent("\(stem) \(number).md").standardizedFileURL
            number += 1
        }
        return candidate
    }
}

/// A folder or note of the vault, as the open-note menu lists it. `path` is
/// relative to the vault; a note has no `children`.
struct ScratchpadVaultNode: Equatable {
    let name: String
    let path: String
    let children: [ScratchpadVaultNode]?
}

/// Reads the notes the private scratchpad kept before notes became vault files.
/// The old copies stay where they are: importing writes new `.md` files and
/// never removes the originals it could not decode.
enum ScratchpadLegacyNotes {
    struct Note: Equatable {
        let name: String
        let text: String
    }

    private struct StoredPad: Decodable {
        let name: String?
        let text: String?
    }

    private struct StoredDocument: Decodable {
        let pads: [StoredPad]?
    }

    static func notes(defaults: UserDefaults,
                      containerURL: URL?,
                      fallbackName: String) -> [Note]? {
        if let preference = defaults.object(forKey: DefaultsKey.scratchpadDocument) {
            guard let data = preference as? Data else { return nil }
            return decode(data)
        }
        guard let containerURL else { return nil }
        let manager = FileManager.default
        let documentURL = containerURL.appendingPathComponent("Scratchpad.json")
        if manager.fileExists(atPath: documentURL.path) {
            guard let data = try? Data(contentsOf: documentURL) else { return nil }
            return decode(data)
        }
        let textURL = containerURL.appendingPathComponent("Scratchpad.txt")
        guard manager.fileExists(atPath: textURL.path),
              let data = try? Data(contentsOf: textURL),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return [Note(name: fallbackName, text: text)]
    }

    private static func decode(_ data: Data) -> [Note]? {
        guard let document = try? JSONDecoder().decode(StoredDocument.self, from: data),
              let pads = document.pads else { return nil }
        return pads.map { Note(name: $0.name ?? "", text: $0.text ?? "") }
    }
}

/// The scratchpad's notes are Markdown files in the user's Obsidian vault, so
/// every edit is saved the moment it lands and Obsidian sees it immediately.
/// Nothing here deletes a file: closing a tab only stops showing it.
struct ScratchpadStore {
    let vaultURL: URL?
    let defaults: UserDefaults
    let privateContainerURL: URL?
    private(set) var lastSavedDocument: ScratchpadDocument?
    private var canSave = false

    init(vaultURL: URL?,
         defaults: UserDefaults,
         privateContainerURL: URL? = PrivateFileStore.containerURL) {
        self.vaultURL = vaultURL
        self.defaults = defaults
        self.privateContainerURL = privateContainerURL
    }

    /// Reads the tabs that were open last time. A tab whose file disappeared
    /// or cannot be read is dropped instead of failing every other note; when
    /// none are left, the vault's `Todo.md` opens. The pad edits the notes the
    /// vault already holds, so it never invents one of its own to type in.
    mutating func load() throws -> ScratchpadDocument {
        canSave = false
        lastSavedDocument = nil
        guard let vaultURL else { throw CocoaError(.fileReadNoSuchFile) }
        let storedPaths = defaults.stringArray(forKey: DefaultsKey.scratchpadOpenNotes) ?? []
        let storedSelection = defaults.string(forKey: DefaultsKey.scratchpadSelectedNote)
        var pads: [ScratchpadPad] = []
        for path in storedPaths {
            guard let url = ScratchpadVaultSupport.fileURL(forRelativePath: path, in: vaultURL),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            pads.append(pad(at: url, path: path, text: text))
        }
        let document: ScratchpadDocument
        if pads.isEmpty {
            let path = ScratchpadVaultSupport.defaultNotePath
            guard let url = ScratchpadVaultSupport.fileURL(forRelativePath: path, in: vaultURL) else {
                throw CocoaError(.fileWriteUnknown)
            }
            // Created empty only when the vault has no such note yet.
            if !FileManager.default.fileExists(atPath: url.path),
               !FileManager.default.createFile(atPath: url.path, contents: Data()) {
                throw CocoaError(.fileWriteUnknown)
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            let todo = pad(at: url, path: path, text: text)
            document = ScratchpadDocument(pads: [todo], selectedID: todo.id)
        } else {
            document = ScratchpadDocument(
                pads: pads,
                selectedID: pads.first(where: { $0.path == storedSelection })?.id ?? pads[0].id
            )
        }
        canSave = true
        lastSavedDocument = document
        persistWorkspace(document)
        return document
    }

    @discardableResult
    mutating func save(_ document: ScratchpadDocument) -> Bool {
        guard canSave else { return false }
        guard let vaultURL else { return false }
        var savedEveryNote = true
        var record = document
        var unsaved: Set<String> = []
        for (index, pad) in document.pads.enumerated() {
            let previous = lastSavedDocument?.pads.first(where: { $0.path == pad.path })?.text
            // A tab with nothing typed since it was read has nothing to save.
            // Obsidian or iCloud rewriting its file meanwhile is not a failed
            // save: the newer file shows on the next load. Counting it as one
            // kept the warning up on every opening, because the pad stops
            // rereading its files while a save is failing.
            if let previous, previous == pad.text { continue }
            guard let url = ScratchpadVaultSupport.fileURL(forRelativePath: pad.path, in: vaultURL) else {
                savedEveryNote = false
                unsaved.insert(pad.path)
                continue
            }
            let onDisk = try? String(contentsOf: url, encoding: .utf8)
            if onDisk == pad.text { continue }
            // Obsidian may have written this note while the tab was open. Its
            // text wins over an autosave typed before the app saw the change.
            let changedOutside = onDisk != nil && previous != nil && onDisk != previous
            if changedOutside || (try? pad.text.write(to: url, atomically: true, encoding: .utf8)) == nil {
                savedEveryNote = false
                if let previous { record.pads[index].text = previous } else { unsaved.insert(pad.path) }
            }
        }
        persistWorkspace(document)
        // Each note remembers its own last write, so one note that cannot be
        // saved does not make every later edit of the others look like a
        // conflict with Obsidian.
        record.pads.removeAll { unsaved.contains($0.path) }
        lastSavedDocument = record
        return savedEveryNote
    }

    /// A new note is a new file in the vault, named after the tab but never
    /// over an existing one.
    mutating func createNote(named name: String,
                             in document: ScratchpadDocument,
                             now: Date = Date()) -> ScratchpadDocument? {
        guard let vaultURL,
              document.pads.count < ScratchpadDocument.maximumPadCount else { return nil }
        let url = ScratchpadVaultSupport.uniqueFileURL(named: name, in: vaultURL)
        guard (try? "".write(to: url, atomically: true, encoding: .utf8)) != nil,
              let path = ScratchpadVaultSupport.relativePath(of: url, in: vaultURL) else { return nil }
        let pad = ScratchpadPad(id: UUID(),
                                name: url.deletingPathExtension().lastPathComponent,
                                text: "",
                                modifiedAt: now,
                                path: path)
        var next = document
        next.pads.append(pad)
        next.selectedID = pad.id
        persistWorkspace(next)
        return next
    }

    /// Opens a note the vault already holds. Anything outside the vault or
    /// without the Markdown extension is refused, so a pick can never write
    /// somewhere the user did not choose.
    mutating func openNote(at url: URL,
                           in document: ScratchpadDocument) -> ScratchpadDocument? {
        guard let vaultURL,
              let path = ScratchpadVaultSupport.relativePath(of: url, in: vaultURL) else { return nil }
        if let existing = document.pads.first(where: { $0.path == path }) {
            var next = document
            next.selectedID = existing.id
            persistWorkspace(next)
            return next
        }
        guard document.pads.count < ScratchpadDocument.maximumPadCount,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let pad = pad(at: url, path: path, text: text)
        var next = document
        next.pads.append(pad)
        next.selectedID = pad.id
        persistWorkspace(next)
        return next
    }

    /// Renaming a tab renames its file in the vault, in the folder it already
    /// lives in. A name already taken by another note is refused.
    mutating func renameNote(_ id: UUID,
                             to name: String,
                             in document: ScratchpadDocument) -> ScratchpadDocument? {
        guard let vaultURL,
              let index = document.pads.firstIndex(where: { $0.id == id }),
              let source = ScratchpadVaultSupport.fileURL(forRelativePath: document.pads[index].path,
                                                          in: vaultURL) else { return nil }
        let stem = ScratchpadVaultSupport.sanitizedFileStem(name)
        let target = source.deletingLastPathComponent().appendingPathComponent("\(stem).md")
        if target.standardizedFileURL == source.standardizedFileURL { return document }
        guard !FileManager.default.fileExists(atPath: target.path),
              (try? FileManager.default.moveItem(at: source, to: target)) != nil,
              let path = ScratchpadVaultSupport.relativePath(of: target, in: vaultURL) else { return nil }
        var next = document
        next.pads[index].name = stem
        next.pads[index].path = path
        persistWorkspace(next)
        return next
    }

    /// Closing a tab leaves the file in the vault: a note is the user's, not
    /// the pad's, and closing it is not deleting it.
    mutating func closeNote(_ id: UUID,
                            in document: ScratchpadDocument) -> ScratchpadDocument? {
        guard document.pads.count > 1,
              let index = document.pads.firstIndex(where: { $0.id == id }) else { return nil }
        var next = document
        next.pads.remove(at: index)
        if document.selectedID == id {
            next.selectedID = next.pads[min(index, next.pads.count - 1)].id
        }
        persistWorkspace(next)
        return next
    }

    /// One-time import of the private notes this feature kept before it wrote
    /// Markdown: each old pad becomes a new `.md` file and its tab, while the
    /// original copies stay untouched as a fallback.
    mutating func importLegacyNotes(defaultName: String) -> Int {
        guard let vaultURL,
              !defaults.bool(forKey: DefaultsKey.scratchpadLegacyImported),
              let notes = ScratchpadLegacyNotes.notes(defaults: defaults,
                                                      containerURL: privateContainerURL,
                                                      fallbackName: defaultName),
              !notes.isEmpty else { return 0 }
        var importedPaths: [String] = []
        for note in notes {
            let url = ScratchpadVaultSupport.uniqueFileURL(
                named: note.name.isEmpty ? defaultName : note.name, in: vaultURL)
            guard (try? note.text.write(to: url, atomically: true, encoding: .utf8)) != nil,
                  let path = ScratchpadVaultSupport.relativePath(of: url, in: vaultURL) else { continue }
            importedPaths.append(path)
        }
        guard !importedPaths.isEmpty else { return 0 }
        defaults.set(importedPaths, forKey: DefaultsKey.scratchpadOpenNotes)
        defaults.set(importedPaths[0], forKey: DefaultsKey.scratchpadSelectedNote)
        defaults.set(true, forKey: DefaultsKey.scratchpadLegacyImported)
        return importedPaths.count
    }

    private func pad(at url: URL, path: String, text: String) -> ScratchpadPad {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return ScratchpadPad(id: UUID(),
                             name: url.deletingPathExtension().lastPathComponent,
                             text: text,
                             modifiedAt: modified,
                             path: path)
    }

    private func persistWorkspace(_ document: ScratchpadDocument) {
        defaults.set(document.pads.map(\.path), forKey: DefaultsKey.scratchpadOpenNotes)
        if let selected = document.pads.first(where: { $0.id == document.selectedID }) {
            defaults.set(selected.path, forKey: DefaultsKey.scratchpadSelectedNote)
        }
    }
}
