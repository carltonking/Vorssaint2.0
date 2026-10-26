// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's side of the VERTUS hub: a local HTTP server that runs the
/// agent, its memory and its routines, so every surface talks to one brain.
///
/// When the hub is installed the island speaks to it instead of starting its
/// own `hermes acp`; otherwise the page keeps the Hermes conversation. The
/// wire is plain: `POST /api/prompt` queues a turn and names its run, and
/// `GET /api/events?run_id=` streams that run as server-sent events until a
/// terminal one. Everything here is a pure translation of that wire, so it can
/// be exercised without a hub; the client only carries the bytes.
enum VertusHubSupport {
    /// The hub listens on loopback (and the tailnet); the island is always
    /// on the same Mac, so loopback is the address.
    static let baseURL = URL(string: "http://127.0.0.1:8787")!
    /// The hub's own default agent, the one every other surface opens on.
    static let agentID = "primary"
    /// The name the hub's agent goes by on the page, whatever engine runs it.
    static let agentName = "VERTUS"

    /// The bearer token the hub writes at install. Its presence is what says
    /// the hub is installed at all.
    static func tokenURL(home: URL) -> URL {
        home.appendingPathComponent(".vertus/token", isDirectory: false)
    }

    /// The credential that answers approvals, on top of the bearer token.
    /// The hub creates it for the person's own clients; its agents are never
    /// given it, so none of them can approve its own request.
    static func approverTokenURL(home: URL) -> URL {
        home.appendingPathComponent(".vertus/approver-token", isDirectory: false)
    }

    static func approverToken(home: URL, fileManager: FileManager = .default) -> String? {
        secret(at: approverTokenURL(home: home), fileManager: fileManager)
    }

    /// The token, trimmed, or nil when the hub is not installed here.
    static func token(home: URL, fileManager: FileManager = .default) -> String? {
        secret(at: tokenURL(home: home), fileManager: fileManager)
    }

