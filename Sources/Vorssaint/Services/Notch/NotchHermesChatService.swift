// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's conversation with VERTUS, held while the feature is on.
///
/// When the VERTUS hub is installed the page is one more client of it, so the
/// island talks to the same agent, memory and model as every other surface.
/// Without the hub it falls back to starting `hermes acp` itself and keeping
/// that one conversation for as long as the switch is on. Either way a reply
/// carries over between openings of the island, and turning the switch off
/// ends the connection and drops the transcript.
///
/// The same service carries the Instinct page (`instinct`): a hosted agent
/// the person texts, reached through the Messages thread with its number.
/// Each page has its own feature, switch, shortcut, saved history and
/// transport; the transcript, the turn and the attention it asks for work the
/// same way on both.
///
/// Main thread only, like the island it belongs to. The client reads on a
/// queue of its own and answers here on the main thread.
final class NotchHermesChatService: ObservableObject {
    /// Which conversation an instance carries.
    enum Agent {
        case vertus, instinct

        var feature: AppFeature {
            switch self {
            case .vertus: return AppFeature.notchHermesChat
            case .instinct: return AppFeature.notchInstinctChat
            }
        }

        var enabledKey: String {
            switch self {
            case .vertus: return DefaultsKey.notchHermesChatEnabled
            case .instinct: return DefaultsKey.notchInstinctChatEnabled
            }
        }

        var module: NotchModule {
            switch self {
            case .vertus: return .hermesChat
            case .instinct: return .instinctChat
            }
        }

        var speakRepliesKey: String {
            switch self {
            case .vertus: return DefaultsKey.notchHermesChatSpeakReplies
            case .instinct: return DefaultsKey.notchInstinctSpeakReplies
            }
        }

        var shortcutEnabledKey: String {
            switch self {
            case .vertus: return DefaultsKey.notchHermesChatShortcutEnabled
            case .instinct: return DefaultsKey.notchInstinctShortcutEnabled
            }
        }

        var shortcutKey: String {
            switch self {
            case .vertus: return DefaultsKey.notchHermesChatShortcut
            case .instinct: return DefaultsKey.notchInstinctShortcut
            }
        }

        var shortcutDefault: GlobalShortcut {
            switch self {
            case .vertus: return .vertusChatDefault
            case .instinct: return .instinctChatDefault
            }
        }

        var historyFile: String {
            switch self {
            case .vertus: return "vertus-chat.json"
            case .instinct: return "instinct-chat.json"
            }
        }

        /// VERTUS takes one prompt at a time, so a message typed while it
        /// writes waits its turn. Texts can follow each other freely.
        var holdsMessagesWhileWorking: Bool { self == .vertus }
    }

    static let shared = NotchHermesChatService(agent: .vertus)
    static let instinct = NotchHermesChatService(agent: .instinct)

    let agent: Agent

    enum State: Equatable {
        /// The feature is off, or the island is gone.
        case off
        /// The server is starting and has not opened a session yet.
        case connecting
        /// A session is open and a message can be sent.
        case ready
        /// The server could not be started or has gone away.
        case failed(Failure)
    }

    /// Why there is no conversation, in terms the page can name.
    enum Failure: Equatable {
        /// Nothing runs at the command set in Settings.
        case notFound(String)
        /// The server started but could not be spoken to, in its own words
        /// or the island's.
        case unreachable(String)
        /// The conversation is the Messages thread, which macOS lets this app
        /// read only with Full Disk Access.
        case needsFullDiskAccess
        /// Instinct's number has not been given yet.
        case noNumber
    }

    @Published private(set) var state: State = .off
    @Published private(set) var messages: [NotchHermesChatMessage] = [] {
        // Saved once the earlier history is back, so an early write can never
        // replace the file before it was read.
        didSet { if historyRestored, messages != oldValue { historyStore.save(messages) } }
    }
    private let historyStore: NotchHermesChatHistoryStore
    private var historyRestored = false
    private var historyRequested = false
    /// The other side's own copy of the conversation came in (Instinct's
    /// Messages thread). It is newer than anything saved here, so a saved
    /// history read after it is not put back in front of it.
    private var threadArrived = false
    /// Messages sent from here that Messages has not echoed back yet. The
    /// echo carries the message's lasting identity and takes their place.
    private var unconfirmed: [UUID] = []
    /// When Instinct last answered a turn, so a second message right behind
    /// the first still reads as the answer.
    private var lastAnswer: Date?

