// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's Hermes conversation is a protocol translation, so its edges
/// are pinned here without starting a server: the frames Hermes is sent, the
/// updates it sends back, and how the command in Settings is found.
enum NotchHermesChatTests {
    static func run(_ suite: TestSuite) {
        handshakeContracts(suite)
        answerContracts(suite)
        updateContracts(suite)
        frameContracts(suite)
        stopContracts(suite)
        permissionContracts(suite)
        discoveryContracts(suite)
        transcriptContracts(suite)
        migrationContracts(suite)
        wiringContracts(suite)
        bubbleContracts(suite)
        hubContracts(suite)
        approvalContracts(suite)
    }

    /// A model writes Markdown; the bubble shows what it means, never the
    /// block syntax, and never rewrites what sits inside a code fence.
    private static func bubbleContracts(_ suite: TestSuite) {
        suite.expect(HermesACPSupport.bubbleMarkdown("## Results\nNo **email** found.")
                == "**Results**\nNo **email** found.",
               "a heading reads as a bold line and inline marks are left for the bubble")
        suite.expect(HermesACPSupport.bubbleMarkdown("- one\n  - nested\n* two")
                == "• one\n  • nested\n• two",
               "bullets become dots and keep their depth")
        suite.expect(HermesACPSupport.bubbleMarkdown("a\n---\nb") == "a\n\nb", "a rule becomes a gap")
        suite.expect(HermesACPSupport.bubbleMarkdown("```\n# not a heading\n- not a bullet\n```")
                == "```\n# not a heading\n- not a bullet\n```",
               "code fences are left exactly as written")
        suite.expect(HermesACPSupport.bubbleMarkdown("V = ∫ 2πx dx\n\n#tag stays") == "V = ∫ 2πx dx\n\n#tag stays",
               "plain text and a tag without a space are unchanged")
    }

    // MARK: Requests

    private static func handshakeContracts(_ suite: TestSuite) {
        let initialize = HermesACPProtocol.initialize(id: 7, clientVersion: "1.2.3")
        let params = initialize["params"] as? [String: Any]
        let capabilities = params?["clientCapabilities"] as? [String: Any]
        let fs = capabilities?["fs"] as? [String: Bool]
        let info = params?["clientInfo"] as? [String: Any]
        suite.expect(initialize["jsonrpc"] as? String == "2.0"
                     && initialize["id"] as? Int == 7
                     && initialize["method"] as? String == "initialize"
                     && params?["protocolVersion"] as? Int == HermesACPProtocol.protocolVersion,
                     "the handshake names the protocol revision the island speaks")
        suite.expect(info?["name"] as? String == "Vorssaint" && info?["version"] as? String == "1.2.3",
                     "the handshake names the app and its version")
        // The island offers no editor services, so a tool that needs one is
        // the agent's to run itself.
        suite.expect(fs?["readTextFile"] == false && fs?["writeTextFile"] == false
                     && capabilities?["terminal"] as? Bool == false,
                     "the island offers Hermes no file or terminal services")

        let session = HermesACPProtocol.newSession(id: 8, cwd: "/Users/someone")
        let sessionParams = session["params"] as? [String: Any]
        suite.expect(session["method"] as? String == "session/new"
                     && sessionParams?["cwd"] as? String == "/Users/someone"
                     && (sessionParams?["mcpServers"] as? [Any])?.isEmpty == true,
                     "a session starts in the home folder with no servers of the island's own")

        let prompt = HermesACPProtocol.prompt(id: 9, session: "abc", text: "Hello")
        let promptParams = prompt["params"] as? [String: Any]
        let blocks = promptParams?["prompt"] as? [[String: String]]
        suite.expect(prompt["method"] as? String == "session/prompt"
                     && promptParams?["sessionId"] as? String == "abc"
                     && blocks?.count == 1
                     && blocks?.first?["type"] == "text"
                     && blocks?.first?["text"] == "Hello",
                     "a message travels as one text block of the open session")

        let cancel = HermesACPProtocol.cancel(session: "abc")
        suite.expect(cancel["method"] as? String == "session/cancel"
                     && cancel["id"] == nil
                     && (cancel["params"] as? [String: Any])?["sessionId"] as? String == "abc",
                     "cancelling is a notification, answered by the prompt's own stop reason")
    }

