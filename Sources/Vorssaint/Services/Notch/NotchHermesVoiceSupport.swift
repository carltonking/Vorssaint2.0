// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind talking to VERTUS: when the microphone may listen,
/// when a pause means the person is done, and what a Markdown reply sounds
/// like read aloud. Kept apart from Speech and AVFoundation so every rule can
/// be checked without a microphone.
enum NotchHermesVoiceSupport {
    /// Where dictation stands. `denied` holds for the rest of the app's life:
    /// the system will not ask again, so the button stops offering.
    enum Phase: Equatable {
        case idle
        /// Waiting on the system's Speech and Microphone prompts.
        case requesting
        case listening
        case denied
    }

    /// What the system says about one permission, reduced to what matters
    /// here.
    enum Authorization: Equatable {
        case granted
        case denied
        case undetermined
    }

    enum Event: Equatable {
        /// The microphone button was pressed.
        case toggle
        /// The permission prompts were answered (both granted, or not).
        case permission(granted: Bool)
        /// The person stopped talking long enough to count as done.
        case silence
        /// The recognizer ended on its own, or failed.
        case ended
    }

    /// What the service does for a transition, so the side effects stay in
    /// one place and the order of them in another.
    enum Effect: Equatable {
        case none
        case requestPermission
        case startListening
        /// Stop the microphone and send whatever was heard.
        case stopAndSend
        /// Permission was refused: say why once, in the conversation.
        case explainDenied
    }

    static func transition(_ phase: Phase, _ event: Event) -> (phase: Phase, effect: Effect) {
        switch (phase, event) {
        case (.idle, .toggle):
            return (.requesting, .requestPermission)
        case (.requesting, .permission(let granted)):
            return granted ? (.listening, .startListening) : (.denied, .explainDenied)
        case (.listening, .toggle), (.listening, .silence), (.listening, .ended):
            return (.idle, .stopAndSend)
        default:
            // A second press while the prompts are up, a late silence after
            // stopping, anything once denied: nothing to do.
            return (phase, .none)
        }
    }

    /// Where a page opening starts: a refusal recorded earlier disables the
    /// button at once rather than after a press that cannot work.
    static func initialPhase(speech: Authorization, microphone: Authorization) -> Phase {
        speech == .denied || microphone == .denied ? .denied : .idle
    }

    // MARK: Silence

    /// A pause this long after words means the sentence is finished.
    static let silenceTimeout: TimeInterval = 1.5
    /// Before the first word, the person is still gathering the thought; the
    /// microphone waits longer before giving up on an empty turn.
    static let openingTimeout: TimeInterval = 8

    static func shouldStop(heardSpeech: Bool, quietFor: TimeInterval) -> Bool {
        quietFor >= (heardSpeech ? silenceTimeout : openingTimeout)
    }

    /// What the field shows while dictating: anything typed first, then the
    /// words heard so far.
    static func draft(typed: String, dictated: String) -> String {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let dictated = dictated.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty { return dictated }
        if dictated.isEmpty { return typed }
        return typed + " " + dictated
    }

    // MARK: Speaking

    /// Only what VERTUS said is read aloud: never your own words echoed back,
    /// tool lines or the island's notes.
    static func shouldSpeak(_ role: NotchHermesChatMessage.Role, enabled: Bool) -> Bool {
        guard enabled else { return false }
        return role == .hermes || role == .proactive
    }

    /// A reply as a person would read it out: the words of a Markdown reply
    /// without the symbols that draw it. Links read as their label, code as
    /// its text, and headings, bullets, quotes and rules as nothing.
    static func spokenText(_ markdown: String) -> String {
        var lines: [String] = []
        for raw in markdown.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            // Fence markers and horizontal rules carry no words.
            if line.hasPrefix("```") || line.hasPrefix("~~~") { continue }
            if line.count >= 3, Set(line.replacingOccurrences(of: " ", with: "")).isSubset(of: ["-", "*", "_"]) {
                continue
            }
            line = replacing(line, #"^#{1,6}\s+"#, with: "")
            line = replacing(line, #"^(>\s*)+"#, with: "")
            line = replacing(line, #"^[-*+•]\s+(\[[ xX]\]\s+)?"#, with: "")
            lines.append(line)
        }
        var text = lines.joined(separator: "\n")
        // Images read as their description, links as their label.
        text = replacing(text, #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1")
        text = replacing(text, #"\[([^\]]+)\]\([^)]*\)"#, with: "$1")
        // Emphasis and code marks around words; a lone underscore inside a
        // name (snake_case) is left alone.
        text = replacing(text, #"(\*\*|__|~~)(.+?)\1"#, with: "$2")
        text = replacing(text, #"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, with: "$1")
        text = replacing(text, #"(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)"#, with: "$1")
        text = text.replacingOccurrences(of: "`", with: "")
        // Table pipes would be read as "vertical bar".
        text = text.replacingOccurrences(of: "|", with: " ")
        text = replacing(text, #"[ \t]{2,}"#, with: " ")
        text = replacing(text, #"\n{3,}"#, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(_ text: String, _ pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
