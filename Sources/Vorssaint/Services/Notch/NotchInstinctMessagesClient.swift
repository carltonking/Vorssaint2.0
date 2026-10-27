// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's conversation with Instinct, a hosted agent the person texts.
/// Instinct has no API of its own to talk to, but it answers iMessages, so the
/// page is the Messages thread with its number: read with `imsg history`,
/// followed with `imsg watch`, and written to with `imsg send`. It is the same
/// thread as on the person's phone, so whatever was said there shows here.
///
/// A turn is one message sent; it ends when Instinct writes back. Instinct
/// asks for approval in plain words, so there are no approval cards to answer.
/// Like the other transports nothing here touches the island's state: events
/// arrive on the main thread and the service decides what they mean.
final class NotchInstinctMessagesClient: NotchAgentChatTransport {
    typealias Event = NotchHermesChatClient.Event
    typealias Support = InstinctMessagesSupport

    /// Reading the chat list or a thread is a database query; one that takes
    /// longer than this is not going to answer.
    private static let readTimeout: TimeInterval = 20
    /// Messages may take a moment to hand the text to iMessage.
    private static let sendTimeout: TimeInterval = 45
    /// How long a dropped watch waits before listening again.
    private static let watchRetryDelay: TimeInterval = 5
    /// A watch line longer than this is not a message; it is dropped rather
    /// than held.
    private static let maximumLine = 4 * 1024 * 1024

    private let executable: URL
    private let number: String
    private let environment: [String: String]
    private let onEvent: (Event) -> Void
    private let queue = DispatchQueue(label: "com.vorssaint.notch.instinct")
    /// Sends run apart from `queue`, so a slow `imsg send` never holds up a
    /// reply the watch is reading.
    private let sendQueue = DispatchQueue(label: "com.vorssaint.notch.instinct-send")

    // Only touched on `queue`.
    private var chatID: Int64?
    /// The newest database row heard, so a watch started again resumes after
    /// it and nothing sent in the gap is lost.
    private var lastRowID: Int64?
    /// Messages already passed on, by guid: history and the watch overlap.
    private var seen = Set<String>()
    private var watch: Process?
    private var watchBuffer = Data()
    /// What the watch said that was not a message, for why it stopped.
    private var watchNoise = ""
    private var replyTimeout: DispatchWorkItem?
    private var started = false
    private var ended = false

    init(executable: URL, number: String, environment: [String: String], onEvent: @escaping (Event) -> Void) {
        self.executable = executable
        self.number = number
        self.environment = environment
        self.onEvent = onEvent
    }

    /// Finds the thread, reads it, and starts listening. Safe to call once.
    func start() {
        queue.async {
            guard !self.started, !self.ended else { return }
            self.started = true
            self.loadThread()
        }
    }

    func send(_ text: String) {
        send(text, attachments: [])
    }

    /// The words as one text, then each file as one of its own, as Messages
    /// sends them; the first that fails ends the turn with its reason.
    func send(_ text: String, attachments: [URL]) {
        var sends: [[String]] = []
        if !text.isEmpty { sends.append(Support.sendArguments(number: number, text: text)) }
        sends += attachments.map { Support.sendArguments(number: number, file: $0) }
        guard !sends.isEmpty else { return }
        sendQueue.async {
            var failure: NotchHermesChatClient.Event?
            for arguments in sends {
                let result = self.run(arguments, timeout: Self.sendTimeout)
                if result.timedOut {
                    failure = .turnFailed("imsg send did not finish.")
                } else if result.status != 0, !Support.probablySent(result.output) {
                    failure = Support.isUnreadable(result.output) ? .needsFullDiskAccess
                        : .turnFailed(Support.reason(result.output))
                }
                if failure != nil { break }
            }
            self.queue.async {
                guard !self.ended else { return }
                if let failure {
                    self.emit(failure)
                } else {
                    self.waitForReply()
                }
            }
        }
    }

    /// Nothing can unsend a text: stopping only stops waiting for the answer,
    /// which still arrives (as Instinct writing) if it comes.
    func cancel() {
        queue.async {
            guard !self.ended else { return }
            self.replyTimeout?.cancel()
            self.replyTimeout = nil
            self.emit(.finished(.cancelled))
        }
    }

    func end() {
        queue.async {
            guard !self.ended else { return }
            self.ended = true
            self.replyTimeout?.cancel()
            self.stopWatch()
        }
    }

    /// Instinct asks in plain words; there is no approval to answer.
    func answer(_ approval: String, choice: NotchAgentApproval.Choice) {}

    // MARK: Reading

