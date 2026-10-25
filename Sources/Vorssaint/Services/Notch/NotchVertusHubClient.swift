// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the island's chat page needs from whatever carries its conversation:
/// the `hermes acp` server it starts itself, or the VERTUS hub already running.
protocol NotchAgentChatTransport: AnyObject {
    func start()
    func send(_ text: String)
    func cancel()
    func end()
    /// Answers an approval the agent is waiting on.
    func answer(_ approval: String, choice: NotchAgentApproval.Choice)
}

/// `hermes acp` never reaches an approval card: the island refuses its
/// permission requests on arrival, so there is nothing to answer.
extension NotchHermesChatClient: NotchAgentChatTransport {
    func answer(_ approval: String, choice: NotchAgentApproval.Choice) {}
}

/// The island's conversation with the VERTUS hub. The hub keeps the agent's
/// session, memory and model on its side, so a turn here is one queued prompt
/// and the stream of its run; nothing is started or kept alive by the island.
///
/// Like the Hermes client, nothing here touches the island's state: events
/// arrive on the main thread and the service decides what they mean.
final class NotchVertusHubClient: NSObject, NotchAgentChatTransport, URLSessionDataDelegate {
    /// A run may think and use tools for minutes between events; the stream
    /// gives up only when the hub has said nothing for this long.
    private static let streamIdleTimeout: TimeInterval = 900
    private static let requestTimeout: TimeInterval = 15
    /// How long a dropped watch waits before listening again.
    private static let watchRetryDelay: TimeInterval = 5

    typealias Event = NotchHermesChatClient.Event

    private let home: URL
    private let onEvent: (Event) -> Void
    private let queue = DispatchQueue(label: "com.vorssaint.notch.vertus-hub")
    private lazy var session: URLSession = {
        let operations = OperationQueue()
        operations.maxConcurrentOperationCount = 1
        operations.underlyingQueue = queue
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.streamIdleTimeout
        return URLSession(configuration: configuration, delegate: self, delegateQueue: operations)
    }()

    // Only touched on `queue`.
    private var token: String?
    private var run: String?
    private var stream: URLSessionDataTask?
    private var reader = VertusHubSupport.LineReader()
    /// The agent-wide stream, held for the whole conversation, from which
    /// only approvals are taken: a turn the island did not start can still
    /// stop and ask, and nobody would see the card otherwise.
    private var watch: URLSessionDataTask?
    private var watchReader = VertusHubSupport.LineReader()
    /// The last event the watch saw, to resume after it on reconnect.
    private var watchSeq: Int?
    /// Stop pressed while the prompt was still being queued: sent as soon as
    /// the hub names the run.
    private var cancelPending = false
    private var turnEnded = false
    private var ended = false

    init(home: URL, onEvent: @escaping (Event) -> Void) {
        self.home = home
        self.onEvent = onEvent
    }