    /// Brings back the conversation from earlier launches, once.
    private func restoreHistory() {
        guard !historyRequested else { return }
        historyRequested = true
        historyStore.load { [weak self] saved in
            guard let self else { return }
            self.historyRestored = true
            if self.threadArrived {
                self.historyStore.save(self.messages)
                return
            }
            let merged = NotchHermesChatHistory.restored(saved: saved, current: self.messages)
            if merged != self.messages { self.messages = merged }
        }
    }

    /// Before the app quits: the last few lines must not wait on the debounce.
    func flushHistory() {
        guard historyRestored else { return }
        historyStore.save(messages)
        historyStore.flush()
    }
    /// The reply being written, kept apart from the transcript until its turn
    /// ends so a tool line can land in the order it happened.
    @Published private(set) var reply = ""
    /// Reasoning Hermes streamed for this turn, shown dimmed above the reply.
    @Published private(set) var thinking = ""
    /// A turn is outstanding: the page shows a stop button and a live mark.
    @Published private(set) var working = false
    /// Counts replies that finished, so the companion on the page can cheer
    /// each one as it lands.
    @Published private(set) var completedReplies = 0
    /// Actions the agent will not take without a yes, oldest first.
    @Published private(set) var approvals: [NotchAgentApproval] = []
    /// Approvals answered here whose settling the hub has not reported yet;
    /// their buttons stay disabled so a double tap sends one answer.
    @Published private(set) var answering: Set<String> = []
    @Published private(set) var agentName: String?
    @Published private(set) var modelName: String?

    private var client: NotchAgentChatTransport?
    /// Which client's events count: one replaced by retry() or ended by
    /// stop() can still have events queued on the main thread.
    private var generation = UUID()
    /// The hub run carrying the island's own turn, once the hub names it.
    private var currentRun: String?
    /// The island was pinned open for an approval, so it is unpinned when the
    /// last one settles rather than staying open for good.
    private var pinnedForApproval = false
    /// The latest proactive message's hold; a newer one restarts it.
    private var messagePinGeneration = 0
    /// The message typed while the turn before it was still writing.
    private var heldMessage: String?
    /// Where the hub's agent stream was last heard, kept across the clients
    /// a retry or a send after a failure starts, so the new watch resumes
    /// there and a routine's message sent in the gap still arrives. Only
    /// this app's life: a message VERTUS sent while the app was not running
    /// is not fetched back.
    private let watchCursor = VertusWatchCursor()

    /// ⇧⌘K (VERTUS) or ⇧⌘L (Instinct) by default: opens the island on
    /// this page.
    private let hotkey: QuickToolHotkey
    @Published private(set) var shortcutRegistrationFailed = false

    private init(agent: Agent) {
        self.agent = agent
        historyStore = NotchHermesChatHistoryStore(fileName: agent.historyFile)
        switch agent {
        case .vertus:
            hotkey = QuickToolHotkey(id: 82)
            hotkey.onPress = { NotchService.shared.showHermesChat(toggle: true) }
        case .instinct:
            hotkey = QuickToolHotkey(id: 83)
            hotkey.onPress = { NotchService.shared.showInstinctChat(toggle: true) }
        }
    }

    /// Registers the page's shortcut while the feature, its switch and the
    /// island are on; anything else releases it.
    func syncShortcut() {
        let defaults = UserDefaults.standard
        let enabled = agent.feature.isAvailable && AppFeature.notch.isAvailable
            && defaults.bool(forKey: agent.enabledKey)
            && defaults.bool(forKey: agent.shortcutEnabledKey)
        let shortcut = GlobalShortcut.saved(for: agent.shortcutKey, fallback: agent.shortcutDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: agent.shortcutKey)
    }

    /// The page's words: VERTUS's, or the same page naming Instinct.
    func strings(_ language: AppLanguage) -> NotchHermesChatStrings {
        let words = FeatureStrings.notchHermesChat(language)
        switch agent {
        case .vertus: return words
        case .instinct: return FeatureStrings.notchInstinctChat(language).chat(words)
        }
    }

    private var text: NotchHermesChatStrings { strings(L10n.shared.language) }