    private static func answerContracts(_ suite: TestSuite) {
        let picked = HermesACPProtocol.permissionReply(id: 4, optionId: "reject-1")
        let pickedOutcome = (picked["result"] as? [String: Any])?["outcome"] as? [String: Any]
        let refused = HermesACPProtocol.permissionReply(id: 5, optionId: nil)
        let refusedOutcome = (refused["result"] as? [String: Any])?["outcome"] as? [String: Any]
        suite.expect(picked["id"] as? Int == 4
                     && pickedOutcome?["outcome"] as? String == "selected"
                     && pickedOutcome?["optionId"] as? String == "reject-1",
                     "choosing an option answers with that option")
        suite.expect(refusedOutcome?["outcome"] as? String == "cancelled"
                     && refusedOutcome?["optionId"] == nil,
                     "with nothing to choose, the request is cancelled rather than approved")

        suite.expect(HermesACPProtocol.encode(["a": 1]) != nil
                     && HermesACPProtocol.encode(["a": Date()]) == nil,
                     "only a JSON object becomes a frame")
    }

    // MARK: Answers

    private static func updateContracts(_ suite: TestSuite) {
        func update(_ kind: String, _ extra: [String: Any] = [:]) -> [String: Any] {
            var body: [String: Any] = ["sessionUpdate": kind]
            body.merge(extra) { _, new in new }
            return ["sessionId": "abc", "update": body]
        }
        suite.expect(HermesACPProtocol.Update.parse(update(
            "agent_message_chunk", ["content": ["type": "text", "text": "Hel"]])) == .text("Hel"),
                     "a reply streams in as text chunks")
        suite.expect(HermesACPProtocol.Update.parse(update(
            "agent_message_chunk", ["content": [["type": "text", "text": "a"],
                                                ["type": "text", "text": "b"]]])) == .text("ab"),
                     "a chunk made of several blocks is their words in order")
        suite.expect(HermesACPProtocol.Update.parse(update(
            "agent_message_chunk", ["content": ["type": "image", "data": "..."]])) == .ignored,
                     "an image carries no words for the transcript")
        suite.expect(HermesACPProtocol.Update.parse(update(
            "agent_message_chunk", ["content": ["type": "text", "text": ""]])) == .ignored,
                     "an empty chunk adds nothing")
        suite.expect(HermesACPProtocol.Update.parse(update(
            "agent_thought_chunk", ["content": ["type": "text", "text": "thinking"]])) == .thought("thinking"),
                     "reasoning Hermes streams is kept apart from the reply")
        suite.expect(HermesACPProtocol.Update.parse(update("tool_call", ["title": "Run tests", "status": "pending"]))
                        == .toolStarted("Run tests"),
                     "a tool call starting is named")
        suite.expect(HermesACPProtocol.Update.parse(update(
            "tool_call_update", ["title": "Run tests", "status": "in_progress"])) == .ignored,
                     "a tool still running adds no line")
        suite.expect(HermesACPProtocol.Update.parse(update(
            "tool_call_update", ["title": "Run tests", "status": "completed"])) == .toolFinished("Run tests")
                        && HermesACPProtocol.Update.parse(update(
            "tool_call_update", ["title": "Run tests", "status": "failed"])) == .toolFinished("Run tests"),
                     "a tool that finished or failed is one line, named without its output")
        suite.expect(HermesACPProtocol.Update.parse(update("tool_call_update", ["status": "completed"]))
                        == .toolFinished("tool"),
                     "a tool with no title is still named")
        suite.expect(HermesACPProtocol.Update.parse(update("plan")) == .ignored
                     && HermesACPProtocol.Update.parse([:]) == .ignored,
                     "an update the page has no place for is dropped rather than guessed at")
    }