    /// Reads the hub's token and asks which model its agent answers with.
    /// A hub that does not answer fails the page, as a server that will not
    /// start does.
    func start() {
        queue.async {
            guard !self.ended else { return }
            guard let token = VertusHubSupport.token(home: self.home) else {
                self.finish(.failed("The VERTUS hub is not installed."))
                return
            }
            self.token = token
            var request = VertusHubSupport.request("api/agents", token: token)
            request.timeoutInterval = Self.requestTimeout
            self.session.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                self.queue.async {
                    guard !self.ended else { return }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard error == nil, (200..<300).contains(status) else {
                        self.finish(.failed(Self.reason(error, status: status)))
                        return
                    }
                    self.emit(.ready(agent: VertusHubSupport.agentName,
                                     model: VertusHubSupport.modelName(from: data)))
                    self.emit(.session)
                    self.listen()
                }
            }.resume()
        }
    }

    func send(_ text: String) {
        queue.async {
            guard !self.ended, let token = self.token else { return }
            var request = VertusHubSupport.prompt(text, token: token)
            request.timeoutInterval = Self.requestTimeout
            self.turnEnded = false
            self.cancelPending = false
            self.session.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                self.queue.async {
                    guard !self.ended else { return }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if let error {
                        self.endTurn(.turnFailed(Self.reason(error, status: status)))
                        return
                    }
                    switch VertusHubSupport.runID(from: data, status: status) {
                    case .success(let run): self.follow(run, token: token)
                    case .failure(let failure): self.endTurn(.turnFailed(failure.reason))
                    }
                }
            }.resume()
        }
    }

    /// Asks the hub to stop the run; it answers with a `cancelled` event,
    /// which ends the turn the usual way.
    func cancel() {
        queue.async {
            guard !self.ended, !self.turnEnded, let token = self.token else { return }
            guard let run = self.run else {
                self.cancelPending = true
                return
            }
            self.session.dataTask(with: VertusHubSupport.cancel(run: run, token: token)).resume()
        }
    }

    /// The hub routes the answer to the waiting engine; the stream then
    /// reports it settled, which is what clears the card. An approval the hub
    /// says is already settled is cleared with how it ended; an answer that
    /// did not get through leaves the card answerable.
    func answer(_ approval: String, choice: NotchAgentApproval.Choice) {
        queue.async {
            guard !self.ended, let token = self.token else { return }
            var request = VertusHubSupport.answer(approval, choice: choice, token: token)
            request.timeoutInterval = Self.requestTimeout
            self.session.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                self.queue.async {
                    guard !self.ended else { return }
                    let status = error == nil ? (response as? HTTPURLResponse)?.statusCode ?? 0 : 0
                    switch VertusHubSupport.answerResult(status: status, data: data) {
                    case .accepted: break
                    case .settled(let outcome): self.emit(.approvalSettled(approval, outcome))
                    case .retry: self.emit(.approvalAnswerFailed(approval))
                    }
                }
            }.resume()
        }
    }

    /// Stops listening. A run in flight keeps going on the hub, which owns it.
    func end() {
        queue.async {
            guard !self.ended else { return }
            self.ended = true
            self.stream?.cancel()
            self.stream = nil
            self.watch?.cancel()
            self.watch = nil
            self.session.invalidateAndCancel()
        }
    }

    // MARK: Streaming

    private func follow(_ run: String, token: String) {
        self.run = run
        emit(.runStarted(run))
        reader = VertusHubSupport.LineReader()
        let task = session.dataTask(with: VertusHubSupport.events(run: run, token: token))
        stream = task
        task.resume()
        if cancelPending {
            cancelPending = false
            session.dataTask(with: VertusHubSupport.cancel(run: run, token: token)).resume()
        }
    }

    /// Holds the agent-wide watch. The first time, it starts from the ledger's
    /// waiting approvals, which a live stream cannot replay; after a drop it
    /// resumes from the last event it saw, so nothing raised in between is
    /// missed.
    private func listen() {
        guard !ended, watch == nil, let token else { return }
        watchReader = VertusHubSupport.LineReader()
        if let since = watchSeq {
            openWatch(VertusHubSupport.watch(token: token, since: since))
            return
        }
        var pending = VertusHubSupport.pendingApprovals(token: token)
        pending.timeoutInterval = Self.requestTimeout
        session.dataTask(with: pending) { [weak self] data, response, _ in
            guard let self else { return }
            self.queue.async {
                guard !self.ended, self.watch == nil else { return }
                if let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
                    for approval in VertusHubSupport.pendingApprovals(from: data) { self.emit(.approval(approval)) }
                }
                self.openWatch(VertusHubSupport.watch(token: token))
            }
        }.resume()
    }

    private func openWatch(_ request: URLRequest) {
        let task = session.dataTask(with: request)
        watch = task
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if dataTask === watch, !ended {
            for line in watchReader.append(data) {
                if let seq = VertusHubSupport.sequence(line: line) { watchSeq = max(watchSeq ?? 0, seq) }
                switch VertusHubSupport.event(line: line, run: nil) {
                case .approval(let approval): emit(.approval(approval))
                case .approvalSettled(let id, let outcome): emit(.approvalSettled(id, outcome))
                default: break
                }
            }
            return
        }
        guard dataTask === stream, !ended, let run else { return }
        for line in reader.append(data) {
            switch VertusHubSupport.event(line: line, run: run) {
            case .text(let words): emit(.text(words))
            case .tool(let name): emit(.tool(name))
            case .done: endTurn(.finished(.endTurn))
            case .cancelled: endTurn(.finished(.cancelled))
            case .error(let reason): endTurn(.turnFailed(reason))
            case .approval(let approval): emit(.approval(approval))
            case .approvalSettled(let id, let outcome): emit(.approvalSettled(id, outcome))
            case .ignored, nil: break
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if task === watch {
            // A hub restart or an idle timeout ends the watch; listen again.
            watch = nil
            guard !ended else { return }
            queue.asyncAfter(deadline: .now() + Self.watchRetryDelay) { [weak self] in self?.listen() }
            return
        }
        guard task === stream, !ended else { return }
        stream = nil
        // The hub closes a run's stream after its terminal event; closing
        // before one means the run's end was never heard.
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        endTurn(.turnFailed(error == nil && (200..<300).contains(status)
                            ? "The reply ended before it finished."
                            : Self.reason(error, status: status)))
    }

    /// One terminal event per turn: the hub can repeat `done`, and the stream
    /// closing after it is not a failure.
    private func endTurn(_ event: Event) {
        guard !turnEnded else { return }
        turnEnded = true
        run = nil
        stream?.cancel()
        stream = nil
        emit(event)
    }

    /// The conversation cannot go on. The session is released here too: the
    /// service's later end() finds the client already ended, and a session
    /// left alive would keep this client (its delegate) alive with it.
    private func finish(_ event: Event) {
        guard !ended else { return }
        ended = true
        stream?.cancel()
        stream = nil
        watch?.cancel()
        watch = nil
        session.invalidateAndCancel()
        emit(event)
    }

    private static func reason(_ error: Error?, status: Int) -> String {
        if let error = error as? URLError, error.code == .cannotConnectToHost {
            return "The VERTUS hub is not running."
        }
        if let error { return error.localizedDescription }
        return status == 0 ? NotchHermesChatClient.Event.unreachable : "HTTP \(status)"
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [onEvent] in onEvent(event) }
    }
}