    // MARK: Lifecycle

    /// Follows the feature's availability, the switch, and the command in
    /// Settings. Called by the feature runtime and by the settings controls.
    func syncWithPreferences() {
        syncShortcut()
        if agent.feature.isAvailable,
           UserDefaults.standard.bool(forKey: agent.enabledKey) { restoreHistory() }
        guard agent.feature.isAvailable,
              UserDefaults.standard.bool(forKey: agent.enabledKey),
              AppFeature.notch.isAvailable
        else {
            stop()
            return
        }
        switch state {
        case .off:
            connect()
        case .failed:
            // A command that just failed is not tried again on every
            // preference write; the page offers Try Again, and typing a
            // message or changing the command is a try of its own.
            break
        case .connecting, .ready:
            if client == nil { connect() }
        }
    }

    /// Ends the connection. The transcript stays (saved on disk): only the
    /// user's Clear Conversation empties it.
    func stop() {
        client?.end()
        client = nil
        generation = UUID()
        currentRun = nil
        releasePin()
        heldMessage = nil
        unconfirmed = []
        // Switched off is a fresh start: turning it back on does not replay
        // everything VERTUS said in between.
        watchCursor.reset()
        // Nothing keeps listening or reading for a conversation that ended.
        NotchHermesVoiceService.existing?.reset()
        if state != .off { state = .off }
        // The transcript stays: only Clear Conversation empties it.
        if !reply.isEmpty { reply = "" }
        if !thinking.isEmpty { thinking = "" }
        if working { working = false }
        if !approvals.isEmpty { approvals = [] }
        if !answering.isEmpty { answering = [] }
        if agentName != nil { agentName = nil }
        if modelName != nil { modelName = nil }
    }

    /// Tries the command in Settings again, after a failure.
    func retry() {
        client?.end()
        client = nil
        generation = UUID()
        currentRun = nil
        connect()
    }

    private func connect() {
        guard agent.feature.isAvailable, AppFeature.notch.isAvailable else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        if agent == .instinct {
            connectToMessages(home: home)
            return
        }
        // The hub owns VERTUS when it is installed: one agent for every
        // surface, rather than a second engine with its own model and memory.
        if VertusHubSupport.token(home: home) != nil {
            if state != .connecting { state = .connecting }
            let current = UUID()
            generation = current
            let hub = NotchVertusHubClient(home: home, watchCursor: watchCursor) { [weak self] event in
                guard let self, self.generation == current else { return }
                self.handle(event)
            }
            client = hub
            hub.start()
            return
        }
        let command = HermesACPSupport.command(
            UserDefaults.standard.string(forKey: DefaultsKey.notchHermesChatCliPath))
        guard let executable = HermesACPSupport.executable(
            command: command, home: home,
            searchPath: ProcessInfo.processInfo.environment["PATH"])
        else {
            state = .failed(.notFound(command))
            return
        }
        if state != .connecting { state = .connecting }
        let current = UUID()
        generation = current
        let client = NotchHermesChatClient(
            executable: executable,
            environment: HermesACPSupport.environment(executable: executable, searchPath: nil),
            workingDirectory: HermesACPSupport.workingDirectory(home: home)
        ) { [weak self] event in
            guard let self, self.generation == current else { return }
            self.handle(event)
        }
        guard let client else {
            state = .failed(.unreachable(NotchHermesChatClient.Event.unreachable))
            return
        }
        self.client = client
        client.start()
    }

