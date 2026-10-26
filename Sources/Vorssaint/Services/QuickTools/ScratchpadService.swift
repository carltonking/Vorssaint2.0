// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// A floating pad for short-lived text: meeting notes, numbers, fragments on
/// their way somewhere else. Summoned from the panel, the quick panel or a
/// global shortcut, it saves every edit by itself in a small tabbed document, so
/// nothing runs at rest and edits remain available between openings. It steps
/// aside on a click outside, and an option keeps it floating over other apps
/// instead.
final class ScratchpadService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ScratchpadService()

    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var isPinned = false
    @Published private(set) var isPreviewing = false
    /// Not a preference: the row is a thing you reach for while writing, not a
    /// choice about the pad, so every opening starts without it and one click
    /// brings it back. Held here rather than in either view so both pads agree
    /// while the pad is up.
    @Published private(set) var marksExpanded = false
    @Published private(set) var pads: [ScratchpadPad] = []
    @Published private(set) var selectedPadID: UUID?
    /// The chosen Obsidian vault, shown in Settings; nil until one is picked.
    @Published private(set) var vaultPath: String?
    /// Both pads show this in place until a write succeeds again.
    @Published private(set) var saveFailed = false
    /// Bumped when Command-W asks the view to close the selected tab
    /// (so confirmation stays in SwiftUI).
    @Published private(set) var keyboardCloseSelectedPadSerial = 0
    @Published var text = "" {
        didSet {
            guard hasLoaded, !isReplacingText, var document else { return }
            document.updateSelectedText(text, modifiedAt: Date())
            self.document = document
            pads = document.pads
            scheduleSave()
        }
    }

    private let hotkey = QuickToolHotkey(id: 18)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private weak var textView: NSTextView?
    private var pendingSave: DispatchWorkItem?
    private var document: ScratchpadDocument?
    private var store = ScratchpadStore(vaultURL: nil, defaults: .standard)
    private var vaultURL: URL?
    private var scopedVaultURL: URL?
    private var hasLoaded = false
    private var isReplacingText = false
    /// Each open note's file date as this editor last read or wrote it. A
    /// newer date on disk means Obsidian (or iCloud) changed the note.
    private var knownFileDates: [String: Date] = [:]
    private var externalSyncTimer: Timer?
    private(set) var modalInteractionActive = false

    private override init() {
        super.init()
        hotkey.onPress = { [weak self] in self?.toggle() }
        refreshVault()
    }

    func syncWithPreferences() {
        let available = AppFeature.scratchpad.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.scratchpadShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.scratchpadShortcut,
                                            fallback: .scratchpadDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.scratchpadShortcut)
        if !available {
            hide()
            // Uninstalled in the hub: nothing stays resident.
            panel = nil
        }
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// The shortcut is a strict toggle only while the pad has the keyboard:
    /// visible but unfocused, it grabs focus instead of closing, so one press
    /// always lands the caret in the text.
    func toggle() {
        guard !modalInteractionActive else { return }
        refreshVault()
        guard vaultURL != nil else {
            QuickToolHUD.show(icon: "folder.badge.questionmark",
                              message: FeatureStrings.scratchpad(L10n.shared.language).vaultMissing)
            return
        }
        if NotchService.shared.showScratchpad(toggle: true) {
            if isVisible { hide() }
            return
        }
        if isVisible, panel?.isKeyWindow == true {
            hide()
        } else {
            show()
        }
    }

    /// The island's own open action passes false: it moves the document out
    /// to the floating pad instead of routing it back into the island.
    func show(allowsIsland: Bool = true) {
        guard AppFeature.scratchpad.isAvailable, !modalInteractionActive else { return }
        let strings = FeatureStrings.scratchpad(L10n.shared.language)
        refreshVault()
        guard vaultURL != nil else {
            QuickToolHUD.show(icon: "folder.badge.questionmark", message: strings.vaultMissing)
            return
        }
        if allowsIsland, NotchService.shared.showScratchpad() {
            if isVisible { hide() }
            return
        }
        if isVisible {
            focusText(requiresKeyWindow: false)
            return
        }
        isPreviewing = false
        marksExpanded = false
        isPinned = !closesOnClickOutside
        guard load() else {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: strings.loadFailed)
            return
        }
        beginExternalSync()
        let panel = ensurePanel()
        installMonitors(for: panel)
        // The pad keeps the spot and size the user gave it while the app
        // runs; it only re-centers when that spot is no longer on any screen.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        focusText(requiresKeyWindow: false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
    }

    /// The island edits the same notes in place: load them from the vault
    /// without showing the floating pad, and commit when it leaves.
    func loadForEmbedding() -> Bool {
        guard AppFeature.scratchpad.isAvailable else { return false }
        marksExpanded = false
        refreshVault()
        guard vaultURL != nil else { return false }
        let loaded = load()
        if loaded { beginExternalSync() }
        return loaded
    }

    /// The inline warning leaves with the pad or the island, so a final
    /// write that fails on the way out falls back to the HUD.
    func commitEdits() {
        endExternalSync()
        flushSave()
        if saveFailed {
            QuickToolHUD.show(
                icon: "exclamationmark.triangle",
                message: FeatureStrings.scratchpad(L10n.shared.language).saveFailed)
        }
    }

    func hide() {
        guard panel != nil else { return }
        commitEdits()
        removeMonitors()
        panel?.orderOut(nil)
        isPinned = false
        isPreviewing = false
        modalInteractionActive = false
    }

    // MARK: - Document

    /// The open pad rereads its files each time it is brought back, so a note
    /// edited in Obsidian shows the newer text here. Unsaved edits stay in
    /// memory instead of being replaced by the older file.
    @discardableResult
    private func load() -> Bool {
        refreshVault()
        guard vaultURL != nil else {
            hasLoaded = false
            return false
        }
        if hasLoaded {
            flushSave()
            if saveFailed { return true }
        }
        do {
            let loaded = try store.load()
            apply(loaded)
            hasLoaded = true
            rememberFileDates()
            return true
        } catch {
            hasLoaded = false
            return false
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasLoaded, let document else { return }
        _ = save(document)
    }

    /// A failed write keeps the edits in memory and retries on the next change.
    private func save(_ next: ScratchpadDocument) -> Bool {
        saveFailed = !store.save(next)
        // Our own write is not an outside change.
        if !saveFailed { rememberFileDates() }
        return !saveFailed
    }

    // MARK: Obsidian sync

    /// While the editor is on screen, a note Obsidian (or iCloud) rewrote is
    /// read back within about a second. Obsidian and iCloud replace the file
    /// rather than edit it, which a file-descriptor watch would lose, so the
    /// open notes' dates are compared instead: a handful of stat calls.
    func beginExternalSync() {
        guard externalSyncTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkExternalChanges() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        externalSyncTimer = timer
    }

    func endExternalSync() {
        externalSyncTimer?.invalidate()
        externalSyncTimer = nil
    }

    private func fileDate(_ path: String) -> Date? {
        guard let vaultURL else { return nil }
        let url = vaultURL.appendingPathComponent(path)
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func rememberFileDates() {
        knownFileDates = Dictionary(uniqueKeysWithValues: pads.map { ($0.path, fileDate($0.path) ?? .distantPast) })
    }

    /// Reloads when an open note changed outside, unless typing here is still
    /// waiting to be saved: those words are never thrown away, and the next
    /// save's own conflict check decides between the two versions.
    private func checkExternalChanges() {
        guard hasLoaded, pendingSave == nil, !saveFailed, !isReplacingText else { return }
        let changed = pads.contains { pad in
            guard let date = fileDate(pad.path) else { return false }
            return date > (knownFileDates[pad.path] ?? .distantPast)
        }
        guard changed, let loaded = try? store.load() else { return }
        apply(loaded)
        rememberFileDates()
    }

    private func apply(_ document: ScratchpadDocument, focus: Bool = false) {
        self.document = document
        pads = document.pads
        selectedPadID = document.selectedID
        let selectedText = document.pads.first(where: { $0.id == document.selectedID })?.text ?? ""
        isReplacingText = true
        text = selectedText
        isReplacingText = false
        if text.isEmpty { isPreviewing = false }
        if focus { focusText() }
    }

    var canCreatePad: Bool { pads.count < ScratchpadDocument.maximumPadCount }
    var canClosePad: Bool { pads.count > 1 }
    var selectedPadName: String {
        pads.first(where: { $0.id == selectedPadID })?.name
            ?? FeatureStrings.scratchpad(L10n.shared.language).pageTitle
    }

    /// A new tab is a new `.md` file, created in the vault before the tab
    /// appears so the note exists the moment it can be typed in.
    func createPad(defaultName: String) {
        guard let document, let next = store.createNote(named: defaultName, in: document) else {
            saveFailed = true
            return
        }
        saveFailed = false
        apply(next, focus: true)
    }

    func selectPad(_ id: UUID) {
        guard id != selectedPadID, let document, let next = document.selecting(id), save(next) else { return }
        apply(next, focus: true)
    }

    /// Renaming a tab renames its file in the vault; a taken name leaves both
    /// the note and its tab as they were and says why.
    func renamePad(_ id: UUID, to name: String) {
        guard let document else { return }
        guard let next = store.renameNote(id, to: name, in: document) else {
            if !ScratchpadSupport.sanitizedPadName(name).isEmpty {
                QuickToolHUD.show(
                    icon: "exclamationmark.triangle",
                    message: FeatureStrings.scratchpad(L10n.shared.language).renameNoteFailed)
            }
            return
        }
        apply(next, focus: id == selectedPadID)
    }

    /// Closing a tab only stops showing the note; the file stays in the vault.
    /// The last edits are flushed first so the closed tab cannot take the text
    /// typed during the save debounce with it.
    @discardableResult
    func closePad(_ id: UUID) -> Bool {
        flushSave()
        guard let document, let next = store.closeNote(id, in: document) else { return false }
        apply(next, focus: true)
        return true
    }

    func setModalInteractionActive(_ active: Bool) {
        modalInteractionActive = active
    }

    /// Notes live in the vault, not in a settings backup, so export only has
    /// to make sure a pending edit already reached its file.
    func prepareForSettingsBackup() {
        if hasLoaded { flushSave() }
    }

    /// Import intentionally replaces settings. Drop the in-memory tabs so the
    /// termination flush cannot write them over the restored preferences.
    func prepareForSettingsRestore() {
        pendingSave?.cancel()
        pendingSave = nil
        hasLoaded = false
        document = nil
        store = ScratchpadStore(vaultURL: vaultURL, defaults: .standard)
    }

    // MARK: - Vault

    /// Picks the Obsidian vault the notes live in, then imports the private
    /// notes this feature kept before it wrote Markdown.
    func chooseVault() {
        guard AppFeature.scratchpad.isAvailable, !modalInteractionActive else { return }
        let strings = FeatureStrings.scratchpad(L10n.shared.language)
        commitEdits()
        let panel = NSOpenPanel()
        // A folder becomes the vault, and a Markdown file opens in place.
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let markdown = UTType(filenameExtension: ScratchpadVaultSupport.markdownExtension) {
            panel.allowedContentTypes = [markdown, .folder]
        }
        panel.prompt = strings.chooseVault
        panel.message = strings.vaultCaption
        panel.directoryURL = vaultURL
        modalInteractionActive = true
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.modalInteractionActive = false
            guard response == .OK, let url = panel.url else { return }
            self.adoptVault(url)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin(completionHandler: complete)
    }

    private func adoptVault(_ url: URL) {
        let defaults = UserDefaults.standard
        guard let vault = ScratchpadVaultSupport.adoptLocation(url, currentVault: vaultURL,
                                                               defaults: defaults) else { return }
        if let bookmark = ScratchpadVaultSupport.bookmark(for: vault) {
            defaults.set(bookmark, forKey: DefaultsKey.scratchpadVaultBookmark)
        } else {
            defaults.removeObject(forKey: DefaultsKey.scratchpadVaultBookmark)
        }
        hasLoaded = false
        document = nil
        refreshVault()
        let strings = FeatureStrings.scratchpad(L10n.shared.language)
        let imported = store.importLegacyNotes(defaultName: strings.newNoteName)
        if imported > 0 {
            QuickToolHUD.show(icon: "checkmark.circle",
                              message: String(format: strings.importedNotesFormat, imported))
        }
        if isVisible, !load() { hide() }
    }

    private func refreshVault() {
        let resolved = ScratchpadVaultSupport.resolvedVaultURL(defaults: .standard)
        guard resolved?.standardizedFileURL.path != vaultURL?.standardizedFileURL.path else {
            vaultPath = resolved?.path
            return
        }
        scopedVaultURL?.stopAccessingSecurityScopedResource()
        scopedVaultURL = nil
        vaultURL = resolved
        vaultPath = resolved?.path
        if let resolved, resolved.startAccessingSecurityScopedResource() {
            scopedVaultURL = resolved
        }
        store = ScratchpadStore(vaultURL: resolved, defaults: .standard)
        hasLoaded = false
        document = nil
        pads = []
        selectedPadID = nil
    }

    /// Opens a note the vault already holds, so any Markdown file is readable
    /// and editable in the pad rather than only the ones it created.
    func openExistingNote() {
        guard AppFeature.scratchpad.isAvailable, !modalInteractionActive else { return }
        let strings = FeatureStrings.scratchpad(L10n.shared.language)
        refreshVault()
        guard let vaultURL else {
            QuickToolHUD.show(icon: "folder.badge.questionmark", message: strings.vaultMissing)
            return
        }
        if document == nil, !load() {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: strings.loadFailed)
            return
        }
        guard pads.count < ScratchpadDocument.maximumPadCount else {
            QuickToolHUD.show(icon: "rectangle.stack",
                              message: String(format: strings.padLimitFormat,
                                              ScratchpadDocument.maximumPadCount))
            return
        }
        let padPanel = panel
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let markdown = UTType(filenameExtension: ScratchpadVaultSupport.markdownExtension) {
            panel.allowedContentTypes = [markdown]
        }
        panel.directoryURL = vaultURL
        panel.prompt = strings.openNote
        panel.message = strings.vaultCaption
        // The pad floats above ordinary windows; its picker has to sit above
        // the pad instead of behind it.
        if let padPanel { panel.level = NSWindow.Level(rawValue: padPanel.level.rawValue + 1) }
        modalInteractionActive = true
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.modalInteractionActive = false
            guard response == .OK, let url = panel.url else { return }
            guard let current = self.document,
                  let next = self.store.openNote(at: url, in: current) else {
                QuickToolHUD.show(icon: "exclamationmark.triangle", message: strings.openNoteFailed)
                return
            }
            self.saveFailed = false
            self.panel?.makeKey()
            self.apply(next, focus: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin(completionHandler: complete)
    }

    /// A clicked `[[wikilink]]` opens its note as a tab, and one naming a
    /// note the vault does not hold yet creates it, as Obsidian does.
    func openLinkedNote(_ target: String) {
        guard let vaultURL else { return }
        if let url = ScratchpadVaultSupport.noteURL(forWikilink: target, in: vaultURL) {
            openNote { store, current in store.openNote(at: url, in: current) }
        } else {
            let name = String(target.prefix(while: { $0 != "#" && $0 != "^" }))
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            openNote { store, current in store.createNote(named: name, in: current) }
        }
    }

    /// The vault's notes for the open-note menu. Read when the menu opens,
    /// never while a view draws.
    func vaultNoteTree() -> [ScratchpadVaultNode] {
        refreshVault()
        guard let vaultURL else { return [] }
        return ScratchpadVaultSupport.noteTree(in: vaultURL)
    }

    /// Opens a note picked from the vault's list as a tab, or selects its tab
    /// when it is already open.
    func openVaultNote(_ path: String) {
        guard let vaultURL,
              let url = ScratchpadVaultSupport.fileURL(forRelativePath: path, in: vaultURL) else { return }
        openNote { store, current in store.openNote(at: url, in: current) }
    }

    private func openNote(_ change: (inout ScratchpadStore, ScratchpadDocument) -> ScratchpadDocument?) {
        guard AppFeature.scratchpad.isAvailable, !modalInteractionActive else { return }
        let strings = FeatureStrings.scratchpad(L10n.shared.language)
        flushSave()
        guard let current = document else { return }
        guard let next = change(&store, current) else {
            let message = pads.count < ScratchpadDocument.maximumPadCount
                ? strings.openNoteFailed
                : String(format: strings.padLimitFormat, ScratchpadDocument.maximumPadCount)
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: message)
            return
        }
        saveFailed = false
        apply(next, focus: true)
    }

    // MARK: - Actions

    func copyAll() {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(text, forType: .string)
    }

    /// Clearing goes through the text view when it is up, so one Cmd+Z brings
    /// everything back while the pad stays open. The island passes its own
    /// editor for the same undo there.
    func clear(through editor: NSTextView? = nil) {
        guard !text.isEmpty else { return }
        if let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) {
            // A live input-method composition holds a marked range into the
            // storage; replacing the whole text underneath it leaves that
            // range pointing at nothing. Commit it first.
            if textView.hasMarkedText() { textView.unmarkText() }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: full, replacementString: "") {
                textView.replaceCharacters(in: full, with: "")
                textView.didChangeText()
            }
        } else {
            text = ""
        }
        if isPreviewing {
            isPreviewing = false
            focusText()
        }
        flushSave()
    }

    /// A checkbox clicked in the formatted reading flips its box through the
    /// text view when it is up, so the click is one edit that Cmd+Z takes
    /// back and the history typed before it stays. The island passes its own
    /// editor for the same undo there.
    func toggleTask(box: Int, through editor: NSTextView? = nil) {
        if let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) {
            // A live input-method composition holds a marked range into the
            // storage; editing around it leaves that range pointing at nothing.
            if textView.hasMarkedText() { textView.unmarkText() }
            guard let edit = ScratchpadSupport.taskToggleEdit(box: box, in: textView.string) else { return }
            // Its own undo step, never folded into the typing before it.
            textView.breakUndoCoalescing()
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            textView.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
        } else {
            guard let edit = ScratchpadSupport.taskToggleEdit(box: box, in: text) else { return }
            text = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
        flushSave()
    }

    /// The toolbar types the Markdown the user would have typed, through the
    /// text view so one Cmd+Z takes the whole mark back. The island passes its
    /// own editor for the same undo there.
    func apply(_ mark: ScratchpadMark, through editor: NSTextView? = nil) {
        guard !isPreviewing else { return }
        guard let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) else { return }
        // A live input-method composition holds a marked range into the
        // storage; editing around it leaves that range pointing at nothing.
        if textView.hasMarkedText() { textView.unmarkText() }
        // Clicking a button takes first responder away from the editor, and a
        // selection set on a view that is not first responder does not show.
        textView.window?.makeFirstResponder(textView)
        let edit = ScratchpadSupport.edit(applying: mark,
                                          to: textView.string,
                                          selection: textView.selectedRange())
        guard (textView.string as NSString).substring(with: edit.range) != edit.replacement else { return }
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        flushSave()
    }

    func toggleMarks() {
        marksExpanded.toggle()
    }

    func togglePreview() {
        guard !text.isEmpty else { return }
        isPreviewing.toggle()
        if isPreviewing { marksExpanded = false }
        if isPreviewing {
            if let textView = textView, textView.window === panel { hideFindBar(in: textView) }
            panel?.makeFirstResponder(nil)
        } else {
            focusText()
        }
    }

    func togglePin() {
        guard isVisible else { return }
        isPinned.toggle()
    }

    func outsideClickPreferenceDidChange() {
        guard isVisible else { return }
        isPinned = !closesOnClickOutside
    }

    /// Activate for dialog input and return focus to the originating host.
    /// The island's dialog floats just above it: a sheet would move and
    /// reskin the borderless surface.
    func exportText(suggestedName: String, from window: NSWindow? = nil) {
        guard !text.isEmpty, !modalInteractionActive, let padID = selectedPadID,
              let sourceWindow = window ?? panel, sourceWindow.isVisible else { return }
        modalInteractionActive = true
        flushSave()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = suggestedName
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.modalInteractionActive = false
            if response == .OK, let url = savePanel.url {
                do {
                    // The island's dialog leaves the pad editable, so the file
                    // gets the pad as it is when the save is confirmed. A pad
                    // closed meanwhile is reported like any failed write.
                    guard let content = self?.document?.pads.first(where: { $0.id == padID })?.text else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    // A read-only volume or a full disk used to end here in
                    // silence, with the save panel closed and nothing written.
                    QuickToolHUD.show(
                        icon: "exclamationmark.triangle",
                        message: FeatureStrings.scratchpad(L10n.shared.language).exportFailed)
                }
            }
            // Dismissal restores the previous key window after completion.
            DispatchQueue.main.async {
                if sourceWindow.isVisible { sourceWindow.makeKey() }
            }
        }
        if sourceWindow === NotchService.shared.presentationWindow {
            // modalInteractionActive keeps the island's working surface
            // while its independent dialog is up.
            savePanel.level = NSWindow.Level(rawValue: sourceWindow.level.rawValue + 1)
            // Like the sheet it replaces, it stays up while another app is active.
            savePanel.hidesOnDeactivate = false
            savePanel.begin(completionHandler: complete)
            NSApp.activate(ignoringOtherApps: true)
            // Activation alone can leave the nonactivating island holding focus.
            savePanel.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { complete(savePanel.runModal()) }
        }
    }

    // MARK: - Focus

    /// The editor registers itself while the pad's view is alive; the service
    /// only ever aims focus and the undoable clear at it.
    func registerTextView(_ view: NSTextView) {
        textView = view
    }

    /// Document actions keep focus in their host. Only an explicit show may
    /// bring the floating pad forward while the island or another app is key.
    private func focusText(requiresKeyWindow: Bool = true) {
        guard let panel, panel.isVisible, !requiresKeyWindow || panel.isKeyWindow else { return }
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, panel.isKeyWindow,
                  let textView = self.textView else { return }
            panel.makeFirstResponder(textView)
            let end = NSRange(location: (textView.string as NSString).length, length: 0)
            textView.setSelectedRange(end)
            textView.scrollRangeToVisible(end)
        }
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default; the pad needs it so
    /// typing and Esc work without activating the app.
    private final class KeyableScratchpadPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableScratchpadPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                                           styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                           backing: .buffered,
                                           defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        // Dragging inside the pad must select text, never move the window;
        // the header strip is the handle.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: 280, height: 220)
        panel.minSize = NSSize(width: 280, height: 220)
        panel.delegate = self
        let host = NSHostingController(rootView: ScratchpadView())
        // No preferred-size tracking: the pad is user-resizable and the view
        // fills whatever frame the panel has.
        host.sizingOptions = []
        panel.contentViewController = host
        // Assigning the content controller shrinks the window to the view's
        // minimum; restore the pad's starting size.
        panel.setContentSize(NSSize(width: 380, height: 300))
        center(panel)
        self.panel = panel
        return panel
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(280, frameSize.width), height: max(220, frameSize.height))
    }

    private func center(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.minY + (screen.height - size.height) * 0.58
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, min(y, screen.maxY - size.height - 16)),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    // MARK: - Monitors

    /// Esc always closes the pad, and so does a click anywhere outside it
    /// unless the user asked for a pad that stays put while working in other
    /// apps. The choice is read at click time, so flipping it in Settings
    /// takes effect on an open pad.
    private var closesOnClickOutside: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.scratchpadCloseOnClickOutside)
    }

    /// The export dialog is a click outside the pad by geometry, so saving to
    /// a file must never be what closes it.
    private var dismissesOnOutsideClick: Bool {
        ScratchpadSupport.dismissesOnOutsideClick(isPinned: isPinned,
                                                  exportModalActive: modalInteractionActive)
    }

    private func performFocusedTabShortcut(_ action: ScratchpadFocusedShortcut.Action) {
        switch action {
        case .createPad:
            createPad(defaultName: FeatureStrings.scratchpad(L10n.shared.language).newNoteName)
        case .closeSelectedPad:
            keyboardCloseSelectedPadSerial += 1
        case .hidePad:
            hide()
        case .find:
            performFind(.showFindInterface)
        case .findNext:
            performFind(.nextMatch)
        case .findPrevious:
            performFind(.previousMatch)
        }
    }

    /// The text view runs the find itself; it only has to be told which of the
    /// finder's actions was asked for, and that arrives as a sender's tag.
    func performFind(_ action: NSTextFinder.Action, in editor: NSTextView? = nil) {
        guard let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) else { return }
        // Both hosts keep the editor at zero opacity while previewing. Finding
        // there would open a bar or select a match nobody can see, over a
        // source nobody is reading, so the pad comes back to the text first.
        let leftPreview = isPreviewing
        if isPreviewing {
            isPreviewing = false
        }
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        // Stepping through matches leaves the keyboard where it is, so
        // Command-G from the search field keeps typing in the field. Preview
        // took the keyboard from the text, so a step out of it gives it back.
        if action == .showFindInterface || leftPreview {
            textView.window?.makeFirstResponder(textView)
        }
        textView.performTextFinderAction(sender)
    }

    /// Both hosts draw the editor at zero opacity in preview, and its find bar
    /// with it, so the bar closes rather than keep a search nobody can see.
    func hideFindBar(in editor: NSTextView) {
        guard editor.enclosingScrollView?.isFindBarVisible == true else { return }
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editor.performTextFinderAction(sender)
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                // Mid-composition Esc belongs to the input method, not the pad.
                if let textView = self.textView, textView.hasMarkedText() {
                    return event
                }
                // The find bar puts itself away on Esc and hands the keyboard
                // back to the text; the pad hides on the next one.
                if PlainTextEditor.findBarHasKeyboard(in: panel) { return event }
                self.hide()
                return nil
            }
            guard !self.modalInteractionActive else { return event }
            let commandOnly = event.modifierFlags
                .intersection([.command, .option, .control]) == .command
            let shift = event.modifierFlags.contains(.shift)
            if let action = ScratchpadFocusedShortcut.action(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                commandOnly: commandOnly,
                shift: shift,
                canCreatePad: self.canCreatePad,
                canClosePad: self.canClosePad
            ) {
                self.performFocusedTabShortcut(action)
                return nil
            }
            // At the tab limit Command-T still belongs to the pad, not the text.
            if commandOnly, !shift, event.charactersIgnoringModifiers?.lowercased() == "t" {
                return nil
            }
            return event
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               // Every key on the Accessibility Keyboard is a click outside this
               // panel. Dismissing on those makes the panel impossible to type into.
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hide()
            }
        }
    }

    /// A click on the pad's own edge (its resize border) still belongs to it.
    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}
