// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Hermes Chat settings: the switch, the command, and where the
/// conversation stands. It lives on the island's own settings page, as the
/// other page features' settings do.
struct NotchHermesChatSettingsControls: View {
    @ObservedObject private var chat = NotchHermesChatService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchHermesChatEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchHermesChatCliPath) private var cliPath = HermesACPSupport.defaultCommand
    @AppStorage(DefaultsKey.notchHermesChatShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.notchHermesChatNumber) private var number = ""
    /// The number the open conversation was started with; editing it moves
    /// the page between the iMessage thread and VERTUS on this Mac.
    @State private var appliedNumber: String?
    /// People texted lately, to pick VERTUS's Photon line from. Read off the
    /// main thread when the page opens, never from the body; empty when
    /// Messages cannot be read.
    @State private var recentContacts: [InstinctChatRecord] = []
    /// The command the running agent was started with. Opening this page is
    /// not a reason to restart it; editing the field is.
    @State private var appliedCommand: String?
    /// The VERTUS hub carries the conversation when it is installed, and then
    /// the command below has nothing to start. Read once when the page opens,
    /// never from the body.
    @State private var usesHub = false
    private var text: NotchHermesChatStrings { FeatureStrings.notchHermesChat(l10n.language) }
    private static let editSettleDelay = Duration.milliseconds(700)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.enable, isOn: $enabled)
                .disabled(!AppFeature.notchHermesChat.isAvailable)
            Text(text.description).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                SettingsRow(symbol: "phone", title: text.number) {
                    HStack(spacing: 4) {
                        TextField(text.numberPlaceholder, text: $number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        if !recentContacts.isEmpty {
                            Menu {
                                ForEach(recentContacts, id: \.id) { contact in
                                    Button(contact.name.isEmpty ? contact.identifier
                                           : "\(contact.name) · \(contact.identifier)") {
                                        number = contact.identifier
                                    }
                                }
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help(text.recentChats)
                            .accessibilityLabel(text.recentChats)
                        }
                    }
                }
                Text(text.numberHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if enabled, !usesHub, !textsVertus {
                SettingsRow(symbol: "terminal", title: text.cliPath) {
                    TextField(text.cliPathPlaceholder, text: $cliPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                Text(text.cliPathHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if enabled {
                Toggle(L10n.shared.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in chat.syncShortcut() }
                ShortcutPreferenceRow(role: .vertusChat, isEnabled: shortcutEnabled) { chat.syncShortcut() }
                if shortcutEnabled, chat.shortcutRegistrationFailed {
                    Text(L10n.shared.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
                }
                status
            }
        }
        .onAppear {
            if appliedCommand == nil { appliedCommand = cliPath }
            if appliedNumber == nil { appliedNumber = number }
            usesHub = VertusHubSupport.token(home: FileManager.default.homeDirectoryForCurrentUser) != nil
        }
        .task { recentContacts = await Self.readRecentContacts() }
        .onChange(of: enabled) { _, _ in
            appliedCommand = cliPath
            appliedNumber = number
            chat.syncWithPreferences()
        }
        // Giving or clearing the number switches the page once the typing
        // settles, not on every keystroke.
        .task(id: number) {
            guard enabled, number != appliedNumber else { return }
            try? await Task.sleep(for: Self.editSettleDelay)
            guard !Task.isCancelled, number != appliedNumber else { return }
            appliedNumber = number
            chat.retry()
        }
        // One restart for a typed command, once it stops changing, rather
        // than one per keystroke.
        .task(id: cliPath) {
            guard enabled, !usesHub, !textsVertus, cliPath != appliedCommand else { return }
            try? await Task.sleep(for: Self.editSettleDelay)
            guard !Task.isCancelled, cliPath != appliedCommand else { return }
            appliedCommand = cliPath
            chat.retry()
        }
    }

    private var textsVertus: Bool {
        !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The one-to-one threads Messages lists first, through `imsg chats`.
    private static func readRecentContacts() async -> [InstinctChatRecord] {
        await Task.detached(priority: .utility) {
            guard let imsg = HermesACPSupport.executable(
                command: InstinctMessagesSupport.defaultCommand,
                home: FileManager.default.homeDirectoryForCurrentUser,
                searchPath: ProcessInfo.processInfo.environment["PATH"]) else { return [] }
            let result = Shell.run(imsg.path, InstinctMessagesSupport.recentChatsArguments(), timeout: 10)
            guard result.status == 0 else { return [] }
            return InstinctMessagesSupport.recentContacts(in: result.output)
        }.value
    }

    @ViewBuilder private var status: some View {
        switch chat.state {
        case .off:
            EmptyView()
        case .connecting:
            Label(text.connecting, systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        case .ready:
            Label(chat.modelName ?? text.ready, systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let failure):
            HStack(spacing: 8) {
                Label(message(failure), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                // Texting VERTUS reads Messages, which needs this grant.
                if failure == .needsFullDiskAccess {
                    Button(FeatureStrings.notchInstinctChat(l10n.language).openFullDiskAccess) {
                        Permissions.shared.requestFullDiskAccess()
                    }
                    .controlSize(.small)
                }
                Button(text.retry) { chat.retry() }
                    .controlSize(.small)
            }
        }
    }

    private func message(_ failure: NotchHermesChatService.Failure) -> String {
        chat.describe(failure, language: l10n.language)
    }
}

/// The page: the conversation, the reply being written, and the field that
/// sends the next message. Hermes decides what tools to use; the island only
/// carries the words, and refuses the commands it would have to approve
/// unseen.
///
/// The same page carries Instinct's iMessage thread (`chat: .instinct`), with
/// previews under the links Instinct sends.
struct NotchHermesChatView: View {
    let size: CGSize
    @ObservedObject private var chat: NotchHermesChatService
    @ObservedObject private var voice = NotchHermesVoiceService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage private var enabled: Bool
    @AppStorage private var speakReplies: Bool
    @Environment(\.notchSettingsPreview) private var preview
    @State private var draft = ""
    /// What was typed before the microphone opened, kept in front of the
    /// words heard so dictating adds to a message instead of replacing it.
    @State private var typedBeforeDictation = ""
    @FocusState private var typing: Bool
    /// Replies finished before the page opened: only the ones after it make
    /// the companion cheer here.
    @State private var cheeredReplies: Int?
    /// The message the next one answers, chosen by swiping it or its Reply.
    @State private var replyTarget: UUID?
    /// Files waiting to go with the next message.
    @State private var pending: [URL] = []
    /// The bubble under the pointer, which a two-finger swipe moves.
    @State private var hoveredMessage: UUID?
    @State private var swipedMessage: UUID?
    @State private var swipeOffset: CGFloat = 0
    @State private var swipe = NotchMessagesSwipe()
    @State private var dropTargeted = false
    private var text: NotchHermesChatStrings { chat.strings(l10n.language) }
    private var messaging: NotchAgentMessagingStrings { FeatureStrings.notchAgentMessaging(l10n.language) }

    init(size: CGSize, chat: NotchHermesChatService = .shared) {
        self.size = size
        _chat = ObservedObject(wrappedValue: chat)
        _enabled = AppStorage(wrappedValue: false, chat.agent.enabledKey)
        _speakReplies = AppStorage(wrappedValue: false, chat.agent.speakRepliesKey)
    }

    /// Links in an iMessage thread open as cards; replies from VERTUS on
    /// this Mac keep their links inline, as they always have.
    private var previewsLinks: Bool { chat.carriesMessagesThread }

    private static let bottomID = "hermes-bottom"

    private var hasConversation: Bool {
        !chat.messages.isEmpty || !chat.reply.isEmpty || chat.working
    }

    var body: some View {
        VStack(spacing: 8) {
            if hasConversation {
                transcript
            } else {
                opening
            }
            ForEach(chat.approvals) { approval in
                NotchAgentApprovalCard(approval: approval, text: text,
                                       busy: chat.answering.contains(approval.id)) { choice in
                    chat.answer(approval, choice)
                }
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The island already holds the keyboard when it opens; the field takes
        // it so the first words typed are the message, as in the Command Bar.
        // A settings preview leaves the keyboard where it was.
        .onAppear {
            if cheeredReplies == nil { cheeredReplies = chat.completedReplies }
            voice.refreshAuthorization()
            swipe.install { phase in handleSwipe(phase) }
        }
        // The microphone never outlives the page that opened it.
        .onDisappear {
            voice.cancelDictation()
            swipe.remove()
        }
        // Files dropped anywhere on the page go with the next message.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async { if !pending.contains(url) { pending.append(url) } }
                }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: voice.heard) { _, words in
            guard voice.phase == .listening else { return }
            draft = NotchHermesVoiceSupport.draft(typed: typedBeforeDictation, dictated: words)
        }
        .task {
            guard !preview else { return }
            try? await Task.sleep(for: .milliseconds(80))
            typing = true
        }
        .notchBand(leading: { status }, trailing: {
            HStack(spacing: 2) {
                NotchIconButton(symbol: speakReplies ? "speaker.wave.2.fill" : "speaker.slash",
                                title: text.speakReplies, selected: speakReplies) {
                    speakReplies.toggle()
                    if !speakReplies { NotchHermesVoiceService.existing?.stopSpeaking() }
                }
                NotchIconButton(symbol: "trash", title: text.clear) { chat.clear() }
                    .disabled(chat.messages.isEmpty && chat.reply.isEmpty)
            }
        })
    }

    // MARK: Conversation

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                        row(message, index: index)
                    }
                    liveTurn
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onAppear { scroll(proxy, animated: false) }
            // A finished turn is worth a slide; a reply writing itself is
            // not, or the island would animate on every few words.
            .onChange(of: chat.messages.count) { _, _ in scroll(proxy, animated: true) }
            .onChange(of: chat.working) { _, _ in scroll(proxy, animated: true) }
            .onChange(of: chat.reply) { _, _ in scroll(proxy, animated: false) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        // The layout for this change has not happened yet; scrolling after it
        // lands on the new bottom rather than the old one.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            } else {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    /// Which side a message sits on, as in Messages: yours right, the
    /// agent's left; the island's own lines sit apart from both.
    private enum Side { case mine, theirs, aside }

    private func side(_ role: NotchHermesChatMessage.Role) -> Side {
        switch role {
        case .person: return .mine
        case .hermes, .proactive: return .theirs
        case .tool, .note: return .aside
        }
    }

    @ViewBuilder private func row(_ message: NotchHermesChatMessage, index: Int) -> some View {
        let messages = chat.messages
        let here = side(message.role)
        let previous = index > 0 ? side(messages[index - 1].role) : nil
        let next = index + 1 < messages.count ? side(messages[index + 1].role) : nil
        // A run of messages from one side tightens up, and only its last
        // bubble carries the tail, as in Messages.
        let startsRun = previous != here
        let endsRun = next != here || (index + 1 == messages.count && chat.working && here == .theirs)
        Group {
            switch here {
            case .mine, .theirs:
                bubbleRow(message, mine: here == .mine, tail: endsRun)
            case .aside:
                Label(message.text, systemImage: message.role == .tool ? "wrench.and.screwdriver" : "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(message.role == .tool ? 0.45 : 0.5))
                    .lineLimit(message.role == .tool ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.top, startsRun && index > 0 ? 8 : 0)
    }

    private func bubbleRow(_ message: NotchHermesChatMessage, mine: Bool, tail: Bool) -> some View {
        let swiping = swipedMessage == message.id ? swipeOffset : 0
        return VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            quote(message, mine: mine)
            NotchHermesChatBubble(words: message.text, mine: mine, tail: tail, text: text, messaging: messaging,
                                  reactions: message.reactions ?? [], attachments: message.attachments ?? [],
                                  reply: { startReply(to: message.id) },
                                  edit: mine ? { draft = message.text; typing = true } : nil)
                .accessibilityLabel("\(mine ? text.you : text.title): \(message.text)")
            if !mine { linkCards(message.text) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .offset(x: swiping)
        // The reply arrow shows from under the bubble as it is swiped.
        .background(alignment: .trailing) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .opacity(min(1, Double(-swiping) / NotchMessagesSwipe.threshold))
                .padding(.trailing, 6)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredMessage = message.id } else if hoveredMessage == message.id { hoveredMessage = nil }
        }
        .contextMenu {
            Button(messaging.reply) { startReply(to: message.id) }
            Button(text.copyMessage) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
            }
        }
    }

    /// The message an inline reply answers, as Messages shows it: a faded
    /// copy of it above the reply, joined to it by a line. Nothing when it
    /// is not in the transcript (older than the thread the page holds).
    @ViewBuilder private func quote(_ message: NotchHermesChatMessage, mine: Bool) -> some View {
        if let target = message.replyTo,
           let original = chat.messages.first(where: { $0.id == target }) {
            let theirs = original.role != .person
            HStack(spacing: 0) {
                if mine { Spacer(minLength: 60) }
                Text(original.text.isEmpty ? (original.attachments?.first?.name ?? "") : original.text)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(theirs ? Color.white.opacity(0.75) : Color.black.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theirs ? NotchMessagesStyle.theirs : NotchMessagesStyle.mine,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(0.55)
                if !mine { Spacer(minLength: 60) }
            }
            .overlay(alignment: mine ? .bottomTrailing : .bottomLeading) {
                // The thread line from the quote down into the reply.
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1.5, height: 10)
                    .offset(x: mine ? -14 : 14, y: 10)
            }
            .padding(.bottom, 4)
            .onTapGesture { startReply(to: original.id) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(messaging.replyingTo): \(original.text)")
        }
    }

    private static func firstLine(_ words: String) -> String {
        NotchAgentReplySupport.firstLine(words)
    }

    private func startReply(to id: UUID) {
        replyTarget = id
        typing = true
    }

    /// A two-finger swipe left on a bubble: it follows the fingers, and let
    /// go far enough it becomes the message the next one replies to.
    private func handleSwipe(_ phase: NotchMessagesSwipe.Phase) -> Bool {
        switch phase {
        case .moved(let distance):
            guard let hovered = hoveredMessage ?? swipedMessage,
                  chat.messages.contains(where: { $0.id == hovered && side($0.role) != .aside }) else { return false }
            swipedMessage = hovered
            swipeOffset = max(-NotchMessagesSwipe.limit, min(0, distance))
            return true
        case .ended:
            guard let swiped = swipedMessage else { return false }
            if swipeOffset <= -NotchMessagesSwipe.threshold { startReply(to: swiped) }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { swipeOffset = 0 }
            swipedMessage = nil
            return true
        }
    }

    /// A card under each web link an agent's message carries, in order.
    @ViewBuilder private func linkCards(_ words: String) -> some View {
        if previewsLinks {
            ForEach(NotchLinkPreviewService.shared.links(in: words), id: \.self) { url in
                NotchLinkPreviewCard(url: url, openTitle: FeatureStrings.notchInstinctChat(l10n.language).openLink)
            }
        }
    }

    /// The reply in flight, with the reasoning Hermes chose to show above it
    /// and a mark while there is nothing to read yet.
    @ViewBuilder private var liveTurn: some View {
        if chat.working {
            VStack(alignment: .leading, spacing: 6) {
                if !chat.thinking.isEmpty {
                    Text(chat.thinking)
                        .font(.system(size: 10.5).italic())
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(5)
                }
                if chat.reply.isEmpty {
                    NotchTypingBubble()
                        .accessibilityLabel("\(text.thinking)…")
                } else {
                    NotchHermesChatBubble(words: chat.reply, mine: false, tail: true, text: text,
                                          messaging: messaging, live: true)
                }
            }
        }
    }


    // MARK: Opening

    /// Before the first message: what the page is for, and the one reason it
    /// could not start, with the way to try again.
    @ViewBuilder private var opening: some View {
        if case .failed(let failure) = chat.state {
            NotchEmptyView(symbol: "exclamationmark.triangle", message: message(failure)) {
                HStack(spacing: 6) {
                    // Messages cannot be read until the grant is given; the
                    // list it lives in is one click away.
                    if failure == .needsFullDiskAccess {
                        NotchPillButton(title: FeatureStrings.notchInstinctChat(l10n.language).openFullDiskAccess) {
                            Permissions.shared.requestFullDiskAccess()
                        }
                    }
                    NotchPillButton(title: text.retry, prominent: true) { chat.retry() }
                }
            }
        } else if !enabled && !preview {
            NotchEmptyView(symbol: symbol, message: text.emptyTitle, mark: mark)
        } else if case .connecting = chat.state {
            NotchEmptyView(symbol: symbol, message: text.connecting, mark: mark)
        } else {
            NotchEmptyView(symbol: symbol, message: text.emptySubtitle, mark: mark)
        }
    }

    private func message(_ failure: NotchHermesChatService.Failure) -> String {
        chat.describe(failure, language: l10n.language)
    }

    private var symbol: String { chat.agent.module.symbol }

    /// VERTUS's own mark where the page would otherwise show a chat glyph.
    private var mark: AnyView? { chat.agent == .vertus ? Self.vertusMark : nil }
    private static let vertusMark = AnyView(VertusMark().fill(style: FillStyle(eoFill: true)))

    // MARK: Band and composer

    /// The island's top row carries only the companion, the agent's face: its
    /// mood already says whether a session is starting, working or stuck, and
    /// the model behind it is not the user's concern (the settings page names
    /// it).
    @ViewBuilder private var status: some View {
        HStack(spacing: 8) {
            // The agent's own mark beside the pages button: which agent this
            // page talks to, at a glance.
            Group {
                if chat.agent == .vertus {
                    VertusWordmark(height: 13)
                } else {
                    InstinctWordmark(height: 13)
                }
            }
            .foregroundStyle(.white.opacity(0.9))
            .help(text.title)
            .accessibilityLabel(text.title)
            if NotchMascotSupport.isEnabled() {
                NotchMascotView(look: NotchMascotSupport.look(), mood: companionMood, size: 20,
                                cue: .celebrate, cueID: chat.completedReplies - (cheeredReplies ?? chat.completedReplies))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Thoughtful while Hermes works, puzzled when it cannot be reached, at
    /// ease otherwise.
    private var companionMood: NotchMascotMood {
        if chat.working { return .thinking }
        if case .failed = chat.state { return .confused }
        if case .connecting = chat.state { return .searching }
        return .idle
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let target = replyTarget, let original = chat.messages.first(where: { $0.id == target }) {
                HStack(spacing: 8) {
                    Rectangle().fill(Color.white.opacity(0.6)).frame(width: 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(messaging.replyingTo)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(Self.firstLine(original.text.isEmpty ? (original.attachments?.first?.name ?? "") : original.text))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    NotchIconButton(symbol: "xmark", title: messaging.cancelReply) { replyTarget = nil }
                }
                .frame(height: 30)
                .padding(.horizontal, 6)
            }
            if !pending.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(pending, id: \.self) { url in
                            NotchPendingAttachment(url: url, remove: messaging.removeAttachment) {
                                pending.removeAll { $0 == url }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 6) {
                Button(action: chooseAttachments) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(messaging.attach)
                .accessibilityLabel(messaging.attach)
                .disabled(preview)
                HStack(alignment: .bottom, spacing: 4) {
                    TextField(listening ? text.listening : text.placeholder, text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .lineLimit(1...4)
                        .focused($typing)
                        .onSubmit(submit)
                        .padding(.vertical, 6)
                        .accessibilityLabel(text.placeholder)
                    sendButton
                }
                .padding(.leading, 11)
                .padding(.trailing, 3)
                .padding(.vertical, 1)
                .frame(minHeight: 30)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            }
        }
    }

    /// Messages' blue arrow, or a stop while the agent writes.
    @ViewBuilder private var sendButton: some View {
        let canSend = !trimmedDraft.isEmpty || !pending.isEmpty
        Button(action: chat.working && !canSend ? { chat.cancel() } : submit) {
            Image(systemName: chat.working && !canSend ? "stop.fill" : "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(canSend || chat.working ? Color.black : Color.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(canSend || chat.working ? NotchMessagesStyle.mine : Color.white.opacity(0.15), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
        .help(chat.working && !canSend ? text.stop : text.send)
        .accessibilityLabel(chat.working && !canSend ? text.stop : text.send)
        .disabled(!canSend && !chat.working)
    }

    /// The plus: files from the Mac, as Messages' attachment button. The
    /// island holds open while the panel is up.
    private func chooseAttachments() {
        let notch = NotchService.shared
        let wasPinned = notch.pinned
        notch.pinned = true
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            if response == .OK {
                for url in panel.urls where !pending.contains(url) { pending.append(url) }
            }
            notch.pinned = wasPinned
            typing = true
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var listening: Bool { voice.phase == .listening }

    private func submit() {
        let words = trimmedDraft
        guard !words.isEmpty || !pending.isEmpty else { return }
        // Sent by hand mid-dictation: the microphone closes without sending
        // the same words a second time.
        voice.cancelDictation()
        draft = ""
        let files = pending
        let target = replyTarget
        pending = []
        replyTarget = nil
        chat.send(words, attachments: files, replyTo: target)
        typing = true
    }
}

/// The island's black and white: your messages light, the agent's dark.
enum NotchMessagesStyle {
    static let mine = Color.white.opacity(0.92)
    static let theirs = Color.white.opacity(0.09)
}

/// One message as Messages shows it: yours on the right in blue, the agent's
/// on the left in grey with its Markdown drawn, files above the words. Under
/// the pointer, Reply and Copy sit beside the bubble.
private struct NotchHermesChatBubble: View {
    let words: String
    let mine: Bool
    var tail = true
    let text: NotchHermesChatStrings
    let messaging: NotchAgentMessagingStrings
    /// A reply still being written: no actions until it is whole.
    var live = false
    /// Tapbacks on the message, drawn on the bubble's top corner.
    var reactions: [NotchHermesChatMessage.Reaction] = []
    var attachments: [NotchHermesChatMessage.Attachment] = []
    var reply: (() -> Void)? = nil
    /// Puts your message back in the field to send again, changed.
    var edit: (() -> Void)? = nil
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if mine { Spacer(minLength: 40) }
            bubbleWithActions
            if !mine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    /// The bubble and its actions answer the pointer as one piece, gap
    /// included: hovering only the words hid the actions as the pointer
    /// crossed the gap on its way to Copy.
    private var bubbleWithActions: some View {
        HStack(alignment: .center, spacing: 6) {
            if mine { actions }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                ForEach(attachments, id: \.self) { file in
                    NotchAttachmentView(attachment: file, openTitle: messaging.open)
                }
                if !words.isEmpty { bubble }
            }
            if !mine { actions }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var bubble: some View {
        content
            .font(.system(size: 12))
            .foregroundStyle(mine ? Color.black.opacity(0.88) : Color.white.opacity(0.9))
            .tint(mine ? Color.black : Color.white)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(mine ? NotchMessagesStyle.mine : NotchMessagesStyle.theirs,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // On the corner away from the bubble's own side, as in
            // Messages, overlapping the edge rather than the words.
            .overlay(alignment: mine ? .topLeading : .topTrailing) { reactionBadge }
            .padding(.top, reactions.isEmpty ? 0 : 9)
    }

    /// The agent's words with their bold, italics, code and links drawn, and
    /// your own as typed. Words that will not read as Markdown show as they are.
    private var content: Text {
        guard !mine, let styled = try? AttributedString(
            markdown: HermesACPSupport.bubbleMarkdown(words),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible)) else { return Text(words) }
        return Text(styled)
    }

    @ViewBuilder private var reactionBadge: some View {
        if !reactions.isEmpty {
            Text(reactions.map(\.emoji).joined())
                .font(.system(size: 11))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(white: 0.22), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
                .offset(x: mine ? -8 : 8, y: -11)
                .accessibilityLabel(reactions.map(\.emoji).joined(separator: " "))
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if let reply { action("arrowshape.turn.up.left", messaging.reply, reply) }
            action("doc.on.doc", text.copyMessage) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(words, forType: .string)
            }
            if let edit { action("pencil", text.editMessage, edit) }
        }
        // Kept in the layout so the bubble does not shift as the pointer
        // comes and goes.
        .opacity(hovered && !live ? 1 : 0)
        .allowsHitTesting(hovered && !live)
    }

    private func action(_ symbol: String, _ title: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Messages' "typing" bubble: three dots pulsing in turn.
struct NotchTypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 2.4
            HStack(spacing: 4) {
                ForEach(0..<3) { dot in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .opacity(reduceMotion ? 0.6 : 0.35 + 0.55 * max(0, sin(phase - Double(dot) * 0.9)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NotchMessagesStyle.theirs, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A file in the thread: a picture shown as itself, anything else as its
/// icon and name. A click opens it.
struct NotchAttachmentView: View {
    let attachment: NotchHermesChatMessage.Attachment
    let openTitle: String
    @State private var image: NSImage?

    var body: some View {
        Button { NSWorkspace.shared.open(attachment.url) } label: {
            if attachment.isImage, let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 180, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.path))
                        .resizable()
                        .frame(width: 26, height: 26)
                    Text(attachment.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: 220, alignment: .leading)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .help("\(openTitle) \(attachment.name)")
        .accessibilityLabel("\(openTitle) \(attachment.name)")
        // Read off the main thread once the bubble is on screen.
        .task(id: attachment.path) {
            guard attachment.isImage else { return }
            image = await NotchAttachmentView.thumbnail(attachment.url)
        }
    }

    private static func thumbnail(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
    }
}

/// A file waiting to be sent, above the field, with its remove button.
private struct NotchPendingAttachment: View {
    let url: URL
    let remove: String
    let onRemove: () -> Void
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    VStack(spacing: 2) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                        Text(url.lastPathComponent).font(.system(size: 8.5)).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(4)
                }
            }
            .frame(width: 52, height: 52)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(white: 0.3))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .help(remove)
            .accessibilityLabel("\(remove) \(url.lastPathComponent)")
        }
        .task(id: url) {
            let ext = url.pathExtension.lowercased()
            guard NotchHermesChatMessage.Attachment.imageExtensions.contains(ext) else { return }
            image = await Self.thumbnail(url)
        }
    }

    private static func thumbnail(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
    }
}

/// Two-finger swipes over the transcript, read from the trackpad's scroll
/// events, since SwiftUI has no swipe for a pointer. Only a mostly sideways
/// swipe is taken; scrolling up and down is left to the transcript.
final class NotchMessagesSwipe {
    enum Phase { case moved(CGFloat), ended }
    /// How far left a bubble is let go to become a reply, and how far it goes.
    static let threshold: CGFloat = 44
    static let limit: CGFloat = 70

    private var monitor: Any?
    private var horizontal = false
    private var decided = false
    private var distance: CGFloat = 0

    func install(_ handler: @escaping (Phase) -> Bool) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            // A mouse wheel has no phases: it only ever scrolls.
            if event.phase.isEmpty && event.momentumPhase.isEmpty { return event }
            if !event.momentumPhase.isEmpty { return self.horizontal ? nil : event }
            if event.phase.contains(.began) {
                self.horizontal = false
                self.decided = false
                self.distance = 0
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                let was = self.horizontal
                self.decided = false
                if was { _ = handler(.ended) }
                return was ? nil : event
            }
            if !self.decided {
                let dx = abs(event.scrollingDeltaX), dy = abs(event.scrollingDeltaY)
                guard dx + dy > 1.5 else { return event }
                self.decided = true
                self.horizontal = dx > dy * 1.5
            }
            guard self.horizontal else { return event }
            // The fingers' own direction, whatever the scrolling preference.
            let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            self.distance += fingers
            if !handler(.moved(self.distance)) {
                self.horizontal = false
                return event
            }
            return nil
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { remove() }
}

/// The VERTUS mark: a pointed-top hexagon with a triangle cut out of it,
/// joining its top corner to its two lower side corners. Drawn rather than
/// shipped as an image so it stays sharp at any size and takes the island's
/// colour; filled even-odd, the triangle is the hole.
struct VertusMark: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        // A regular hexagon's side corners sit a quarter of its height from
        // the top and bottom.
        let top = point(0.5, 0), upperRight = point(1, 0.25), lowerRight = point(1, 0.75)
        let bottom = point(0.5, 1), lowerLeft = point(0, 0.75), upperLeft = point(0, 0.25)
        var path = Path()
        path.addLines([top, upperRight, lowerRight, bottom, lowerLeft, upperLeft])
        path.closeSubpath()
        path.addLines([top, lowerLeft, lowerRight])
        path.closeSubpath()
        return path
    }
}

/// An action the agent is holding until someone says yes: what it wants to
/// do, the command when it adds something, and the answers it accepts. The
/// one-time yes is the prominent answer; a broader yes takes a deliberate
/// reach to the side, and no is always one tap away.
private struct NotchAgentApprovalCard: View {
    let approval: NotchAgentApproval
    let text: NotchHermesChatStrings
    let busy: Bool
    let answer: (NotchAgentApproval.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text.approvalTitle, systemImage: "hand.raised.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.orange)
            Text(approval.headline)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let detail = approval.detail {
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { buttons }
                VStack(alignment: .leading, spacing: 2) { buttons }
            }
            .disabled(busy)
            .opacity(busy ? 0.5 : 1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(text.approvalTitle): \(approval.headline)")
    }

    @ViewBuilder private var buttons: some View {
        if approval.choices.contains(.deny) {
            NotchPillButton(title: text.deny) { answer(.deny) }
        }
        if approval.choices.contains(.once) {
            NotchPillButton(title: text.allowOnce, prominent: true) { answer(.once) }
        }
        if approval.choices.contains(.session) {
            NotchPillButton(title: text.allowSession) { answer(.session) }
        }
        if approval.choices.contains(.always) {
            NotchPillButton(title: text.allowAlways) { answer(.always) }
        }
    }
}

/// Instinct's mark: a serif capital I, its stem pinched at the middle and
/// flaring into the top and bottom serifs. Drawn so it stays sharp and takes
/// the island's colour.
struct InstinctMark: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0, 0))
        path.addLine(to: p(1, 0))
        path.addQuadCurve(to: p(0.68, 0.5), control: p(0.62, 0.08))
        path.addQuadCurve(to: p(1, 1), control: p(0.62, 0.92))
        path.addLine(to: p(0, 1))
        path.addQuadCurve(to: p(0.32, 0.5), control: p(0.38, 0.92))
        path.addQuadCurve(to: p(0, 0), control: p(0.38, 0.08))
        path.closeSubpath()
        return path
    }
}