    private static func frameContracts(_ suite: TestSuite) {
        func frame(_ object: [String: Any]) -> HermesACPFrame? {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return HermesACPFrame(line: data)
        }
        let notification = frame(["jsonrpc": "2.0", "method": "session/update", "params": ["sessionId": "abc"]])
        suite.expect(notification?.kind == .notification && notification?.id == nil
                     && notification?.method == "session/update"
                     && (notification?.params["sessionId"] as? String) == "abc",
                     "a message without an id tells the island about a turn")
        let request = frame(["jsonrpc": "2.0", "id": 3, "method": "session/request_permission"])
        suite.expect(request?.kind == .request && request?.id == 3,
                     "a message with an id asks the island something")
        let response = frame(["jsonrpc": "2.0", "id": 3, "result": ["stopReason": "end_turn"]])
        suite.expect(response?.kind == .response && response?.id == 3
                     && (response?.result["stopReason"] as? String) == "end_turn",
                     "an answer to the island's own request carries its id")
        let failure = frame(["jsonrpc": "2.0", "id": 4, "error": ["code": -32601, "message": "no method"]])
        suite.expect(failure?.kind == .failure && failure?.failure == "no method",
                     "a protocol error is read in the server's own words")
        suite.expect(frame(["jsonrpc": "2.0", "id": 5, "error": ["code": -32603]])?.failure == "error",
                     "an error without a message still fails the turn")
        suite.expect(HermesACPFrame(line: Data("not json".utf8)) == nil
                     && HermesACPFrame(line: Data()) == nil,
                     "a line that is not a frame is skipped")

        var reader = HermesACPLineReader()
        let two = reader.append(Data("{\"id\":1}\n{\"id\":2}\n".utf8))
        suite.expect(two.compactMap(\.id) == [1, 2], "two frames arriving at once are both read")
        let split = Data("{\"id\":3}\n".utf8)
        let firstHalf = split.prefix(4)
        suite.expect(reader.append(Data(firstHalf)).isEmpty
                     && reader.append(split.suffix(from: 4)).compactMap(\.id) == [3],
                     "a frame split across reads waits for the rest of itself")
        suite.expect(reader.append(Data("{\"id\":6}\r\n".utf8)).compactMap(\.id) == [6],
                     "a server writing CRLF still speaks the same protocol")
        suite.expect(reader.append(Data("\n".utf8)).isEmpty,
                     "a blank line is not a frame")
        suite.expect(reader.append(Data("INFO loading plugin\n".utf8)).isEmpty,
                     "a log line on the protocol stream is skipped")

        var flooding = HermesACPLineReader()
        _ = flooding.append(Data(repeating: 0x20, count: (4 << 20) + 1))
        suite.expect(flooding.overflowed,
                     "a server writing more than a frame without a newline is not an ACP server")
    }

    private static func stopContracts(_ suite: TestSuite) {
        suite.expect(HermesACPProtocol.Stop.parse(["stopReason": "end_turn"]) == .endTurn
                     && HermesACPProtocol.Stop.parse(["stopReason": "cancelled"]) == .cancelled
                     && HermesACPProtocol.Stop.parse(["stopReason": "max_tokens"]) == .maxTokens
                     && HermesACPProtocol.Stop.parse(["stopReason": "max_turn_requests"]) == .maxTurnRequests
                     && HermesACPProtocol.Stop.parse(["stopReason": "refusal"]) == .refusal,
                     "every stop reason Hermes names is understood")
        suite.expect(HermesACPProtocol.Stop.parse([:]) == .endTurn
                     && HermesACPProtocol.Stop.parse(["stopReason": "something-new"]) == .endTurn,
                     "an answer without a reason it knows still ends the turn normally")
        suite.expect(HermesACPProtocol.Stop.cancelled.wasCancelled
                     && !HermesACPProtocol.Stop.endTurn.wasCancelled,
                     "only the island's own stop counts as cancelled")
    }

    private static func permissionContracts(_ suite: TestSuite) {
        let offered: [[String: Any]] = [
            ["optionId": "allow-1", "name": "Allow once", "kind": "allow_once"],
            ["optionId": "reject-1", "name": "Reject", "kind": "reject_once"],
        ]
        suite.expect(HermesACPProtocol.refusalOption(in: offered) == "reject-1",
                     "the offered refusal is chosen when Hermes asks to run something")
        suite.expect(HermesACPProtocol.refusalOption(in: [
            ["optionId": "yes", "name": "Yes", "kind": "allow_always"],
            ["optionId": "no-always", "name": "No", "kind": "reject_always"],
        ]) == "no-always",
                     "an always-refusal is taken when it is the only refusal offered")
        suite.expect(HermesACPProtocol.refusalOption(in: [
            ["optionId": "yes", "name": "Continue", "kind": "allow_once"],
            ["optionId": "stop", "name": "Deny this", "kind": "custom"],
        ]) == "stop",
                     "an option that reads as a denial is taken even when its kind is unknown")
        suite.expect(HermesACPProtocol.refusalOption(in: [
            ["optionId": "yes", "name": "Allow", "kind": "allow_once"],
        ]) == nil,
                     "a request with nothing to refuse is cancelled rather than approved")
        suite.expect(HermesACPProtocol.permissionSubject(["toolCall": ["title": "rm -rf build"]]) == "rm -rf build"
                     && HermesACPProtocol.permissionSubject(["toolCall": ["kind": "execute"]]) == "execute"
                     && HermesACPProtocol.permissionSubject([:]) == nil,
                     "the page can name what was refused")
    }