    private static func secret(at url: URL, fileManager: FileManager) -> String? {
        guard fileManager.isReadableFile(atPath: url.path),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: Requests

    static func request(_ path: String, token: String, method: String = "GET",
                        body: [String: Any]? = nil, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // The hub holds destructive commands from remote clients for
        // confirmation; the island is on this Mac, so it says so.
        request.setValue("local", forHTTPHeaderField: "X-Vertus-Client")
        if let body, let data = try? JSONSerialization.data(withJSONObject: body) {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func prompt(_ text: String, token: String) -> URLRequest {
        request("api/prompt", token: token, method: "POST",
                body: ["text": text, "agent_id": agentID])
    }

    static func events(run: String, token: String) -> URLRequest {
        var request = request("api/events", token: token,
                              query: [URLQueryItem(name: "run_id", value: run)])
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    /// The agent's live stream, every run included: how an approval asked
    /// by a turn that started elsewhere (a routine, the terminal) still
    /// reaches the island.
    /// With `since`, the hub first replays what it stored after that event,
    /// so a watch that dropped and reconnects misses nothing in between.
    static func watch(token: String, since: Int? = nil) -> URLRequest {
        var query = [URLQueryItem(name: "agent_id", value: agentID)]
        if let since { query.append(URLQueryItem(name: "since", value: String(since))) }
        var request = request("api/events", token: token, query: query)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    /// The approvals still waiting, from the hub's ledger: what a watch that
    /// just connected cannot have seen arrive.
    static func pendingApprovals(token: String) -> URLRequest {
        request("api/approvals", token: token,
                query: [URLQueryItem(name: "state", value: "pending"), URLQueryItem(name: "limit", value: "50")])
    }

    /// The hub agent's routines, for the name a message VERTUS sent on its
    /// own is credited to.
    static func routines(token: String) -> URLRequest {
        request("api/routines", token: token, query: [URLQueryItem(name: "agent_id", value: agentID)])
    }

    /// One run as the hub stored it, for what kind of run it is: the
    /// agent's stream does not say which runs a routine started.
    static func run(_ run: String, token: String) -> URLRequest {
        request("api/runs/\(run)", token: token)
    }

    static func cancel(run: String, token: String) -> URLRequest {
        request("api/runs/\(run)/cancel", token: token, method: "POST", body: [:])
    }

    /// Answers an approval the agent is waiting on. The hub credits the
    /// decision to the client named in `X-Vertus-Client`.
    static func answer(_ approval: String, choice: NotchAgentApproval.Choice, token: String,
                       approverToken: String) -> URLRequest {
        var request = request("api/approvals/\(approval)", token: token, method: "POST",
                              body: ["choice": choice.rawValue])
        request.setValue("island", forHTTPHeaderField: "X-Vertus-Client")
        request.setValue(approverToken, forHTTPHeaderField: "X-Vertus-Approver")
        return request
    }

    // MARK: Responses

    /// The run a queued prompt was given, or the hub's reason for refusing it.
    static func runID(from data: Data?, status: Int) -> Result<String, HubError> {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        if (200..<300).contains(status), let run = object?["run_id"] as? String, !run.isEmpty {
            return .success(run)
        }
        let reason = (object?["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return .failure(HubError(reason: reason ?? "HTTP \(status)"))
    }

    /// The model the hub's agent answers with, from `GET /api/agents`.
    static func modelName(from data: Data?) -> String? {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let agents = (object as? [String: Any])?["agents"] as? [[String: Any]] ?? object as? [[String: Any]] ?? []
        let agent = agents.first { $0["id"] as? String == agentID }
        return (agent?["model"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The hub's own agent's waiting approvals, oldest first. The ledger
    /// keeps no list of accepted answers, so a card restored from it offers
    /// the two every approval takes.
    static func pendingApprovals(from data: Data?) -> [NotchAgentApproval] {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let rows = object?["approvals"] as? [[String: Any]] ?? []
        return rows.reversed().compactMap { row in
            guard row["agent_id"] as? String == agentID, row["decision"] == nil || row["decision"] is NSNull,
                  let id = row["approval_id"] as? String, !id.isEmpty else { return nil }
            return NotchAgentApproval(id: id, description: row["action"] as? String ?? "",
                                      command: row["target"] as? String ?? "", choices: [.once, .deny],
                                      runID: row["run_id"] as? String)
        }
    }

    /// Routine names by id, from `GET /api/routines`. A routine without a
    /// name is left out, so its message falls back to the plain line.
    static func routineNames(from data: Data?) -> [String: String] {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let rows = object?["routines"] as? [[String: Any]] ?? []
        var names: [String: String] = [:]
        for row in rows {
            guard let id = row["routine_id"] as? String, !id.isEmpty,
                  let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            names[id] = name
        }
        return names
    }

    /// What `GET /api/runs/<id>` says the run is, or nil when the answer
    /// does not describe a run. A routine's run carries the routine's id,
    /// or failing that its source (`routine:<id>`).
    static func runKind(from data: Data?) -> VertusRoutineReplies.Kind? {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        guard let run = object?["run"] as? [String: Any] else { return nil }
        guard run["run_kind"] as? String == "routine" else { return .other }
        if let id = run["routine_id"] as? String, !id.isEmpty { return .routine(id) }
        if let source = run["source"] as? String, source.hasPrefix("routine:"), source.count > "routine:".count {
            return .routine(String(source.dropFirst("routine:".count)))
        }
        return .routine(nil)
    }

    /// What the hub said to an answer.
    enum AnswerResult: Equatable {
        /// The engine has it; the settling arrives on the stream.
        case accepted
        /// Nothing waits on it any more: answered elsewhere, or expired.
        case settled(NotchAgentApproval.Outcome)
        /// The answer did not get through; the card stays answerable.
        case retry
    }

    static func answerResult(status: Int, data: Data?) -> AnswerResult {
        switch status {
        case 200..<300: return .accepted
        case 404: return .settled(.expired)
        case 409:
            // "approval already settled: <decision>"
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let reason = object?["error"] as? String ?? ""
            let decision = reason.range(of: "settled: ").map { String(reason[$0.upperBound...]) }
            return .settled(NotchAgentApproval.Outcome(decision: decision?.trimmingCharacters(in: .whitespaces)))
        default: return .retry
        }
    }

    /// The hub's sequence number of one streamed event, so a watch can resume
    /// after it.
    static func sequence(line: String) -> Int? {
        guard line.hasPrefix("data:"),
              let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["seq"] as? NSNumber)?.intValue
    }

    struct HubError: Error, Equatable {
        let reason: String
    }

    // MARK: Events

    /// What one event of a run means to the page.
    enum Event: Equatable {
        case text(String)
        /// A tool the agent is running, by name.
        case tool(String)
        case done
        case cancelled
        case error(String)
        /// The agent stopped and waits for a yes before it acts.
        case approval(NotchAgentApproval)
        /// An approval was answered (here or anywhere else) or withdrawn.
        case approvalSettled(String, NotchAgentApproval.Outcome)
        /// One of the agent's routines started a run of its own: what that
        /// run writes is VERTUS speaking first, not answering the island.
        case routineFired(routine: String, run: String)
        /// Status the page does not show: "thinking…", memory writes, other
        /// runs' traffic.
        case ignored
    }

    /// One event of the agent-wide watch, with the run it belongs to: the
    /// watch carries every run at once, so the run is what tells a routine's
    /// reply from the island's own or the terminal's.
    struct WatchEvent: Equatable {
        let run: String?
        let event: Event
    }

    static func watchEvent(line: String) -> WatchEvent? {
        guard let event = event(line: line, run: nil) else { return nil }
        return WatchEvent(run: runID(line: line), event: event)
    }

    private static func runID(line: String) -> String? {
        guard line.hasPrefix("data:"),
              let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["run_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Splits a stream's bytes into its `data:` payloads, keeping a partial
    /// line for the next chunk.
    struct LineReader {
        private var pending = Data()

        mutating func append(_ chunk: Data) -> [String] {
            pending.append(chunk)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                if let text = String(data: line, encoding: .utf8) {
                    lines.append(text.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                }
            }
            return lines
        }
    }

    /// One server-sent line as an event. Comments, blank separators and
    /// fields other than `data` mean nothing here. With a `run`, another
    /// run's events are ignored; without one, every run's are read.
    static func event(line: String, run: String?) -> Event? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let run, let owner = object["run_id"] as? String, !owner.isEmpty, owner != run { return .ignored }
        switch object["type"] as? String {
        case "text":
            let words = object["text"] as? String ?? ""
            return words.isEmpty ? .ignored : .text(words)
        case "activity":
            return toolName(object["text"] as? String ?? "").map(Event.tool) ?? .ignored
        case "done": return .done
        case "cancelled": return .cancelled
        case "approval_request":
            guard let id = object["approval_id"] as? String, !id.isEmpty else { return .ignored }
            let choices = (object["choices"] as? [String] ?? []).compactMap(NotchAgentApproval.Choice.init)
            return .approval(NotchAgentApproval(
                id: id,
                description: object["description"] as? String ?? "",
                command: object["command"] as? String ?? "",
                choices: choices.isEmpty ? [.once, .deny] : choices,
                runID: (object["run_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }))
        case "approval_resolved":
            guard let id = object["approval_id"] as? String, !id.isEmpty else { return .ignored }
            return .approvalSettled(id, NotchAgentApproval.Outcome(decision: object["decision"] as? String))
        case "routine_fired":
            guard let routine = object["routine_id"] as? String, !routine.isEmpty,
                  let fired = object["run_id"] as? String, !fired.isEmpty else { return .ignored }
            return .routineFired(routine: routine, run: fired)
        case "error":
            let reason = (object["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .error(reason ?? "VERTUS did not answer.")
        default: return .ignored
        }
    }

    /// The hub narrates a turn as "thinking…", "running tools…" and
    /// "running <tool>…"; only the last names something worth a line.
    static func toolName(_ activity: String) -> String? {
        let words = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.hasPrefix("running ") else { return nil }
        let name = words.dropFirst("running ".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "…. "))
        guard !name.isEmpty, name != "tools" else { return nil }
        return name
    }
}

/// The replies VERTUS writes on its own: a routine fires on the hub's
/// schedule, and what its run says is a message nobody on the island asked
/// for. Fed the agent-wide watch one event at a time, this keeps the words of
/// each routine run until the run ends, and hands back the finished message.
///
/// The agent's stream does not say which runs are routines: the hub sends
/// `routine_fired` to the fleet-wide stream only, so on the island's watch a
/// routine's words arrive like anyone else's. A run heard for the first time
/// is therefore kept aside while the hub is asked what it is
/// (`GET /api/runs/<id>`), and only a run whose kind is `routine` becomes a
/// message. The island's own turns and the terminal's stream through the same
/// watch and are someone's answer already, so their words are let go once the
/// hub says so. A `routine_fired` that does arrive answers the question early.
struct VertusRoutineReplies {
    /// What a check-in routine replies when it has nothing worth saying. The
    /// island stays silent then: no line, no companion, no opening.
    static let silence = "NOTHING_TO_REPORT"

    /// The hub's own reading (proactive_routines.is_nothing_to_report): the
    /// bare token, allowing the code fence, backticks or quotes a model
    /// sometimes wraps it in. Words around it make it a real message.
    static func isSilence(_ reply: String) -> Bool {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 6, text.hasPrefix("```"), text.hasSuffix("```") {
            text = String(text.dropFirst(3).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "`'\" \n\t")) == silence
    }
    /// Runs followed at once, asked about or known to be routines. One whose
    /// end the watch never heard (the hub restarted mid-run) is let go,
    /// oldest first, past this.
    static let maximumRuns = 8
    /// A message the island will show in a bubble; anything longer is cut
    /// here rather than held in memory for a reply that ran away.
    static let maximumCharacters = 8_000
    /// The island's own runs remembered, so a late event of one cannot
    /// start being collected.
    static let maximumOwnRuns = 32
    /// Runs already settled (not routines, finished, or let go) remembered,
    /// so a late event of one, such as a memory write after its `done`, is
    /// not asked about a second time.
    static let maximumSettledRuns = 64

    struct Message: Equatable {
        let run: String
        /// The routine's id, when the hub named it.
        let routine: String?
        let text: String
    }

    /// What the hub says a run is.
    enum Kind: Equatable {
        /// A routine's run, by the routine's id when the hub gives one.
        case routine(String?)
        /// Anything else: a person's turn, the terminal, a message between
        /// agents. Also what a run the hub could not describe counts as: a
        /// message nobody asked for is not worth showing on a guess.
        case other
    }

    /// What one watch event asks of the client.
    enum Step: Equatable {
        /// A run heard for the first time: ask the hub what it is and hand
        /// the answer to `classify(run:as:)`. Asked once per run.
        case lookup(String)
        /// A routine run ended with something to say.
        case message(Message)
    }

    private struct Collecting {
        let run: String
        /// Whether the hub has said this is a routine's run; until then its
        /// words are held in case it is.
        var classified: Bool
        var routine: String?
        var text = ""
        var characters = 0
        var truncated = false
        /// `done` arrived before the hub said what the run is; the message
        /// goes out with the answer.
        var ended = false
    }

    /// Oldest first.
    private var collecting: [Collecting] = []
    private var own: [String] = []
    private var settled: [String] = []

    /// How many runs are being followed, asked about or collected.
    var followed: Int { collecting.count }

    /// A run the island started itself: its reply is the island's turn,
    /// shown as it streams, never a second time as a message sent unasked.
    mutating func ignore(run: String) {
        collecting.removeAll { $0.run == run }
        guard !own.contains(run) else { return }
        own.append(run)
        if own.count > Self.maximumOwnRuns { own.removeFirst(own.count - Self.maximumOwnRuns) }
    }

    /// Takes one watch event; returns a run to ask the hub about, or a
    /// message when a routine run ended with something to say.
    ///
    /// A run that fails or is cancelled says nothing on the island. Nobody
    /// asked for it, so a failure is not news worth interrupting for, and a
    /// half-written message would claim attention for words VERTUS never
    /// finished. The hub keeps the failure on the routine itself, where it
    /// counts them and turns off a routine that keeps failing.
    mutating func receive(_ event: VertusHubSupport.Event, run: String?) -> Step? {
        if case .routineFired(let routine, let fired) = event {
            guard !own.contains(fired), !settled.contains(fired) else { return nil }
            guard let index = collecting.firstIndex(where: { $0.run == fired }) else {
                follow(Collecting(run: fired, classified: true, routine: routine))
                return nil
            }
            guard !collecting[index].classified else { return nil }
            return classify(at: index, routine: routine).map(Step.message)
        }
        guard let run, !own.contains(run), !settled.contains(run) else { return nil }
        var lookup: Step?
        if !collecting.contains(where: { $0.run == run }) {
            follow(Collecting(run: run, classified: false, routine: nil))
            lookup = .lookup(run)
        }
        guard let index = collecting.firstIndex(where: { $0.run == run }) else { return lookup }
        switch event {
        case .text(let words):
            guard !collecting[index].ended else { return lookup }
            var entry = collecting[index]
            let room = Self.maximumCharacters - entry.characters
            guard room > 0 else {
                entry.truncated = true
                collecting[index] = entry
                return lookup
            }
            let kept = words.count > room ? String(words.prefix(room)) : words
            entry.truncated = entry.truncated || kept.count < words.count
            entry.text += kept
            entry.characters += kept.count
            collecting[index] = entry
            return lookup
        case .tool:
            // What the run says before a tool is narration ("let me check
            // your mail…"); the message is what it writes after its last
            // tool, which is also where the check-in's silence is written.
            var entry = collecting[index]
            entry.text = ""
            entry.characters = 0
            entry.truncated = false
            collecting[index] = entry
            return lookup
        case .done:
            // The hub can repeat `done`; the run is settled after the first,
            // so a repeat finds nothing to send again.
            guard collecting[index].classified else {
                collecting[index].ended = true
                return lookup
            }
            return finish(at: index).map(Step.message)
        case .error, .cancelled:
            collecting.remove(at: index)
            settle(run)
            return nil
        default:
            return lookup
        }
    }

    /// The hub's answer about a run `receive` asked for. A routine's run
    /// keeps being collected, and one that already ended is delivered now;
    /// anything else is let go with what it said.
    mutating func classify(run: String, as kind: Kind) -> Message? {
        guard let index = collecting.firstIndex(where: { $0.run == run }),
              !collecting[index].classified else { return nil }
        switch kind {
        case .routine(let routine):
            return classify(at: index, routine: routine)
        case .other:
            collecting.remove(at: index)
            settle(run)
            return nil
        }
    }

    private mutating func classify(at index: Int, routine: String?) -> Message? {
        collecting[index].classified = true
        collecting[index].routine = routine
        return collecting[index].ended ? finish(at: index) : nil
    }

    private mutating func finish(at index: Int) -> Message? {
        let finished = collecting.remove(at: index)
        settle(finished.run)
        let words = finished.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !Self.isSilence(words) else { return nil }
        return Message(run: finished.run, routine: finished.routine,
                       text: finished.truncated ? words + "…" : words)
    }

    private mutating func follow(_ entry: Collecting) {
        collecting.append(entry)
        guard collecting.count > Self.maximumRuns else { return }
        for dropped in collecting.prefix(collecting.count - Self.maximumRuns) { settle(dropped.run) }
        collecting.removeFirst(collecting.count - Self.maximumRuns)
    }

    private mutating func settle(_ run: String) {
        guard !settled.contains(run) else { return }
        settled.append(run)
        if settled.count > Self.maximumSettledRuns { settled.removeFirst(settled.count - Self.maximumSettledRuns) }
    }
}

/// The last event the hub's agent stream delivered, kept by the service
/// across the clients it starts, so a watch opened after a retry resumes
/// where the one before it stopped instead of only hearing what comes next.
/// Written on a client's queue, read on the main thread when a client is made.
final class VertusWatchCursor: @unchecked Sendable {
    private let lock = NSLock()
    private var seq: Int?

    var value: Int? {
        lock.lock()
        defer { lock.unlock() }
        return seq
    }

    /// The hub numbers its events in order, so the cursor only moves forward.
    func advance(to next: Int) {
        lock.lock()
        defer { lock.unlock() }
        seq = max(seq ?? 0, next)
    }

    /// Forgets the place: a conversation switched off starts over live.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        seq = nil
    }
}

/// How the island gets attention for a message VERTUS sent unasked. Unlike
/// an approval nothing waits on it, so it never pins the island and never
/// takes a page the person is using.
enum NotchAgentReachOut: Equatable {
    /// The conversation is on screen, or now is no time to interrupt: the
    /// message landing is enough.
    case append
    /// The island is open on something else: the companion reacts, and the
    /// message waits on the chat page.
    case nudge
    /// The island is closed: it opens on the conversation, unpinned and
    /// without the keyboard, so a click elsewhere or the pointer passing
    /// over and away puts it back as it would any island opened by hover.
    case open

    /// Local hours in which a message only lands: from 22:00 until 07:00 an
    /// island that opens or a companion that jumps is a light in a dark room.
    static let quietHoursStart = 22
    static let quietHoursEnd = 7

    /// Routines that keep VERTUS's own house (its memory) rather than tell
    /// the person anything; what they write is kept for reading, never
    /// interrupts. Matched by the routine's name on the hub.
    static let quietRoutines: Set<String> = ["memory-consolidation"]

    static func isQuietHour(_ hour: Int) -> Bool {
        hour >= quietHoursStart || hour < quietHoursEnd
    }

    static func isQuietRoutine(_ name: String?) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return quietRoutines.contains(name)
    }

    /// - Parameters:
    ///   - onChat: the island's selected page is the conversation.
    ///   - covered: something sits over the selected page (the sections
    ///     grid, the app panel, the Command Bar), so the conversation is not
    ///     what is on screen even with it selected.
    ///   - hour: the local hour, 0–23.
    ///   - routine: the name of the routine that wrote, when known.
    static func attention(expanded: Bool, onChat: Bool, covered: Bool,
                          hour: Int, routine: String?) -> NotchAgentReachOut {
        if isQuietHour(hour) || isQuietRoutine(routine) { return .append }
        guard expanded else { return .open }
        return onChat && !covered ? .append : .nudge
    }
}

/// One action the agent will not take without a yes: what it wants to do, in
/// the engine's words, and the answers it accepts.
struct NotchAgentApproval: Equatable, Identifiable {
    enum Choice: String, CaseIterable {
        /// This one action.
        case once
        /// This kind of action for the rest of the conversation.
        case session
        /// This kind of action from now on.
        case always
        case deny
    }

    enum Outcome: Equatable {
        case allowed
        case denied
        /// Nobody answered in time, or the turn ended first; the engine
        /// failed the action closed.
        case expired

        init(decision: String?) {
            switch decision {
            case "once", "session", "always": self = .allowed
            case "deny": self = .denied
            default: self = .expired
            }
        }
    }

    let id: String
    let description: String
    let command: String
    let choices: [Choice]
    /// The turn that is waiting. The island's own turn ending expires only
    /// its own approvals; a routine's or the terminal's keep waiting.
    var runID: String? = nil

    /// What the card says: the engine's description, which for VERTUS's own
    /// rules already names the command ("VERTUS wants to delete files: rm …").
    var headline: String {
        let words = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? command : words
    }

    /// The command shown under the headline, when it adds something: a rule
    /// label such as "<terminal> (plugin approval rule)" or a repeat of the
    /// headline does not.
    var detail: String? {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !command.hasPrefix("<"), !headline.contains(command) else { return nil }
        return command
    }
}
