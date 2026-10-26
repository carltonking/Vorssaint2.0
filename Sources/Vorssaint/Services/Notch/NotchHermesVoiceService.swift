// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation
import Speech

/// The VERTUS page's voice: push-to-talk dictation into the message field,
/// and replies read aloud when the speaker is on. Apple's Speech and
/// AVFoundation only; recognition stays on the Mac whenever the recognizer
/// can do it there.
///
/// Main thread only. Created the first time the page offers the microphone
/// or a reply is to be spoken, never by the feature runtime: nothing here
/// runs, listens or asks for a permission until someone presses a button.
final class NotchHermesVoiceService: ObservableObject {
    private static var created: NotchHermesVoiceService?

    static var shared: NotchHermesVoiceService {
        if let created { return created }
        let service = NotchHermesVoiceService()
        created = service
        return service
    }

    /// The instance if anything has used voice yet. Stopping a conversation
    /// that never spoke has nothing to silence, and should not build the
    /// synthesizer just to say so.
    static var existing: NotchHermesVoiceService? { created }

    @Published private(set) var phase: NotchHermesVoiceSupport.Phase
    /// The words heard so far in the current dictation.
    @Published private(set) var heard = ""

    private let synthesizer = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastChange = Date()
    /// Receives the transcript when a dictation ends with words in it.
    private var deliver: ((String) -> Void)?
    /// Which dictation the recognizer's callbacks belong to: one stopped
    /// can still have results queued on the main thread.
    private var generation = 0

    private init() {
        phase = NotchHermesVoiceSupport.initialPhase(
            speech: Self.speechAuthorization(), microphone: Self.microphoneAuthorization())
    }

    private var text: NotchHermesChatStrings {
        FeatureStrings.notchHermesChat(L10n.shared.language)
    }

    // MARK: Dictation

    /// Access granted in System Settings after a refusal takes effect the
    /// next time the page opens, without restarting the app.
    func refreshAuthorization() {
        guard phase == .idle || phase == .denied else { return }
        let next = NotchHermesVoiceSupport.initialPhase(
            speech: Self.speechAuthorization(), microphone: Self.microphoneAuthorization())
        if next != phase { phase = next }
    }

    /// The microphone button: starts listening, or stops and sends what was
    /// heard to `deliver`.
    func toggleDictation(deliver: @escaping (String) -> Void) {
        if phase == .idle { self.deliver = deliver }
        handle(.toggle)
    }

    /// Stops listening without sending: the page went away mid-sentence.
    func cancelDictation() {
        deliver = nil
        guard phase == .listening || phase == .requesting else { return }
        _ = finishListening()
        phase = .idle
    }

    private func handle(_ event: NotchHermesVoiceSupport.Event) {
        let (next, effect) = NotchHermesVoiceSupport.transition(phase, event)
        if next != phase { phase = next }
        switch effect {
        case .none:
            break
        case .requestPermission:
            // The person is about to talk: VERTUS stops reading over them.
            stopSpeaking()
            requestPermission()
        case .startListening:
            guard startListening() else {
                deliver = nil
                phase = .idle
                NotchHermesChatService.shared.addNote(text.dictationUnavailable)
                return
            }
        case .stopAndSend:
            let words = finishListening()
            let receiver = deliver
            deliver = nil
            if !words.isEmpty { receiver?(words) }
        case .explainDenied:
            deliver = nil
            NotchHermesChatService.shared.addNote(text.dictationDenied)
        }
    }

    /// Speech Recognition first, then the microphone, each asked only while
    /// the system has no answer yet; an earlier answer comes straight back.
    private func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.phase == .requesting else { return }
                guard status == .authorized else {
                    self.handle(.permission(granted: false))
                    return
                }
                Permissions.shared.requestMicrophone { [weak self] granted in
                    guard let self, self.phase == .requesting else { return }
                    self.handle(.permission(granted: granted))
                }
            }
        }
    }

    private func startListening() -> Bool {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return false }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On the Mac when it can be: the words never leave it.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No input device (a Mac mini with nothing plugged in) reports an
        // empty format, and installing a tap on it raises.
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }

        generation += 1
        let current = generation
        self.engine = engine
        self.request = request
        heard = ""
        lastChange = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let ended = result?.isFinal ?? (error != nil)
            DispatchQueue.main.async {
                guard let self, self.generation == current, self.phase == .listening else { return }
                if let words, words != self.heard {
                    self.heard = words
                    self.lastChange = Date()
                }
                if ended { self.handle(.ended) }
            }
        }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.phase == .listening else { return }
            let heardSpeech = !self.heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if NotchHermesVoiceSupport.shouldStop(heardSpeech: heardSpeech,
                                                  quietFor: Date().timeIntervalSince(self.lastChange)) {
                self.handle(.silence)
            }
        }
        return true
    }

    /// Releases the microphone and returns what was heard.
    private func finishListening() -> String {
        generation += 1
        silenceTimer?.invalidate()
        silenceTimer = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heard.isEmpty { heard = "" }
        return words
    }

    // MARK: Speaking

    /// Reads a reply aloud, after any still being read. Nothing is read over
    /// a person who is dictating.
    func speak(_ markdown: String) {
        guard phase != .listening else { return }
        let words = NotchHermesVoiceSupport.spokenText(markdown)
        guard !words.isEmpty else { return }
        synthesizer.speak(AVSpeechUtterance(string: words))
    }

    func stopSpeaking() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// The conversation ended: silent and not listening.
    func reset() {
        cancelDictation()
        stopSpeaking()
    }

    // MARK: Authorization

    private static func speechAuthorization() -> NotchHermesVoiceSupport.Authorization {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    private static func microphoneAuthorization() -> NotchHermesVoiceSupport.Authorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }
}