    // MARK: Finding the command

    private static func discoveryContracts(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        suite.expect(HermesACPSupport.command(nil) == "hermes"
                     && HermesACPSupport.command("") == "hermes"
                     && HermesACPSupport.command("   ") == "hermes"
                     && HermesACPSupport.command("  /opt/bin/hermes  ") == "/opt/bin/hermes",
                     "a blank command falls back to hermes and typed spaces are trimmed")
        suite.expect(HermesACPSupport.arguments == ["acp"],
                     "the server is the command's acp subcommand")

        let absolute = HermesACPSupport.candidates(command: "/opt/hermes/bin/hermes", home: home)
        suite.expect(absolute.count == 1 && absolute.first?.path == "/opt/hermes/bin/hermes",
                     "an absolute command is used where it points")
        let tilde = HermesACPSupport.candidates(command: "~/bin/hermes", home: home)
        suite.expect(tilde.count == 1
                     && tilde.first?.path == (NSString(string: "~/bin/hermes").expandingTildeInPath),
                     "a command written with a tilde is expanded")

        let bare = HermesACPSupport.candidates(command: nil, home: home, searchPath: "/custom/bin")
        // Hermes installs into ~/.local/bin, which a Finder launch never has
        // on its PATH, so it is searched first.
        suite.expect(bare.first?.path == "/Users/someone/.local/bin/hermes"
                     && bare.contains { $0.path == "/opt/homebrew/bin/hermes" }
                     && bare.contains { $0.path == "/usr/local/bin/hermes" }
                     && bare.last?.path == "/custom/bin/hermes",
                     "a bare command is searched for where a Finder launch cannot look")

        let relative = HermesACPSupport.candidates(command: "tools/hermes", home: home)
        suite.expect(relative.count == 1 && relative.first?.path == "/Users/someone/tools/hermes",
                     "a command with a slash is relative to home, not to the app")

        let folder = FileManager.default.temporaryDirectory
            .appending(path: "hermes-chat-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executable = folder.appending(path: "hermes", directoryHint: .notDirectory)
        let plain = folder.appending(path: "notes", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        suite.expect(HermesACPSupport.executable(command: executable.path, home: home) == nil,
                     "a command that does not exist is not run")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: executable)
            try Data().write(to: plain)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.path)
        } catch {
            suite.expect(false, "the command discovery fixture can be written: \(error)")
        }
        suite.expect(HermesACPSupport.executable(command: executable.path, home: home) == executable,
                     "an executable at the typed path is found")
        suite.expect(HermesACPSupport.executable(command: plain.path, home: home) == nil,
                     "a file that cannot be run is not the command")

        let environment = HermesACPSupport.environment(
            executable: URL(fileURLWithPath: "/Users/someone/.local/bin/hermes"),
            searchPath: "/custom/bin",
            base: ["PATH": "/usr/bin:/bin", "HERMES_ACP_SKIP_CONFIGURED_MCP": "1", "HOME": "/Users/someone"])
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        suite.expect(path.first == "/Users/someone/.local/bin"
                     && path.contains("/custom/bin")
                     && path.contains("/usr/bin")
                     && environment["HOME"] == "/Users/someone",
                     "the agent's own folder leads its PATH and the rest is kept")
        suite.expect(environment["HERMES_ACP_SKIP_CONFIGURED_MCP"] == nil,
                     "the agent's own configuration decides which servers a session gets")

