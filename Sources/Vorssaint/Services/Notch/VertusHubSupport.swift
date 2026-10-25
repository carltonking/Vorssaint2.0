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
        /// Status the page does not show: "thinking…", memory writes, other
        /// runs' traffic.
        case ignored
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
