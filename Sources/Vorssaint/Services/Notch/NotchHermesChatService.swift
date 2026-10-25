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
/// Main thread only, like the island it belongs to. The client reads on a
/// queue of its own and answers here on the main thread.
final class NotchHermesChatService: ObservableObject {
    static let shared = NotchHermesChatService()

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
    }

    @Published private(set) var state: State = .off
    @Published private(set) var messages: [NotchHermesChatMessage] = []
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
    /// The message typed while the turn before it was still writing.
    private var heldMessage: String?

    private init() {}

    private var text: NotchHermesChatStrings {
        FeatureStrings.notchHermesChat(L10n.shared.language)
    }

    // MARK: Lifecycle

    /// Follows the feature's availability, the switch, and the command in
    /// Settings. Called by the feature runtime and by the settings controls.
    func syncWithPreferences() {
        guard AppFeature.notchHermesChat.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchHermesChatEnabled),
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

    /// Ends the conversation and forgets it. The transcript is dropped too:
    /// an agent switched off should leave nothing running or held in memory.
    func stop() {
        client?.end()
        client = nil
        heldMessage = nil
        if state != .off { state = .off }
        if !messages.isEmpty { messages = [] }
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
        connect()
    }

    private func connect() {
        guard AppFeature.notchHermesChat.isAvailable, AppFeature.notch.isAvailable else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        // The hub owns VERTUS when it is installed: one agent for every
        // surface, rather than a second engine with its own model and memory.
        if VertusHubSupport.token(home: home) != nil {
            if state != .connecting { state = .connecting }
            let hub = NotchVertusHubClient(home: home) { [weak self] event in self?.handle(event) }
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
        let client = NotchHermesChatClient(
            executable: executable,
            environment: HermesACPSupport.environment(executable: executable, searchPath: nil),
            workingDirectory: HermesACPSupport.workingDirectory(home: home)
        ) { [weak self] event in
            self?.handle(event)
        }
        guard let client else {
            state = .failed(.unreachable(NotchHermesChatClient.Event.unreachable))
            return
        }
        self.client = client
        client.start()
    }

    // MARK: Sending

    /// Sends a message, starting the server again if it is not running.
    func send(_ message: String) {
        let words = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        guard AppFeature.notchHermesChat.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchHermesChatEnabled)
        else { return }
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
        if working {
            heldMessage = words
            return
        }
        beginTurn(words)
    }

    private func beginTurn(_ words: String) {
        messages.append(NotchHermesChatMessage(role: .person, text: words))
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

    /// Empties the transcript without ending the session: Hermes keeps the
    /// conversation on its side, as clearing a terminal would not.
    func clear() {
        messages = []
        reply = ""
        thinking = ""
        heldMessage = nil
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
        case .finished(let stop):
            finish(stop)
        case .turnFailed(let reason):
            // What was written before the failure stays, above the reason.
            commitReply()
            append(NotchHermesChatMessage(role: .note, text: text.unreachable(reason)))
            finish(.endTurn)
        case .failed(let reason):
            fail(.unreachable(reason))
        }
    }

    private func finish(_ stop: HermesACPProtocol.Stop) {
        let wrote = !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        commitReply()
        // A turn that ended took its unanswered approvals with it: the engine
        // withdrew them and fails those actions closed.
        for _ in approvals { append(NotchHermesChatMessage(role: .note, text: line(for: .expired))) }
        if !approvals.isEmpty { approvals = [] }
        if !answering.isEmpty { answering = [] }
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
        switch failure {
        case .notFound(let command): return NotchHermesChatMessage(role: .note, text: text.notFound(command))
        case .unreachable(let reason): return NotchHermesChatMessage(role: .note, text: text.unreachable(reason))
        }
    }

    private func append(_ message: NotchHermesChatMessage) {
        messages.append(message)
        messages = HermesACPSupport.trimmed(messages)
    }

    private func commitReply() {
        let words = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        reply = ""
        guard !words.isEmpty else { return }
        append(NotchHermesChatMessage(role: .hermes, text: words))
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
        if notch.expanded && notch.selected == .hermesChat { return }
        notch.reactMascot(.surprised)
        notch.open(.hermesChat, takeFocus: false)
    }

    /// The companion is the agent's face. On the conversation's page it acts
    /// there; anywhere else it tells you in the island that Hermes answered,
    /// or could not.
    private func reactOutsideConversation(_ reaction: NotchMascotReaction) {
        let notch = NotchService.shared
        guard !(notch.expanded && notch.selected == .hermesChat) else { return }
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
