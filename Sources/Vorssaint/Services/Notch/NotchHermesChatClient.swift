// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// One live ACP conversation with Hermes Agent: the `hermes acp` server is
/// started once, kept for the whole chat, and fed one JSON line at a time.
///
/// The difference from `AgentCLIConversation` is that a chat is not one
/// question and one answer. Hermes streams its reply as notifications while a
/// prompt is outstanding, and it asks permission before running a command, so
/// the connection has to stay open and answer what the server asks. Nothing
/// here touches the island's state: events are delivered on the main thread
/// and the service decides what they mean.
final class NotchHermesChatClient {
    /// A turn is allowed to run long (a model can think for minutes) but not
    /// forever, so a wedged server leaves no turn spinning.
    private static let handshakeTimeout: TimeInterval = 40
    private static let promptTimeout: TimeInterval = 900

    enum Event {
        /// `initialize` was answered; the agent names itself and its model.
        case ready(agent: String?, model: String?)
        /// `session/new` was answered; prompts can be sent.
        case session
        /// Words of the reply as they stream in.
        case text(String)
        /// Reasoning Hermes chose to stream, shown apart from the reply.
        case thought(String)
        /// A tool the agent finished, named without its output.
        case tool(String)
        /// The turn ended, for one of the protocol's reasons.
        case finished(HermesACPProtocol.Stop)
        /// A command was refused, because the island never approves one.
        case refused(String?)
        /// The agent waits for a yes before acting (the VERTUS hub asks;
        /// a bare `hermes acp` is refused instead, above).
        case approval(NotchAgentApproval)
        /// An approval was answered, here or on another surface, or expired.
        case approvalSettled(String, NotchAgentApproval.Outcome)
        /// An answer did not reach the hub; the approval is still waiting.
        case approvalAnswerFailed(String)
        /// The hub named the run carrying the turn just sent.
        case runStarted(String)
        /// One turn could not finish, but the conversation goes on; the text
        /// is why. The hub reports a run's own failure this way.
        case turnFailed(String)
        /// The conversation cannot go on; the text is why.
        case failed(String)

        /// What a failed start reads as when the server said nothing.
        static let unreachable = "VERTUS did not answer."
    }

    private enum Request { case initialize, session, prompt }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let queue = DispatchQueue(label: "com.vorssaint.notch.hermes-chat")
    private let workingDirectory: String
    private let onEvent: (Event) -> Void

    // Only touched on `queue`.
    private var reader = HermesACPLineReader()
    private var nextID = 0
    private var pending: [Int: Request] = [:]
    private var session: String?
    private var queuedPrompt: String?
    private var timeoutWork: DispatchWorkItem?
    private var started = false
    private var ended = false

