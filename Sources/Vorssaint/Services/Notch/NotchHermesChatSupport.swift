// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Agent Client Protocol conversation the island holds with Hermes Agent.
///
/// Hermes runs as an ACP server over standard input and output, one JSON
/// object a line (`hermes acp`). Everything here is a pure translation
/// between that wire format and the island's own vocabulary, so the protocol
/// can be exercised without starting a server: the client below only carries
/// the bytes.
enum HermesACPProtocol {
    /// The only protocol revision the island speaks. Hermes answers with the
    /// revision it will use, which is 1 for every build that ships ACP.
    static let protocolVersion = 1
    static let clientName = "Vorssaint"

    // MARK: Requests

    static func initialize(id: Int, clientVersion: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "initialize",
            "params": [
                "protocolVersion": protocolVersion,
                // The island offers no editor services: no file reads or
                // writes on Hermes' behalf, and no terminal of its own. A
                // tool that needs one is the agent's to run itself.
                "clientCapabilities": [
                    "fs": ["readTextFile": false, "writeTextFile": false],
                    "terminal": false,
                ],
                "clientInfo": ["name": clientName, "version": clientVersion],
            ],
        ]
    }

    static func newSession(id: Int, cwd: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "session/new",
            "params": ["cwd": cwd, "mcpServers": []],
        ]
    }

    static func prompt(id: Int, session: String, text: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "session/prompt",
            "params": [
                "sessionId": session,
                "prompt": [["type": "text", "text": text]],
            ],
        ]
    }

    /// A notification, not a request: the turn ends with a `cancelled` stop
    /// reason on the prompt already outstanding.
    static func cancel(session: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": ["sessionId": session],
        ]
    }

    /// The answer to a permission request. An outcome naming no option is the
    /// protocol's own way to refuse when the server offered nothing to pick.
    static func permissionReply(id: Int, optionId: String?) -> [String: Any] {
        let outcome: [String: Any] = optionId.map { ["outcome": "selected", "optionId": $0] }
            ?? ["outcome": "cancelled"]
        return ["jsonrpc": "2.0", "id": id, "result": ["outcome": outcome]]
    }

    static func encode(_ message: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(message) else { return nil }
        return try? JSONSerialization.data(withJSONObject: message, options: .withoutEscapingSlashes)
    }

    // MARK: Answers

    /// The session id Hermes gave a new session. It sits at the top of the
    /// result, and Hermes also records it in its own metadata, which is read
    /// only if the top-level field ever goes away.
    static func sessionId(of result: [String: Any]) -> String? {
        if let id = result["sessionId"] as? String, !id.isEmpty { return id }
        let meta = result["_meta"] as? [String: Any]
        let hermes = meta?["hermes"] as? [String: Any]
        let provenance = hermes?["sessionProvenance"] as? [String: Any]
        return (provenance?["acpSessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func agentName(of result: [String: Any]) -> String? {
        let info = result["agentInfo"] as? [String: Any]
        return (info?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The model Hermes is configured to use, when it says. Only the name is
    /// kept, for the connection line above the conversation.
    static func modelName(of result: [String: Any]) -> String? {
        let models = result["models"] as? [String: Any]
        let current = models?["currentModelId"] as? String ?? models?["current"] as? String
        guard let current, !current.isEmpty else { return nil }
        let available = models?["availableModels"] as? [[String: Any]] ?? []
        let match = available.first { ($0["modelId"] as? String) == current }
        return (match?["name"] as? String) ?? current
    }

    // MARK: Notifications

    /// One entry of a `session/update` notification. Only the shapes a chat
    /// can show are named; the rest of the protocol's updates are ignored so
    /// a newer Hermes never floods the transcript.
    enum Update: Equatable {
        case text(String)
        case thought(String)
        case toolStarted(String)
        case toolFinished(String)
        case ignored

        static func parse(_ params: [String: Any]) -> Update {
            guard let update = params["update"] as? [String: Any],
                  let kind = update["sessionUpdate"] as? String
            else { return .ignored }
            switch kind {
            case "agent_message_chunk":
                guard let text = contentText(update["content"]), !text.isEmpty else { return .ignored }
                return .text(text)
            case "agent_thought_chunk":
                guard let text = contentText(update["content"]), !text.isEmpty else { return .ignored }
                return .thought(text)
            case "tool_call":
                return .toolStarted(toolTitle(update))
            case "tool_call_update":
                let status = update["status"] as? String
                // A call keeps reporting as it runs; only a closed one is a
                // line the island adds to the conversation.
                guard status == "completed" || status == "failed" else { return .ignored }
                return .toolFinished(toolTitle(update))
            default:
                return .ignored
            }
        }

        /// A content block's words. Prompts and replies are text here; an
        /// image or a resource link carries none and contributes nothing.
        static func contentText(_ block: Any?) -> String? {
            if let block = block as? [String: Any] {
                let type = block["type"] as? String
                guard type == nil || type == "text" else { return nil }
                return block["text"] as? String
            }
            if let blocks = block as? [[String: Any]] {
                let words = blocks.compactMap { contentText($0) }
                return words.isEmpty ? nil : words.joined()
            }
            return nil
        }

        private static func toolTitle(_ update: [String: Any]) -> String {
            if let title = update["title"] as? String, !title.isEmpty { return title }
            if let kind = update["kind"] as? String, !kind.isEmpty { return kind }
            return "tool"
        }
    }

    /// How a turn ended, in the words the page needs. `cancelled` is the
    /// island's own Stop button; the rest arrive from Hermes.
    enum Stop: String, Equatable {
        case endTurn = "end_turn"
        case cancelled
        case maxTokens = "max_tokens"
        case maxTurnRequests = "max_turn_requests"
        case refusal

        static func parse(_ result: [String: Any]) -> Stop {
            Stop(rawValue: result["stopReason"] as? String ?? "") ?? .endTurn
        }

        var wasCancelled: Bool { self == .cancelled }
    }

    // MARK: Permissions

    /// A permission request Hermes raises before a dangerous command.
    ///
    /// The island has no dialog of its own and no way for a person to read a
    /// command before it runs, so it always refuses: a host that answers these
    /// on its own would run shell commands the person never saw. Hermes then
    /// reports the call as failed and carries on, and the page says so.
    static func refusalOption(in options: [[String: Any]]) -> String? {
        func optionId(_ option: [String: Any]) -> String? {
            (option["optionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        let byKind = options.first { ($0["kind"] as? String) == "reject_once" }
            ?? options.first { ($0["kind"] as? String)?.hasPrefix("reject") == true }
        if let id = byKind.flatMap(optionId) { return id }
        // A server that names its options differently is still refused, by
        // whatever reads as a denial.
        let named = options.first { option in
            let label = "\(option["optionId"] as? String ?? "") \(option["name"] as? String ?? "")".lowercased()
            return label.contains("deny") || label.contains("reject")
        }
        return named.flatMap(optionId)
    }

    /// The command a permission request is about, when Hermes names one, so
    /// the page can say what was refused.
    static func permissionSubject(_ params: [String: Any]) -> String? {
        let call = params["toolCall"] as? [String: Any]
        for key in ["title", "kind"] {
            if let value = call?[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

/// Reads the lines Hermes writes and cuts them into frames. One instance per
/// connection: a partial line waits in the buffer for the rest of itself.
struct HermesACPLineReader {
    private(set) var buffer = Data()

    /// Every whole frame completed by `chunk`, in the order it arrived.
    mutating func append(_ chunk: Data) -> [HermesACPFrame] {
        buffer.append(chunk)
        var frames: [HermesACPFrame] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer.subdata(in: buffer.startIndex..<newline)
            // A server writing CRLF still speaks the same protocol.
            if line.last == 0x0D { line.removeLast() }
            buffer.removeSubrange(buffer.startIndex...newline)
            if let frame = HermesACPFrame(line: line) { frames.append(frame) }
        }
        return frames
    }

    /// A server that writes far more than a frame is not an ACP server; the
    /// buffer is dropped rather than grown without bound.
    var overflowed: Bool { buffer.count > 4 << 20 }
}

/// One JSON-RPC frame off the wire, whichever of the four shapes it takes.
struct HermesACPFrame {
    enum Kind: Equatable { case response, failure, notification, request }

    let kind: Kind
    let id: Int?
    let method: String?
    let result: [String: Any]
    let params: [String: Any]
    let failure: String?

    init?(line: Data) {
        guard !line.isEmpty,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        else { return nil }
        let id = object["id"] as? Int
        let method = object["method"] as? String
        let params = object["params"] as? [String: Any] ?? [:]
        let result = object["result"] as? [String: Any] ?? [:]
        let error = object["error"] as? [String: Any]
        let message = error?["message"] as? String ?? (error == nil ? nil : "error")
        self.id = id
        self.method = method
        self.result = result
        self.params = params
        failure = message
        if method != nil {
            // A message carrying an id asks something of the island; one
            // without an id is Hermes telling it about a turn.
            kind = id == nil ? .notification : .request
        } else if error != nil {
            kind = .failure
        } else {
            kind = .response
        }
    }
}

/// One line of the island's conversation with Hermes.
struct NotchHermesChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Equatable, Codable {
        case person, hermes
        /// A tool the agent ran, named without its output.
        case tool
        /// The island's own remark: a refusal, a stop, a failure.
        case note
        /// VERTUS wrote first: a routine's reply nobody on the island asked
        /// for, marked so it does not read as an answer to the line above.
        case proactive
    }

    /// A tapback someone put on a message, as Messages shows it on the
    /// bubble's corner. Each side holds at most one per message.
    struct Reaction: Equatable, Codable {
        let emoji: String
        let fromMe: Bool
    }

    let id: UUID
    let role: Role
    var text: String
    let date: Date
    /// The routine that wrote a proactive message, when the hub named it.
    let source: String?
    /// Tapbacks on this message (Instinct's Messages thread only). Optional
    /// so a history saved before they existed still reads.
    var reactions: [Reaction]?
    /// The message this one answers inline, when it was sent as a reply to
    /// a particular message rather than to the thread.
    var replyTo: UUID?
    /// Files sent with the message, as Messages shows them in the thread.
    /// Optional so a history saved before they existed still reads.
    var attachments: [Attachment]?

    /// A file on this Mac: one chosen to send, or one Messages received.
    struct Attachment: Codable, Equatable, Hashable {
        let path: String
        let name: String

        static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp"]
        var isImage: Bool { Self.imageExtensions.contains((name as NSString).pathExtension.lowercased())
            || Self.imageExtensions.contains((path as NSString).pathExtension.lowercased()) }
        var url: URL { URL(fileURLWithPath: path) }
    }

    init(id: UUID = UUID(), role: Role, text: String, date: Date = Date(), source: String? = nil,
         reactions: [Reaction]? = nil, replyTo: UUID? = nil, attachments: [Attachment]? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.source = source
        self.reactions = reactions
        self.replyTo = replyTo
        self.attachments = attachments
    }

    /// The same message under another role, keeping everything it carries.
    func with(role: Role) -> NotchHermesChatMessage {
        NotchHermesChatMessage(id: id, role: role, text: text, date: date, source: source,
                               reactions: reactions, replyTo: replyTo, attachments: attachments)
    }
}

/// Replies, attachments and notifications for the agents' pages, as Messages
/// does them, kept apart from the views so they can be tested.
enum NotchAgentReplySupport {
    /// How much of the message being answered rides along with a reply.
    static let quoteLimit = 80

    static func firstLine(_ words: String) -> String {
        words.split(whereSeparator: \.isNewline).first.map(String.init) ?? words
    }

    /// The line that tells the agent which message a reply answers. iMessage
    /// threads cannot be started from `imsg`, so the quote travels as text
    /// and is read back into a reply when the thread is read again.
    static func quoteLine(for original: String) -> String {
        let line = firstLine(original).trimmingCharacters(in: .whitespaces)
        let short = line.count > quoteLimit ? String(line.prefix(quoteLimit - 1)) + "…" : line
        return "> " + short
    }

    /// What goes to the agent for a reply: the quote, then the words.
    static func outgoing(_ words: String, quoting original: String?) -> String {
        guard let original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return words }
        return quoteLine(for: original) + "\n" + words
    }

    /// A message of yours read back from Messages: its quote line becomes
    /// the reply it was, pointing at the latest earlier message it quotes.
    /// Messages without a quote, or quoting nothing in sight, stay as read.
    static func resolvingReply(_ message: NotchHermesChatMessage,
                               among earlier: [NotchHermesChatMessage]) -> NotchHermesChatMessage {
        guard message.role == .person, message.replyTo == nil, message.text.hasPrefix("> "),
              let newline = message.text.firstIndex(where: \.isNewline) else { return message }
        var snippet = String(message.text[message.text.index(message.text.startIndex, offsetBy: 2)..<newline])
            .trimmingCharacters(in: .whitespaces)
        if snippet.hasSuffix("…") { snippet.removeLast() }
        guard !snippet.isEmpty,
              let original = earlier.last(where: {
                  $0.id != message.id && firstLine($0.text).trimmingCharacters(in: .whitespaces).hasPrefix(snippet)
              }) else { return message }
        var resolved = message
        resolved.text = String(message.text[message.text.index(after: newline)...])
        resolved.replyTo = original.id
        return resolved
    }

    /// The same, down a whole thread in order.
    static func resolvingReplies(_ thread: [NotchHermesChatMessage]) -> [NotchHermesChatMessage] {
        var resolved: [NotchHermesChatMessage] = []
        for message in thread { resolved.append(resolvingReply(message, among: resolved)) }
        return resolved
    }

    /// The prompt for an agent on this Mac: it reads files by path, so the
    /// attachments are named under the words.
    static func prompt(_ words: String, attachments: [URL]) -> String {
        guard !attachments.isEmpty else { return words }
        let list = attachments.map { "- " + $0.path }.joined(separator: "\n")
        let files = "Attached files:\n" + list
        return words.isEmpty ? files : words + "\n\n" + files
    }

    static func attachments(_ urls: [URL]) -> [NotchHermesChatMessage.Attachment]? {
        let list = urls.map { NotchHermesChatMessage.Attachment(path: $0.path, name: $0.lastPathComponent) }
        return list.isEmpty ? nil : list
    }
}

/// Where the Hermes command is, and what it needs on its PATH.
enum HermesACPSupport {
    static let defaultCommand = "hermes"
    static let arguments = ["acp"]

    /// The command as typed in Settings, reduced to one that can be run.
    /// Blank falls back to `hermes`, which every install puts on the shell's
    /// PATH, and a bare name is searched for rather than being handed to the
    /// process as a relative path.
    static func command(_ stored: String?) -> String {
        let trimmed = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultCommand : trimmed
    }

    /// The folders an app opened from Finder cannot see on its PATH. Hermes
    /// installs into `~/.local/bin`, which a Finder launch never has.
    static func folders(home: URL, searchPath: String?) -> [String] {
        [home.appending(path: ".local/bin", directoryHint: .isDirectory).path,
         "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }

    /// Every place the typed command could be, in the order they win.
    static func candidates(command stored: String?, home: URL, searchPath: String? = nil) -> [URL] {
        let typed = command(stored)
        if typed.hasPrefix("/") || typed.hasPrefix("~") {
            return [URL(fileURLWithPath: (typed as NSString).expandingTildeInPath, isDirectory: false)]
        }
        if typed.contains("/") {
            return [home.appending(path: typed, directoryHint: .notDirectory)]
        }
        return folders(home: home, searchPath: searchPath)
            .map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: typed) }
    }

    static func executable(command: String?, home: URL, searchPath: String? = nil) -> URL? {
        candidates(command: command, home: home, searchPath: searchPath).first { isExecutable($0) }
    }

    static func isExecutable(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && !directory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// A conversation starts in the person's home folder: the agent's file and
    /// terminal tools work there, the way they do in a terminal.
    static func workingDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        home.path
    }

    /// A Finder launch starts with the system folders only, so the folders
    /// Hermes installs into lead its PATH and the app's own follows.
    static func environment(executable: URL, searchPath: String?,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let folders = [executable.deletingLastPathComponent().path]
            + (searchPath.map { [$0] } ?? ["/opt/homebrew/bin", "/usr/local/bin"])
            + [base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
        environment["PATH"] = folders.joined(separator: ":")
        // Hermes no longer reads this, and its own configuration is what
        // decides which servers an ACP session gets.
        environment.removeValue(forKey: "HERMES_ACP_SKIP_CONFIGURED_MCP")
        return environment
    }

    /// The transcript keeps a bounded number of turns, so a conversation left
    /// open for hours cannot grow the island's memory without end. The oldest
    /// turns go first; the page says nothing about it, as a terminal does not.
    static let maximumMessages = 200

    static func trimmed(_ messages: [NotchHermesChatMessage]) -> [NotchHermesChatMessage] {
        guard messages.count > maximumMessages else { return messages }
        return Array(messages.suffix(maximumMessages))
    }

    /// A reply's Markdown as a chat bubble shows it. The bubble renders inline
    /// marks (bold, italics, code, links) and keeps line breaks; the block
    /// syntax a model writes is turned into what it means first: a heading
    /// becomes a bold line, a bullet a dot, a rule a gap. Code fences are left
    /// as written, and nothing inside one is touched.
    static func bubbleMarkdown(_ reply: String) -> String {
        var inFence = false
        let lines = reply.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return line
            }
            guard !inFence else { return line }
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            if let heading = trimmed.range(of: #"^#{1,6}[ \t]+"#, options: .regularExpression) {
                let words = trimmed[heading.upperBound...].trimmingCharacters(in: .whitespaces)
                return words.isEmpty ? "" : "**\(words)**"
            }
            if trimmed.range(of: #"^([-*_])([ \t]*\1){2,}$"#, options: .regularExpression) != nil { return "" }
            if let bullet = trimmed.range(of: #"^[-*+][ \t]+"#, options: .regularExpression) {
                // Nested bullets keep their depth, two spaces a level.
                let depth = indent.replacingOccurrences(of: "\t", with: "  ").count / 2
                return String(repeating: "  ", count: depth) + "• " + trimmed[bullet.upperBound...]
            }
            return line
        }
        return lines.joined(separator: "\n")
    }
}

/// The conversation as saved between launches: only the user's Clear empties
/// it, so it survives quitting, updates, and the page being switched off.
enum NotchHermesChatHistory {
    private struct File: Codable {
        var version = 1
        var messages: [Line]
    }

    /// One message that may not decode (a role a newer build added): skipped
    /// alone rather than costing the whole history.
    private struct Line: Codable {
        let message: NotchHermesChatMessage?
        init(_ message: NotchHermesChatMessage) { self.message = message }
        init(from decoder: Decoder) throws {
            message = try? NotchHermesChatMessage(from: decoder)
        }
        func encode(to encoder: Encoder) throws { try message?.encode(to: encoder) }
    }

    static func encode(_ messages: [NotchHermesChatMessage]) -> Data? {
        let file = File(messages: HermesACPSupport.trimmed(messages).map(Line.init))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(file)
    }

    /// The saved conversation, newest kept within the cap; anything unreadable
    /// reads as no history.
    static func decode(_ data: Data) -> [NotchHermesChatMessage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.version == 1 else { return [] }
        return HermesACPSupport.trimmed(file.messages.compactMap(\.message))
    }

    /// Saved lines first, then any that arrived before the file was read,
    /// without repeats, within the cap.
    static func restored(saved: [NotchHermesChatMessage],
                         current: [NotchHermesChatMessage]) -> [NotchHermesChatMessage] {
        let known = Set(saved.map(\.id))
        return HermesACPSupport.trimmed(saved + current.filter { !known.contains($0.id) })
    }
}