    /// Instinct's thread, through `imsg`: the number from Settings, the tool
    /// wherever Homebrew or the PATH put it.
    private func connectToMessages(home: URL) {
        let number = (UserDefaults.standard.string(forKey: DefaultsKey.notchInstinctNumber) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else {
            state = .failed(.noNumber)
            return
        }
        guard let executable = HermesACPSupport.executable(
            command: InstinctMessagesSupport.defaultCommand, home: home,
            searchPath: ProcessInfo.processInfo.environment["PATH"])
        else {
            state = .failed(.notFound(InstinctMessagesSupport.defaultCommand))
            return
        }
        if state != .connecting { state = .connecting }
        let current = UUID()
        generation = current
        let client = NotchInstinctMessagesClient(
            executable: executable, number: number,
            environment: HermesACPSupport.environment(executable: executable, searchPath: nil)
        ) { [weak self] event in
            guard let self, self.generation == current else { return }
            self.handle(event)
        }
        self.client = client
        client.start()
    }

    // MARK: Sending

    /// Sends a message, starting the server again if it is not running.
    func send(_ message: String) {
        let words = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        guard agent.feature.isAvailable,
              UserDefaults.standard.bool(forKey: agent.enabledKey)
        else { return }
        // A new message talks over the old reply: the reading stops.
        NotchHermesVoiceService.existing?.stopSpeaking()
        // Typing into a conversation that failed is a try of its own.
        if client == nil { connect() }
        // Nothing to send to, and the field the words came from is already
        // cleared: they stay in the conversation with the reason, rather than
        // vanishing and leaving a turn that never ends.
        guard client != nil else {
            append(NotchHermesChatMessage(role: .person, text: words))
            if case .failed(let failure) = state { append(note(failure)) }
            return
        }
        // The turn before this one is still writing; Hermes takes one prompt
        // at a time, so the message waits rather than being dropped.
        if working, agent.holdsMessagesWhileWorking {
            heldMessage = words
            return
        }
        beginTurn(words)
    }

    private func beginTurn(_ words: String) {
        let message = NotchHermesChatMessage(role: .person, text: words)
        unconfirmed.append(message.id)
        messages.append(message)
        messages = HermesACPSupport.trimmed(messages)
        reply = ""
        thinking = ""
        working = true
        client?.send(words)
    }

    /// Stops the turn in flight. Hermes reports it as `cancelled` and keeps
    /// whatever it had already written.
    func cancel() {
        guard working else { return }
        client?.cancel()
    }

    /// Answers an approval card. The card stays, disabled, until the hub
    /// reports the approval settled.
    func answer(_ approval: NotchAgentApproval, _ choice: NotchAgentApproval.Choice) {
        guard approvals.contains(where: { $0.id == approval.id }), !answering.contains(approval.id) else { return }
        answering.insert(approval.id)
        client?.answer(approval.id, choice: choice)
    }

    /// A line of the island's own in the conversation, such as why the
    /// microphone cannot listen.
    func addNote(_ line: String) {
        append(NotchHermesChatMessage(role: .note, text: line))
    }

    /// Empties the transcript without ending the session: Hermes keeps the
    /// conversation on its side, as clearing a terminal would not.
    func clear() {
        // Cleared before the saved history came back: that history goes too.
        historyRestored = true
        historyRequested = true
        messages = []
        historyStore.save([])
        reply = ""
        thinking = ""
        heldMessage = nil
        unconfirmed = []
    }

    // MARK: Events

    private func handle(_ event: NotchHermesChatClient.Event) {
        switch event {
        case .ready(let agent, let model):
            if let agent, !agent.isEmpty { agentName = agent }
            if let model, !model.isEmpty { modelName = model }
        case .session:
            if state != .ready { state = .ready }
            if let held = heldMessage {
                heldMessage = nil
                beginTurn(held)
            }
        case .text(let words):
            reply += words
        case .thought(let words):
            thinking += words
        case .tool(let title):
            // Whatever was written before the tool ran belongs above it.
            commitReply()
            thinking = ""
            append(NotchHermesChatMessage(role: .tool, text: title))
        case .refused(let subject):
            let line = subject.map { text.refusedCommandLine($0) } ?? text.refusedCommand
            append(NotchHermesChatMessage(role: .note, text: line))
        case .approval(let approval):
            guard !approvals.contains(where: { $0.id == approval.id }) else { return }
            // What the agent was saying before it stopped to ask stays above
            // the card, in the order it happened.
            commitReply()
            approvals.append(approval)
            requestAttention()
        case .approvalSettled(let id, let outcome):
            answering.remove(id)
            guard approvals.contains(where: { $0.id == id }) else { return }
            approvals.removeAll { $0.id == id }
            append(NotchHermesChatMessage(role: .note, text: line(for: outcome)))
            if approvals.isEmpty { releasePin() }
        case .approvalAnswerFailed(let id):
            // Still waiting on the hub: the card becomes answerable again.
            answering.remove(id)
        case .runStarted(let run):
            currentRun = run
        case .proactive(let words, let routine):
            // A reply of the island's own turn may be writing below; it
            // lands after this one, in the order the two finished.
            append(NotchHermesChatMessage(role: .proactive, text: words, source: routine))
            reachOut(routine: routine)
        case .finished(let stop):
            finish(stop)
        case .turnFailed(let reason):
            // What was written before the failure stays, above the reason.
            commitReply()
            expireOwnApprovals()
            append(NotchHermesChatMessage(role: .note, text: text.unreachable(reason)))
            finish(.endTurn)
        case .failed(let reason):
            fail(.unreachable(reason))
        case .needsFullDiskAccess:
            fail(.needsFullDiskAccess)
        case .thread(let thread):
            threadArrived = true
            unconfirmed = []
            let merged = InstinctMessagesSupport.merged(thread: thread, current: messages)
            if merged != messages { messages = merged }
        case .delivered(let message):
            confirm(message)
        case .received(let message):
            receive(message)
        case .reacted(let reaction):
            // A tapback changes a line already shown; it is not a reply and
            // asks for no attention.
            let updated = InstinctMessagesSupport.applying(reaction, to: messages)
            if updated != messages { messages = updated }
        }
    }

    /// A message of the person's came back from Messages. One sent from here
    /// takes its lasting identity; one sent from the phone joins the thread.
    private func confirm(_ message: NotchHermesChatMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        if let index = messages.indices.reversed().first(where: {
            unconfirmed.contains(messages[$0].id) && messages[$0].text == message.text
        }) {
            unconfirmed.removeAll { $0 == messages[index].id }
            messages[index] = message
        } else {
            append(message)
        }
    }

    /// A whole message from the agent. While a turn waits (or right behind
    /// the message that answered one) it is the answer; otherwise the agent
    /// wrote on its own and asks for attention as VERTUS's routines do.
    private func receive(_ message: NotchHermesChatMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        if InstinctMessagesSupport.isUnprompted(waiting: working, lastAnswer: lastAnswer, at: message.date) {
            append(message.with(role: .proactive))
            reachOut(routine: nil)
            return
        }
        lastAnswer = message.date
        append(message)
        guard working else { return }
        completedReplies += 1
        reactOutsideConversation(.celebrate)
        working = false
        if let held = heldMessage {
            heldMessage = nil
            beginTurn(held)
        }
    }

    private func finish(_ stop: HermesACPProtocol.Stop) {
        let wrote = !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        commitReply()
        expireOwnApprovals()
        currentRun = nil
        if stop.wasCancelled {
            if !wrote { append(NotchHermesChatMessage(role: .note, text: text.stopped)) }
        } else if let line = stopNote(stop) {
            append(NotchHermesChatMessage(role: .note, text: line))
        }
        if wrote, !stop.wasCancelled {
            completedReplies += 1
            reactOutsideConversation(.celebrate)
        }
        reply = ""
        thinking = ""
        if working { working = false }
        if let held = heldMessage {
            heldMessage = nil
            beginTurn(held)
        }
    }

    /// The reasons a turn can end that the person should hear about. A normal
    /// end says nothing, the reply speaking for itself.
    private func stopNote(_ stop: HermesACPProtocol.Stop) -> String? {
        switch stop {
        case .endTurn, .cancelled: return nil
        case .maxTokens: return text.stoppedAtLimit
        case .maxTurnRequests: return text.stoppedAtStepLimit
        case .refusal: return text.refusedByAgent
        }
    }

    /// Why there is no conversation, as a line of it.
    private func note(_ failure: Failure) -> NotchHermesChatMessage {
        NotchHermesChatMessage(role: .note, text: describe(failure, language: L10n.shared.language))
    }

    /// Why there is no conversation, in the page's words. The Full Disk
    /// Access line names this build, since a developer build is an entry of
    /// its own in System Settings.
    func describe(_ failure: Failure, language: AppLanguage) -> String {
        let text = strings(language)
        switch failure {
        case .notFound(let command): return text.notFound(command)
        case .unreachable(let reason): return text.unreachable(reason)
        case .needsFullDiskAccess:
            let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? AppInfo.name
            return FeatureStrings.notchInstinctChat(language).fullDiskAccess(app)
        case .noNumber: return FeatureStrings.notchInstinctChat(language).noNumber
        }
    }

    private func append(_ message: NotchHermesChatMessage) {
        messages.append(message)
        messages = HermesACPSupport.trimmed(messages)
        // Every finished reply and unasked message passes through here, so
        // this is the one place that reads them aloud when the speaker is on.
        if NotchHermesVoiceSupport.shouldSpeak(
            message.role, enabled: UserDefaults.standard.bool(forKey: agent.speakRepliesKey)) {
            NotchHermesVoiceService.shared.speak(message.text)
        }
    }

    private func commitReply() {
        let words = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        reply = ""
        guard !words.isEmpty else { return }
        append(NotchHermesChatMessage(role: .hermes, text: words))
    }

    /// The island's own turn ended and took its unanswered approvals with it:
    /// the engine withdrew them and failed those actions closed. Approvals of
    /// other turns (a routine, the terminal) are still waiting and stay.
    private func expireOwnApprovals() {
        guard let run = currentRun else { return }
        let own = approvals.filter { $0.runID == run }
        guard !own.isEmpty else { return }
        for approval in own {
            answering.remove(approval.id)
            append(NotchHermesChatMessage(role: .note, text: line(for: .expired)))
        }
        approvals.removeAll { $0.runID == run }
        if approvals.isEmpty { releasePin() }
    }

    private func releasePin() {
        guard pinnedForApproval else { return }
        pinnedForApproval = false
        NotchService.shared.pinned = false
    }

    private func line(for outcome: NotchAgentApproval.Outcome) -> String {
        switch outcome {
        case .allowed: return text.approvalAllowed
        case .denied: return text.approvalDenied
        case .expired: return text.approvalExpired
        }
    }

    /// The agent is parked until someone answers, and the engine fails the
    /// action closed when nobody does: the island opens on the conversation,
    /// without taking the keyboard from whatever is being typed.
    private func requestAttention() {
        let notch = NotchService.shared
        // Pinned, so moving the pointer away or switching apps does not put
        // the card away while the agent waits; unpinned once all settle.
        if !notch.pinned { pinnedForApproval = true }
        if notch.expanded && notch.selected == agent.module {
            notch.pinned = true
            return
        }
        notch.reactMascot(.surprised)
        notch.open(agent.module, pinned: true, takeFocus: false)
    }

    /// VERTUS has something to say, unasked. Nothing waits on it, so unlike
    /// an approval it never pins the island and never takes the page the
    /// person is using: on the conversation the message just lands, on
    /// another page (or the conversation under the sections, the app panel
    /// or the Command Bar) the companion reacts, and a closed island opens on
    /// the conversation without the keyboard. At night, or from a routine
    /// that only keeps VERTUS's house, it just lands.
    private func reachOut(routine: String?) {
        let notch = NotchService.shared
        switch NotchAgentReachOut.attention(
            expanded: notch.expanded,
            onChat: notch.selected == agent.module,
            covered: notch.showingSections || notch.showingAppPanel || notch.showingCommandBar,
            hour: Calendar.current.component(.hour, from: Date()),
            routine: routine) {
        case .append:
            return
        case .nudge:
            notch.reactMascot(.perk)
        case .open:
            notch.reactMascot(.perk)
            // Opened with the pointer elsewhere, an unpinned island counts as
            // opened by hover and collapses at once, so the message would
            // land unseen. It holds open like a notification, then lets go
            // unless something else (an approval, the user) is keeping it.
            let wasPinned = notch.pinned
            notch.open(agent.module, pinned: true, takeFocus: false)
            guard !wasPinned else { return }
            messagePinGeneration += 1
            let generation = messagePinGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchAgentReachOut.holdOpen) { [weak self] in
                guard let self, self.messagePinGeneration == generation, !self.pinnedForApproval else { return }
                NotchService.shared.pinned = false
            }
        }
    }

    /// The companion is the agent's face. On the conversation's page it acts
    /// there; anywhere else it tells you in the island that Hermes answered,
    /// or could not.
    private func reactOutsideConversation(_ reaction: NotchMascotReaction) {
        let notch = NotchService.shared
        guard !(notch.expanded && notch.selected == agent.module) else { return }
        notch.reactMascot(reaction)
    }

    private func fail(_ failure: Failure) {
        reactOutsideConversation(.confused)
        client?.end()
        client = nil
        if working { working = false }
        commitReply()
        state = .failed(failure)
    }
}