        suite.expect(HermesACPSupport.workingDirectory(home: home) == "/Users/someone",
                     "a conversation starts in the person's home folder")
    }

    private static func transcriptContracts(_ suite: TestSuite) {
        let messages = (0..<HermesACPSupport.maximumMessages + 5).map {
            NotchHermesChatMessage(role: .person, text: "\($0)")
        }
        let trimmed = HermesACPSupport.trimmed(messages)
        suite.expect(trimmed.count == HermesACPSupport.maximumMessages
                     && trimmed.first?.text == "5"
                     && trimmed.last?.text == "\(HermesACPSupport.maximumMessages + 4)",
                     "an open conversation keeps its newest turns and drops the oldest")
        suite.expect(HermesACPSupport.trimmed(Array(messages.prefix(3))).count == 3,
                     "a short conversation is left as it is")
        let message = NotchHermesChatMessage(role: .note, text: "Stopped.")
        suite.expect(message.role == .note && message.text == "Stopped." && message.id == message.id,
                     "a line keeps its role, words and identity")
    }

    /// Hermes Chat was tried in development builds before new features became
    /// opt-in, so a switch already on is an install choice already made.
    private static func migrationContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.hermes-chat-availability.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            suite.expect(false, "the Hermes Chat availability suite can be created")
            return
        }
        defer { defaults.removePersistentDomain(forName: domain) }
        let key = AppFeature.notchHermesChat.availabilityKey
        Defaults.migrateNotchHermesChatAvailability(in: defaults)
        suite.expect(defaults.object(forKey: key) == nil,
                     "a Mac that never switched the chat on meets it on the Features page")
        defaults.set(true, forKey: DefaultsKey.notchHermesChatEnabled)
        Defaults.migrateNotchHermesChatAvailability(in: defaults)
        suite.expect(defaults.object(forKey: key) as? Bool == true,
                     "a chat already switched on stays installed after the update")
        defaults.set(false, forKey: key)
        Defaults.migrateNotchHermesChatAvailability(in: defaults)
        suite.expect(defaults.object(forKey: key) as? Bool == false,
                     "an uninstall chosen later is never undone by the migration")
    }

    // MARK: Wiring

    /// The service is not part of this test binary, so the lines that decide
    /// when the agent process runs and what the island shows are pinned at
    /// their source.
    private static func wiringContracts(_ suite: TestSuite) {
        func source(_ path: String) -> String {
            (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }
        let service = source("Sources/Vorssaint/Services/Notch/NotchHermesChatService.swift")
        suite.expect(service.contains("AppFeature.notchHermesChat.isAvailable")
                     && service.contains("UserDefaults.standard.bool(forKey: DefaultsKey.notchHermesChatEnabled)")
                     && service.contains("AppFeature.notch.isAvailable"),
                     "the agent only runs while the feature, its switch and the island are on")
        suite.expect(service.contains("client?.end()"),
                     "turning the feature off ends the agent process")
        suite.expect(service.contains("HermesACPSupport.executable(")
                     && service.contains("state = .failed(.notFound(command))"),
                     "a command that is not there is reported instead of started")

        let runtime = source("Sources/Vorssaint/App/FeatureRuntime.swift")
        suite.expect(runtime.contains(".notchHermesChat: {")
                     && runtime.contains("NotchHermesChatService.shared.syncWithPreferences()"),
                     "the feature runtime owns the conversation's lifetime")

        let support = source("Sources/Vorssaint/Services/Notch/NotchSupport.swift")
        suite.expect(support.contains("case .hermesChat: return AppFeature.notchHermesChat.isAvailable(in: defaults)"),
                     "the page is unavailable with its feature")
        suite.expect(support.contains("$0 != .hermesChat || defaults.bool(forKey: DefaultsKey.notchHermesChatEnabled)"),
                     "the page leaves the island when the chat is switched off")

        let catalog = source("Sources/Vorssaint/Core/FeatureCatalog.swift")
        suite.expect(catalog.contains("notchHermesChat")
                     && AppFeature.notchHermesChat.permissions.isEmpty
                     && AppFeature.notchHermesChat.enabledKeys == [DefaultsKey.notchHermesChatEnabled]
                     && AppFeature.notchHermesChat.group == .dynamicIsland
                     && !AppFeature.notchHermesChat.installedByDefault,
                     "the chat is an uninstalled island extension with one switch and no permission")
        suite.expect(AppFeature.notchHermesChat.symbolName == NotchModule.hermesChat.symbol,
                     "the hub and the island draw the same mark")

        let view = source("Sources/Vorssaint/UI/Notch/NotchView.swift")
        suite.expect(view.contains("case .hermesChat: NotchHermesChatView(size: pageSize)"),
                     "opening the page shows the conversation")
    }

    /// With the VERTUS hub installed the page is a hub client: a prompt names
    /// the hub's agent and says it comes from this Mac, a run's stream reads
    /// as the page's own events, and nothing from another run leaks in.
    private static func hubContracts(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("vertus-hub-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        suite.expect(VertusHubSupport.token(home: home) == nil, "no token file means no hub")
        try? FileManager.default.createDirectory(at: home.appendingPathComponent(".vertus"),
                                                 withIntermediateDirectories: true)
        try? "  secret\n".write(to: VertusHubSupport.tokenURL(home: home), atomically: true, encoding: .utf8)
        suite.expect(VertusHubSupport.token(home: home) == "secret", "the token is read trimmed")
        try? "\n".write(to: VertusHubSupport.tokenURL(home: home), atomically: true, encoding: .utf8)
        suite.expect(VertusHubSupport.token(home: home) == nil, "an empty token is no hub")

        let prompt = VertusHubSupport.prompt("Hello", token: "t")
        let body = prompt.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        suite.expect(prompt.httpMethod == "POST" && prompt.url?.path == "/api/prompt"
                     && body?["text"] as? String == "Hello" && body?["agent_id"] as? String == "primary",
                     "a prompt is queued for the hub's own agent")
        suite.expect(prompt.value(forHTTPHeaderField: "Authorization") == "Bearer t"
                     && prompt.value(forHTTPHeaderField: "X-Vertus-Client") == "local",
                     "a prompt carries the token and says it comes from this Mac")
        let events = VertusHubSupport.events(run: "r1", token: "t")
        suite.expect(events.url?.query == "run_id=r1", "a run's stream is asked for by its id")
        suite.expect(VertusHubSupport.cancel(run: "r1", token: "t").url?.path == "/api/runs/r1/cancel",
                     "stopping names the run")

        let accepted = try? JSONSerialization.data(withJSONObject: ["accepted": true, "run_id": "r9"])
        suite.expect(VertusHubSupport.runID(from: accepted, status: 202) == .success("r9"), "an accepted prompt names its run")
        let refused = try? JSONSerialization.data(withJSONObject: ["error": "agent degraded: thrashing"])
        suite.expect(VertusHubSupport.runID(from: refused, status: 503)
                     == .failure(VertusHubSupport.HubError(reason: "agent degraded: thrashing")),
                     "a refused prompt keeps the hub's reason")
        suite.expect(VertusHubSupport.runID(from: nil, status: 500)
                     == .failure(VertusHubSupport.HubError(reason: "HTTP 500")), "a bare failure names its status")
        let agents = try? JSONSerialization.data(withJSONObject: ["agents": [["id": "alpha", "model": "x"],
                                                                             ["id": "primary", "model": "gpt-4o"]]])
        suite.expect(VertusHubSupport.modelName(from: agents) == "gpt-4o", "the model is the primary agent's")

        func event(_ json: String) -> VertusHubSupport.Event? { VertusHubSupport.event(line: "data: " + json, run: "r1") }
        suite.expect(event(#"{"type":"text","text":"Hi","run_id":"r1"}"#) == .text("Hi"), "reply words stream")
        suite.expect(event(#"{"type":"text","text":"Hi","run_id":"r2"}"#) == .ignored, "another run's words stay out")
        suite.expect(event(#"{"type":"activity","text":"running terminal…","run_id":"r1"}"#) == .tool("terminal"),
                     "a tool the agent runs is named")
        suite.expect(event(#"{"type":"activity","text":"thinking…"}"#) == .ignored
                     && event(#"{"type":"activity","text":"running tools…"}"#) == .ignored,
                     "status chatter is not a line of the conversation")
        suite.expect(event(#"{"type":"done","run_id":"r1"}"#) == .done
                     && event(#"{"type":"cancelled"}"#) == .cancelled, "a run's end is heard")
        suite.expect(event(#"{"type":"error","message":"rate limited"}"#) == .error("rate limited"),
                     "a run's failure keeps its reason")
        suite.expect(VertusHubSupport.event(line: ": keepalive", run: "r1") == nil
                     && VertusHubSupport.event(line: "", run: "r1") == nil, "comments and separators mean nothing")

        var reader = VertusHubSupport.LineReader()
        let first = reader.append(Data("data: {\"a\":1}\r\n\ndata: {\"b".utf8))
        let second = reader.append(Data("\":2}\n".utf8))
        suite.expect(first == ["data: {\"a\":1}", ""] && second == ["data: {\"b\":2}"],
                     "a line split across chunks is read whole")
    }

    /// The hub stops before sending, posting, spending or deleting and asks:
    /// the page reads the request, offers only the answers the engine takes,
    /// and sends the one picked back under the island's name.
    private static func approvalContracts(_ suite: TestSuite) {
        func event(_ json: String) -> VertusHubSupport.Event? { VertusHubSupport.event(line: "data: " + json, run: "r1") }
        let request = event(#"{"type":"approval_request","run_id":"r1","approval_id":"a1","description":"VERTUS wants to delete files: rm notes.txt","command":"<terminal> (plugin approval rule)","choices":["once","session","always","deny","bogus"]}"#)
        guard case .approval(let approval)? = request else {
            suite.expect(false, "an approval request reads as an approval")
            return
        }
        suite.expect(approval.id == "a1" && approval.choices == [.once, .session, .always, .deny],
                     "an approval keeps its id and only the answers the engine takes")
        suite.expect(approval.headline == "VERTUS wants to delete files: rm notes.txt" && approval.detail == nil,
                     "a rule label is not shown as the command")
        let engineGate = NotchAgentApproval(id: "a2", description: "recursive delete",
                                            command: "rm -rf build", choices: [.once, .deny])
        suite.expect(engineGate.headline == "recursive delete" && engineGate.detail == "rm -rf build",
                     "the engine's own gate shows its reason with the command under it")
        suite.expect(NotchAgentApproval(id: "a3", description: " ", command: "git push", choices: []).headline == "git push",
                     "an approval with no reason names the command")
        guard case .approval(let fallback)? = event(#"{"type":"approval_request","approval_id":"a4","description":"x"}"#) else {
            suite.expect(false, "an approval without choices still reads")
            return
        }
        suite.expect(fallback.choices == [.once, .deny], "an approval without choices offers yes once or no")
        suite.expect(event(#"{"type":"approval_request","description":"x"}"#) == .ignored,
                     "an approval without an id cannot be answered and is not shown")

        suite.expect(event(#"{"type":"approval_resolved","approval_id":"a1","decision":"session"}"#) == .approvalSettled("a1", .allowed)
                     && event(#"{"type":"approval_resolved","approval_id":"a1","decision":"deny"}"#) == .approvalSettled("a1", .denied)
                     && event(#"{"type":"approval_resolved","approval_id":"a1","decision":"withdrawn"}"#) == .approvalSettled("a1", .expired),
                     "a settled approval says whether it was allowed, denied or expired")
        suite.expect(event(#"{"type":"approval_request","run_id":"r2","approval_id":"a9","description":"x"}"#) == .ignored,
                     "another run's approval stays out of this conversation")
        guard case .approval(let elsewhere)? = VertusHubSupport.event(
            line: #"data: {"type":"approval_request","run_id":"r2","approval_id":"a9","description":"x"}"#, run: nil) else {
            suite.expect(false, "the agent-wide watch reads every run's approvals")
            return
        }
        suite.expect(elsewhere.id == "a9", "an approval from a turn started elsewhere still reaches the island")
        let watch = VertusHubSupport.watch(token: "t")
        suite.expect(watch.url?.path == "/api/events" && watch.url?.query == "agent_id=primary",
                     "the watch follows the hub's own agent, every run")

        let answer = VertusHubSupport.answer("a1", choice: .session, token: "t")
        let body = answer.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        suite.expect(answer.httpMethod == "POST" && answer.url?.path == "/api/approvals/a1"
                     && body?["choice"] as? String == "session",
                     "an answer is posted to the approval it settles")
        suite.expect(answer.value(forHTTPHeaderField: "X-Vertus-Client") == "island"
                     && answer.value(forHTTPHeaderField: "Authorization") == "Bearer t",
                     "an answer carries the token and is credited to the island")
    }
}
