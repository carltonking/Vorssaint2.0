// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where the VERTUS conversation lives between launches:
/// `Application Support/<bundle id>/vertus-chat.json`, owner-only. Reads and
/// writes happen off the main thread; a write waits a moment for a reply that
/// is still streaming in to settle.
final class NotchHermesChatHistoryStore {
    private let queue = DispatchQueue(label: "com.vorssaint.notch.vertus-history", qos: .utility)
    private let settle: TimeInterval = 1
    private var pending: DispatchWorkItem?
    private var latest: [NotchHermesChatMessage]?

    private var fileURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("vertus-chat.json", isDirectory: false)
    }

    /// Reads the saved conversation and hands it back on the main thread.
    func load(_ completion: @escaping ([NotchHermesChatMessage]) -> Void) {
        let url = fileURL
        queue.async {
            let saved = url.flatMap { try? Data(contentsOf: $0) }.map(NotchHermesChatHistory.decode) ?? []
            DispatchQueue.main.async { completion(saved) }
        }
    }

    func save(_ messages: [NotchHermesChatMessage]) {
        queue.async {
            self.latest = messages
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.writeLatest() }
            self.pending = work
            self.queue.asyncAfter(deadline: .now() + self.settle, execute: work)
        }
    }

    /// Writes whatever is still waiting, before the app quits.
    func flush() {
        queue.sync {
            pending?.cancel()
            pending = nil
            writeLatest()
        }
    }

    // On `queue`.
    private func writeLatest() {
        guard let messages = latest, let url = fileURL else { return }
        latest = nil
        if messages.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = NotchHermesChatHistory.encode(messages),
              PrivateFileStore.createDirectory(at: url.deletingLastPathComponent()) else { return }
        PrivateFileStore.write(data, to: url)
    }
}
