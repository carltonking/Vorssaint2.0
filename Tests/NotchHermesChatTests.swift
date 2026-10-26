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
        silenceContracts(suite)
        routineReplyContracts(suite)
        reachOutContracts(suite)
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
        suite.expect(watch.url?.path == "/api/events" && watch.url?.query == nil,
                     "the watch follows the hub's own agent, every run")
        suite.expect(VertusHubSupport.watch(token: "t", since: 412).url?.query == "since=412",
                     "a watch that dropped resumes after the last event it saw")
        suite.expect(VertusHubSupport.watchEvent(line: #"data: {"type":"done","agent_id":"alpha","run_id":"x"}"#) == nil
                     && VertusHubSupport.watchEvent(line: #"data: {"type":"done","agent_id":"primary","run_id":"x"}"#) != nil,
                     "the fleet watch keeps only the hub agent's events")
        suite.expect(VertusHubSupport.sequence(line: #"data: {"type":"text","seq":412}"#) == 412
                     && VertusHubSupport.sequence(line: ": ping") == nil, "every streamed event names its place")
        suite.expect(request.flatMap { if case .approval(let a) = $0 { return a.runID } else { return nil } } == "r1",
                     "an approval remembers the turn that is waiting on it")

        // Waiting approvals the watch cannot replay come from the ledger:
        // only the hub agent's undecided rows, oldest first.
        let ledger = try? JSONSerialization.data(withJSONObject: ["approvals": [
            ["approval_id": "new", "agent_id": "primary", "run_id": "r5", "action": "VERTUS wants to push",
             "target": "<terminal> (plugin approval rule)", "decision": NSNull()],
            ["approval_id": "other-bot", "agent_id": "alpha", "action": "x", "target": "", "decision": NSNull()],
            ["approval_id": "old", "agent_id": "primary", "action": "recursive delete", "target": "rm -rf b",
             "decision": NSNull()],
        ]])
        let restored = VertusHubSupport.pendingApprovals(from: ledger)
        suite.expect(restored.map(\.id) == ["old", "new"] && restored.last?.runID == "r5"
                     && restored.allSatisfy { $0.choices == [.once, .deny] },
                     "approvals already waiting are restored, the hub agent's only, with the answers every one takes")

        func json(_ object: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: object) }
        suite.expect(VertusHubSupport.answerResult(status: 200, data: nil) == .accepted
                     && VertusHubSupport.answerResult(status: 404, data: nil) == .settled(.expired)
                     && VertusHubSupport.answerResult(status: 409, data: json(["error": "approval already settled: always"]))
                        == .settled(.allowed)
                     && VertusHubSupport.answerResult(status: 409, data: json(["error": "approval already settled: deny"]))
                        == .settled(.denied),
                     "an approval settled elsewhere clears with how it really ended")
        suite.expect(VertusHubSupport.answerResult(status: 0, data: nil) == .retry
                     && VertusHubSupport.answerResult(status: 500, data: nil) == .retry,
                     "an answer that did not get through leaves the approval answerable")

        let answer = VertusHubSupport.answer("a1", choice: .session, token: "t", approverToken: "ap")
        let body = answer.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        suite.expect(answer.httpMethod == "POST" && answer.url?.path == "/api/approvals/a1"
                     && body?["choice"] as? String == "session",
                     "an answer is posted to the approval it settles")
        suite.expect(answer.value(forHTTPHeaderField: "X-Vertus-Client") == "island"
                     && answer.value(forHTTPHeaderField: "Authorization") == "Bearer t",
                     "an answer carries the token and is credited to the island")
        suite.expect(answer.value(forHTTPHeaderField: "X-Vertus-Approver") == "ap",
                     "an answer carries the approver credential no agent is given")
        suite.expect(VertusHubSupport.approverTokenURL(home: URL(fileURLWithPath: "/Users/x")).path
                     == "/Users/x/.vertus/approver-token", "the approver credential lives beside the hub's token")
    }

    // MARK: VERTUS writing first

    /// A routine the hub fires on its own writes a reply nobody on the island
    /// asked for. Only those runs become messages, whole, once they end well,
    /// and the check-in that has nothing to say stays silent.
    private static func routineReplyContracts(_ suite: TestSuite) {
        func line(_ json: String) -> String { "data: " + json }
        func watched(_ json: String) -> VertusHubSupport.WatchEvent? { VertusHubSupport.watchEvent(line: line(json)) }
        func fired(_ run: String, routine: String = "rt1") -> String {
            #"{"type":"routine_fired","routine_id":""# + routine + #"","agent_id":"primary","run_id":""# + run + #"","manual":false,"seq":3}"#
        }
        func text(_ run: String, _ words: String) -> String {
            let object: [String: Any] = ["type": "text", "run_id": run, "agent_id": "primary", "text": words]
            return (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        func end(_ run: String, _ type: String = "done") -> String {
            #"{"type":""# + type + #"","run_id":""# + run + #"","agent_id":"primary"}"#
        }
        /// Feeds lines through the watch's own reading, as the client does,
        /// and returns every message that came out. A run asked about is
        /// answered at once from `kinds`, as the hub would; one missing there
        /// stays unanswered. Also returns every run asked about.
        func watch(_ replies: inout VertusRoutineReplies, _ lines: [String],
                   kinds: [String: VertusRoutineReplies.Kind] = [:]) -> (messages: [VertusRoutineReplies.Message], asked: [String]) {
            var messages: [VertusRoutineReplies.Message] = []
            var asked: [String] = []
            for json in lines {
                guard let event = watched(json) else { continue }
                switch replies.receive(event.event, run: event.run) {
                case .message(let message)?: messages.append(message)
                case .lookup(let run)?:
                    asked.append(run)
                    if let kind = kinds[run], let message = replies.classify(run: run, as: kind) {
                        messages.append(message)
                    }
                case nil: break
                }
            }
            return (messages, asked)
        }
        func feed(_ replies: inout VertusRoutineReplies, _ lines: [String],
                  kinds: [String: VertusRoutineReplies.Kind] = [:]) -> [VertusRoutineReplies.Message] {
            watch(&replies, lines, kinds: kinds).messages
        }
        func activity(_ run: String, _ words: String) -> String {
            #"{"type":"activity","run_id":""# + run + #"","agent_id":"primary","text":""# + words + #""}"#
        }

        suite.expect(watched(fired("r7")) == VertusHubSupport.WatchEvent(run: "r7", event: .routineFired(routine: "rt1", run: "r7")),
                     "a fired routine names itself and the run carrying its reply")
        suite.expect(watched(#"{"type":"routine_fired","routine_id":"rt1","run_id":""}"#)?.event == .ignored
                     && watched(#"{"type":"routine_fired","run_id":"r7"}"#)?.event == .ignored,
                     "a fired routine without its run or its id has nothing to follow")
        suite.expect(VertusHubSupport.event(line: line(fired("r7")), run: "r1") == .ignored,
                     "a routine's run stays out of the island's own turn")
        suite.expect(watched(#"{"type":"routine_skipped","routine_id":"rt1","run_id":""}"#)?.event == .ignored
                     && watched(#"{"type":"memory_write","run_id":"r7"}"#)?.event == .ignored,
                     "other hub traffic is still ignored")

        var replies = VertusRoutineReplies()
        let messages = feed(&replies, [
            fired("r7"), text("r7", "Your flight "), text("terminal", "unrelated words"),
            text("r7", "leaves at **9:40**."), end("terminal"), end("r7"), end("r7"),
        ], kinds: ["terminal": .other])
        suite.expect(messages == [VertusRoutineReplies.Message(run: "r7", routine: "rt1", text: "Your flight leaves at **9:40**.")],
                     "a routine's reply comes out once, whole, when its run is done, and a repeated done sends nothing")
        suite.expect(feed(&replies, [text("other", "Hello"), end("other")], kinds: ["other": .other]).isEmpty,
                     "a run no routine started, such as the terminal's, is never a message")
        suite.expect(replies.followed == 0, "a finished run is let go")

        var own = VertusRoutineReplies()
        own.ignore(run: "mine")
        suite.expect(feed(&own, [fired("mine"), text("mine", "The answer"), end("mine")]).isEmpty && own.followed == 0,
                     "the island's own run is never shown a second time as a message sent unasked")
        var late = VertusRoutineReplies()
        _ = feed(&late, [fired("r8"), text("r8", "half")])
        late.ignore(run: "r8")
        suite.expect(feed(&late, [text("r8", " more"), end("r8")]).isEmpty,
                     "a run the island claims as its own stops being collected")

        var quiet = VertusRoutineReplies()
        suite.expect(feed(&quiet, [fired("c1"), text("c1", "NOTHING_"), text("c1", "TO_REPORT\n"), end("c1")]).isEmpty
                     && feed(&quiet, [fired("c2"), text("c2", "  NOTHING_TO_REPORT  "), end("c2")]).isEmpty,
                     "a check-in with nothing to report says nothing at all")
        suite.expect(feed(&quiet, [fired("c3"), text("c3", "nothing_to_report"), end("c3")]).map(\.text) == ["nothing_to_report"],
                     "only the exact sentinel is silence")
        suite.expect(feed(&quiet, [fired("c4"), text("c4", " \n "), end("c4")]).isEmpty,
                     "an empty reply is not a message")

        var failing = VertusRoutineReplies()
        suite.expect(feed(&failing, [fired("e1"), text("e1", "Half a thou"), end("e1", "error")]).isEmpty
                     && feed(&failing, [fired("x1"), text("x1", "Started"), end("x1", "cancelled")]).isEmpty
                     && failing.followed == 0,
                     "a routine that fails or is cancelled stays silent and is let go")
        suite.expect(feed(&failing, [end("e1")]).isEmpty, "a done after a failure finds nothing to send")

        var many = VertusRoutineReplies()
        let runs = (0..<(VertusRoutineReplies.maximumRuns + 3)).map { "m\($0)" }
        _ = feed(&many, runs.flatMap { [fired($0), text($0, "from \($0)")] })
        suite.expect(many.followed == VertusRoutineReplies.maximumRuns,
                     "only so many routine runs are followed at once")
        suite.expect(feed(&many, [end(runs[0])]).isEmpty && feed(&many, [end(runs.last!)]).map(\.text) == ["from \(runs.last!)"],
                     "the oldest run whose end never came is the one let go")

        var long = VertusRoutineReplies()
        let chunk = String(repeating: "a", count: 1_000)
        let chunks = (0..<(VertusRoutineReplies.maximumCharacters / 1_000 + 3)).map { _ in text("l1", chunk) }
        let capped = feed(&long, [fired("l1")] + chunks + [end("l1")])
        suite.expect(capped.count == 1 && capped[0].text.count == VertusRoutineReplies.maximumCharacters + 1
                     && capped[0].text.hasSuffix("…"),
                     "a runaway reply is cut at the limit and says so")

        // The hub sends `routine_fired` to the fleet stream only: on the
        // agent's stream a routine's run arrives as bare text and done, so
        // the run is asked about and collected on the hub's say-so.
        var real = VertusRoutineReplies()
        let routine = watch(&real, [
            activity("q1", "thinking…"), text("q1", "Your flight "), text("q1", "leaves at 9:40."), end("q1"),
        ], kinds: ["q1": .routine("rt1")])
        suite.expect(routine.messages == [VertusRoutineReplies.Message(run: "q1", routine: "rt1", text: "Your flight leaves at 9:40.")]
                     && routine.asked == ["q1"],
                     "a routine's run with no routine_fired is asked about once and its reply delivered")
        let person = watch(&real, [text("u1", "Sure, here it is."), end("u1")], kinds: ["u1": .other])
        suite.expect(person.messages.isEmpty && real.followed == 0,
                     "a run the hub says is not a routine is let go")
        suite.expect(watch(&real, [activity("u1", "memory write"), text("q1", "late")]).asked.isEmpty,
                     "a run already settled is not asked about again")

        var held = VertusRoutineReplies()
        let early = watch(&held, [text("h1", "Rain at 4."), end("h1")])
        suite.expect(early.messages.isEmpty && early.asked == ["h1"],
                     "a done heard before the hub says what the run is waits for the answer")
        suite.expect(held.classify(run: "h1", as: .routine("rt2"))
                     == VertusRoutineReplies.Message(run: "h1", routine: "rt2", text: "Rain at 4."),
                     "the held reply goes out when the hub says the run is a routine")
        suite.expect(held.classify(run: "h1", as: .routine("rt2")) == nil && feed(&held, [end("h1")]).isEmpty,
                     "a held reply goes out once")
        var unasked = VertusRoutineReplies()
        _ = watch(&unasked, [text("h2", "Draft"), end("h2")])
        suite.expect(unasked.classify(run: "h2", as: .other) == nil && unasked.followed == 0,
                     "a held run the hub says is someone's turn is dropped")

        var firedLate = VertusRoutineReplies()
        suite.expect(feed(&firedLate, [text("f1", "Hello "), fired("f1"), text("f1", "there."), end("f1")])
                     .map(\.text) == ["Hello there."] && firedLate.classify(run: "f1", as: .other) == nil,
                     "a routine_fired that does arrive names the run, keeping what it wrote before")

        var checkIn = VertusRoutineReplies()
        suite.expect(feed(&checkIn, [
            text("c5", "Let me check your mail…"), activity("c5", "running tools…"),
            activity("c5", "running gmail_search…"), text("c5", "NOTHING_TO_REPORT"), end("c5"),
        ], kinds: ["c5": .routine("rt1")]).isEmpty,
                     "a check-in that talks before its tool and ends with nothing to report stays silent")
        suite.expect(feed(&checkIn, [
            text("c6", "Checking your calendar."), activity("c6", "running calendar_list…"),
            text("c6", "Dentist at 3."), end("c6"),
        ], kinds: ["c6": .routine("rt1")]).map(\.text) == ["Dentist at 3."],
                     "the message is what the run wrote after its last tool")
        suite.expect(feed(&checkIn, [
            text("c7", "Good "), activity("c7", "thinking…"), activity("c7", "running tools…"), text("c7", "morning."), end("c7"),
        ], kinds: ["c7": .routine("rt1")]).map(\.text) == ["Good morning."],
                     "thinking, and the unnamed tools line, are not a tool boundary")

        func runJSON(_ object: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: object) }
        suite.expect(VertusHubSupport.runKind(from: runJSON(["run": ["run_id": "q1", "run_kind": "routine", "routine_id": "rt1",
                                                                     "source": "routine:rt1"], "messages": []]))
                     == .routine("rt1"),
                     "a routine's run is named by its routine")
        suite.expect(VertusHubSupport.runKind(from: runJSON(["run": ["run_kind": "routine", "routine_id": NSNull(),
                                                                     "source": "routine:rt9"]])) == .routine("rt9")
                     && VertusHubSupport.runKind(from: runJSON(["run": ["run_kind": "routine"]])) == .routine(nil),
                     "a routine's run without its id falls back to its source")
        suite.expect(VertusHubSupport.runKind(from: runJSON(["run": ["run_kind": "user"]])) == .other
                     && VertusHubSupport.runKind(from: runJSON(["run": ["run_kind": "handoff"]])) == .other,
                     "every other run kind is someone's turn")
        suite.expect(VertusHubSupport.runKind(from: runJSON(["error": "run not found: x"])) == nil
                     && VertusHubSupport.runKind(from: nil) == nil,
                     "an answer that describes no run says nothing")
        let lookup = VertusHubSupport.run("q1", token: "t")
        suite.expect(lookup.httpMethod == "GET" && lookup.url?.path == "/api/runs/q1"
                     && lookup.value(forHTTPHeaderField: "Authorization") == "Bearer t",
                     "a run is looked up by its id")

        let cursor = VertusWatchCursor()
        suite.expect(cursor.value == nil, "a first watch starts live")
        cursor.advance(to: 41)
        cursor.advance(to: 7)
        suite.expect(cursor.value == 41
                     && VertusHubSupport.watch(token: "t", since: cursor.value).url?.query == "since=41",
                     "a client started after a retry resumes after the last event any earlier one heard")
        cursor.reset()
        suite.expect(cursor.value == nil, "a conversation switched off starts over live")

        let listing = try? JSONSerialization.data(withJSONObject: ["routines": [
            ["routine_id": "rt1", "agent_id": "primary", "name": " Morning check-in ", "prompt": "Check in."],
            ["routine_id": "rt2", "agent_id": "primary", "name": "", "prompt": "x"],
            ["routine_id": "", "name": "orphan"],
        ]])
        suite.expect(VertusHubSupport.routineNames(from: listing) == ["rt1": "Morning check-in"]
                     && VertusHubSupport.routineNames(from: nil).isEmpty,
                     "routines are named by id, and one without a name is left to the plain line")
        let routines = VertusHubSupport.routines(token: "t")
        suite.expect(routines.httpMethod == "GET" && routines.url?.path == "/api/routines"
                     && routines.url?.query == "agent_id=primary"
                     && routines.value(forHTTPHeaderField: "Authorization") == "Bearer t",
                     "the routine names are the hub agent's own")
    }

    /// A message nobody waits on never pins the island or takes a page in
    /// use, and the line over it says VERTUS wrote first, in every language.
    private static func reachOutContracts(_ suite: TestSuite) {
        func attention(expanded: Bool, onChat: Bool, covered: Bool = false, hour: Int = 12,
                       routine: String? = nil) -> NotchAgentReachOut {
            NotchAgentReachOut.attention(expanded: expanded, onChat: onChat, covered: covered, hour: hour, routine: routine)
        }
        suite.expect(attention(expanded: false, onChat: false) == .open
                     && attention(expanded: false, onChat: true) == .open
                     && attention(expanded: false, onChat: false, routine: "morning-brief") == .open,
                     "a closed island opens on the conversation")
        suite.expect(attention(expanded: true, onChat: true) == .append,
                     "with the conversation on screen the message just lands")
        suite.expect(attention(expanded: true, onChat: false) == .nudge,
                     "a page in use is not taken; the companion reacts instead")
        suite.expect(attention(expanded: true, onChat: true, covered: true) == .nudge,
                     "a conversation covered by the sections, the app panel or the Command Bar is not on screen")

        for hour in [22, 23, 0, 3, 6] {
            suite.expect(attention(expanded: false, onChat: false, hour: hour) == .append
                         && attention(expanded: true, onChat: false, hour: hour) == .append,
                         "at \(hour):00 a message only lands, nothing opens or reacts")
        }
        for hour in [7, 12, 21] {
            suite.expect(attention(expanded: false, onChat: false, hour: hour) == .open,
                         "at \(hour):00 a closed island still opens")
        }
        suite.expect(attention(expanded: false, onChat: false, routine: "memory-consolidation") == .append
                     && attention(expanded: true, onChat: false, routine: " Memory-Consolidation ") == .append,
                     "a housekeeping routine never interrupts")

        let message = NotchHermesChatMessage(role: .proactive, text: "Hi", source: "Morning check-in")
        suite.expect(message.role == .proactive && message.source == "Morning check-in"
                     && NotchHermesChatMessage(role: .hermes, text: "x").source == nil,
                     "a message sent unasked keeps the routine that wrote it")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.notchHermesChat(language)
            suite.expect(!strings.reachedOut.isEmpty && strings.reachedOut(nil) == strings.reachedOut
                         && strings.reachedOut("") == strings.reachedOut,
                         "an unnamed routine reads as the plain line in \(language)")
            suite.expect(strings.reachedOut("Morning check-in").contains("Morning check-in")
                         && strings.reachedOutFormat.contains("%1$@"),
                         "a named routine is credited in \(language)")
        }
    }

    /// The check-in's "nothing to say" reads the same on the island as on
    /// the hub, wrapped or not; with other words around it, it is a message.
    private static func silenceContracts(_ suite: TestSuite) {
        for quiet in ["NOTHING_TO_REPORT", "  NOTHING_TO_REPORT\n", "`NOTHING_TO_REPORT`",
                      "\"NOTHING_TO_REPORT\"", "```\nNOTHING_TO_REPORT\n```"] {
            suite.expect(VertusRoutineReplies.isSilence(quiet), "\(quiet.debugDescription) keeps the island silent")
        }
        for spoken in ["NOTHING_TO_REPORT, sir.", "Nothing to report", "Mail: NOTHING_TO_REPORT", ""] {
            suite.expect(!VertusRoutineReplies.isSilence(spoken), "\(spoken.debugDescription) is a real message")
        }
    }
}