    init?(executable: URL, environment: [String: String], workingDirectory: String,
          onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        self.workingDirectory = workingDirectory
        process.executableURL = executable
        process.arguments = HermesACPSupport.arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        // Hermes logs every plugin it loads to stderr; none of it belongs in
        // the app's own log, and a full pipe would stall the server.
        process.standardError = FileHandle.nullDevice
        // A server that exits early fails a write instead of ending the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return nil }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.serverExited() }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                queue.async { self.serverExited() }
                return
            }
            queue.async { self.receive(chunk) }
        }
    }

    /// Starts the server and the handshake. Safe to call once.
    func start() {
        queue.async {
            guard !self.started else { return }
            self.started = true
            do {
                try self.process.run()
            } catch {
                self.finish(.failed(error.localizedDescription))
                return
            }
            self.beginHandshake()
        }
    }

    /// Sends one message. A message typed before the session exists waits for
    /// it rather than failing, since the handshake takes a moment.
    func send(_ text: String) {
        queue.async {
            guard !self.ended else { return }
            guard let session = self.session else {
                self.queuedPrompt = text
                return
            }
            self.writePrompt(text, session: session)
        }
    }

    /// Ends the turn politely, which Hermes reports as a `cancelled` stop.
    func cancel() {
        queue.async {
            guard !self.ended, let session = self.session else { return }
            self.write(HermesACPProtocol.cancel(session: session))
        }
    }

    /// Ends the conversation. A server that lingers is stopped.
    func end() {
        let child = process
        queue.async {
            guard !self.ended else { return }
            self.ended = true
            self.timeoutWork?.cancel()
            self.output.fileHandleForReading.readabilityHandler = nil
            try? self.input.fileHandleForWriting.close()
        }
        guard child.isRunning, child.processIdentifier > 0 else { return }
        let leaves = ProcessInfo.processInfo.systemUptime + 0.4
        while child.isRunning, ProcessInfo.processInfo.systemUptime < leaves { usleep(10_000) }
        if child.isRunning { child.terminate() }
        let stops = ProcessInfo.processInfo.systemUptime + 0.6
        while child.isRunning, ProcessInfo.processInfo.systemUptime < stops { usleep(10_000) }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
    }

    // MARK: Handshake

    private func beginHandshake() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        nextID += 1
        pending[nextID] = .initialize
        write(HermesACPProtocol.initialize(id: nextID, clientVersion: version))
        schedule(Self.handshakeTimeout) { [weak self] in
            self?.finish(.failed(Event.unreachable))
        }
    }

    private func beginSession() {
        nextID += 1
        pending[nextID] = .session
        write(HermesACPProtocol.newSession(id: nextID, cwd: workingDirectory))
    }

    private func writePrompt(_ text: String, session: String) {
        nextID += 1
        pending[nextID] = .prompt
        write(HermesACPProtocol.prompt(id: nextID, session: session, text: text))
        schedule(Self.promptTimeout) { [weak self] in
            self?.finish(.failed(Event.unreachable))
        }
    }

    /// One deadline at a time: the handshake's, then the turn's.
    private func schedule(_ deadline: TimeInterval, then action: @escaping () -> Void) {
        timeoutWork?.cancel()
        let work = DispatchWorkItem(block: action)
        timeoutWork = work
        queue.asyncAfter(deadline: .now() + deadline, execute: work)
    }

    // MARK: Reading

    private func receive(_ chunk: Data) {
        guard !ended else { return }
        for frame in reader.append(chunk) { handle(frame) }
        if reader.overflowed { finish(.failed("VERTUS wrote more than a conversation.")) }
    }

    private func handle(_ frame: HermesACPFrame) {
        switch frame.kind {
        case .notification:
            guard frame.method == "session/update" else { return }
            switch HermesACPProtocol.Update.parse(frame.params) {
            case .text(let text): emit(.text(text))
            case .thought(let text): emit(.thought(text))
            case .toolFinished(let title): emit(.tool(title))
            case .toolStarted, .ignored: break
            }
        case .request:
            answer(frame)
        case .failure:
            finish(.failed(frame.failure ?? Event.unreachable))
        case .response:
            guard let id = frame.id, let request = pending.removeValue(forKey: id) else { return }
            switch request {
            case .initialize:
                timeoutWork?.cancel()
                emit(.ready(agent: HermesACPProtocol.agentName(of: frame.result),
                            model: HermesACPProtocol.modelName(of: frame.result)))
                beginSession()
            case .session:
                timeoutWork?.cancel()
                guard let id = HermesACPProtocol.sessionId(of: frame.result) else {
                    finish(.failed("VERTUS started no session."))
                    return
                }
                session = id
                emit(.session)
                if let queued = queuedPrompt {
                    queuedPrompt = nil
                    writePrompt(queued, session: id)
                }
            case .prompt:
                timeoutWork?.cancel()
                emit(.finished(HermesACPProtocol.Stop.parse(frame.result)))
            }
        }
    }

    /// Hermes asks before a dangerous command, and asks for files and a
    /// terminal it was told the island does not have. A permission request is
    /// refused; anything else is an error the protocol allows.
    private func answer(_ frame: HermesACPFrame) {
        guard let id = frame.id else { return }
        if frame.method == "session/request_permission" {
            let options = frame.params["options"] as? [[String: Any]] ?? []
            write(HermesACPProtocol.permissionReply(
                id: id, optionId: HermesACPProtocol.refusalOption(in: options)))
            emit(.refused(HermesACPProtocol.permissionSubject(frame.params)))
            return
        }
        write([
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": -32601, "message": "The island does not provide \(frame.method ?? "that")."],
        ])
    }

    private func write(_ message: [String: Any]) {
        guard !ended, let data = HermesACPProtocol.encode(message) else { return }
        var line = data
        line.append(0x0A)
        do {
            try input.fileHandleForWriting.write(contentsOf: line)
        } catch {
            finish(.failed(error.localizedDescription))
        }
    }

    private func serverExited() {
        guard !ended else { return }
        finish(.failed(Event.unreachable))
    }

    /// The conversation is over: everything outstanding is dropped and one
    /// last event tells the page why.
    private func finish(_ event: Event) {
        guard !ended else { return }
        ended = true
        timeoutWork?.cancel()
        pending.removeAll()
        emit(event)
    }

    /// Events reach the island on the main thread, in the order they arrived.
    private func emit(_ event: Event) {
        DispatchQueue.main.async { [onEvent] in onEvent(event) }
    }
}