    private func loadThread() {
        let chats = run(Support.chatsArguments(), timeout: Self.readTimeout)
        guard !ended else { return }
        if Support.isUnreadable(chats.output) { emit(.needsFullDiskAccess); return }
        guard chats.status == 0, !chats.timedOut else {
            emit(.failed(chats.timedOut ? "imsg did not answer." : Support.reason(chats.output)))
            return
        }
        chatID = Support.chat(for: number, in: Support.chats(in: chats.output))?.id
        var thread: [InstinctMessageRecord] = []
        if let chatID {
            let history = run(Support.historyArguments(chatID: chatID), timeout: Self.readTimeout)
            guard !ended else { return }
            if Support.isUnreadable(history.output) { emit(.needsFullDiskAccess); return }
            thread = Support.records(in: history.output).filter { Support.belongs($0, to: number) }
        }
        for record in thread { note(record) }
        emit(.session)
        // A number never texted yet has no thread: an empty one is still the
        // thread, and the first message sent starts it.
        emit(.thread(thread.map { Support.message($0) }))
        startWatch()
    }

    private func note(_ record: InstinctMessageRecord) {
        seen.insert(record.guid)
        lastRowID = max(lastRowID ?? record.rowID, record.rowID)
    }

    // MARK: Watching

    private func startWatch() {
        guard !ended else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = Support.watchArguments(chatID: chatID, number: number, after: lastRowID)
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        // Errors come on stderr; they explain a watch that stops (Full Disk
        // Access taken away), so they are read with the messages.
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            self?.queue.async { self?.receive(chunk, from: process) }
        }
        process.terminationHandler = { [weak self] finished in
            self?.queue.async { self?.watchEnded(finished) }
        }
        watchBuffer = Data()
        watchNoise = ""
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            emit(.failed(error.localizedDescription))
            return
        }
        watch = process
    }

    private func receive(_ chunk: Data, from process: Process) {
        guard !ended, process === watch else { return }
        watchBuffer.append(chunk)
        while let newline = watchBuffer.firstIndex(of: 0x0A) {
            let line = String(decoding: watchBuffer[watchBuffer.startIndex..<newline], as: UTF8.self)
            watchBuffer = Data(watchBuffer[watchBuffer.index(after: newline)...])
            handle(line)
        }
        if watchBuffer.count > Self.maximumLine { watchBuffer = Data() }
    }

    private func handle(_ line: String) {
        if let reaction = Support.reaction(fromLine: line) {
            guard Support.belongs(reaction, to: number), seen.insert(reaction.guid).inserted else { return }
            lastRowID = max(lastRowID ?? reaction.rowID, reaction.rowID)
            emit(.reacted(reaction))
            return
        }
        guard let record = Support.record(fromLine: line) else {
            let words = line.trimmingCharacters(in: .whitespaces)
            if !words.isEmpty { watchNoise = String((watchNoise + "\n" + words).suffix(2_000)) }
            return
        }
        guard Support.belongs(record, to: number), !seen.contains(record.guid) else { return }
        note(record)
        if record.fromMe {
            emit(.delivered(Support.message(record)))
        } else {
            replyTimeout?.cancel()
            replyTimeout = nil
            emit(.received(Support.message(record)))
        }
    }

    private func watchEnded(_ process: Process) {
        guard !ended, process === watch else { return }
        watch = nil
        if Support.isUnreadable(watchNoise) {
            emit(.needsFullDiskAccess)
            return
        }
        // A watch that drops (Messages restarted, the database moved under
        // it) listens again after the last message it heard.
        queue.asyncAfter(deadline: .now() + Self.watchRetryDelay) { [weak self] in
            guard let self, !self.ended, self.watch == nil else { return }
            self.startWatch()
        }
    }

    private func stopWatch() {
        guard let process = watch else { return }
        watch = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    // MARK: Turns

    /// The turn waits for Instinct's answer, but not forever: a reply that
    /// never comes stops showing as awaited.
    private func waitForReply() {
        replyTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.ended else { return }
            self.replyTimeout = nil
            self.emit(.finished(.endTurn))
        }
        replyTimeout = work
        queue.asyncAfter(deadline: .now() + Support.replyTimeout, execute: work)
    }

    // MARK: Helpers

    private func run(_ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String, timedOut: Bool) {
        let result = BoundedProcessRunner.run(executable.path, arguments, timeout: timeout,
                                              maxOutputBytes: 8 * 1024 * 1024, environment: environment)
        return (result.status, String(decoding: result.output, as: UTF8.self), result.timedOut)
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [onEvent] in onEvent(event) }
    }
}
