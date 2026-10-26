// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import LinkPresentation

/// The previews under links an agent sends on the island: the page's title,
/// its site and its image, fetched once per link with Apple's
/// LinkPresentation and kept for the rest of the app's life. Nothing is
/// fetched while a view draws; a card asks from its task and redraws when the
/// answer is in.
///
/// Main thread only. A provider answers on a queue of its own and the result
/// is carried back here.
final class NotchLinkPreviewService: ObservableObject {
    static let shared = NotchLinkPreviewService()

    struct Preview: Equatable {
        let title: String?
        let site: String
        let image: NSImage?

        static func == (lhs: Preview, rhs: Preview) -> Bool {
            lhs.title == rhs.title && lhs.site == rhs.site && lhs.image === rhs.image
        }
    }

    enum Entry: Equatable {
        case loading
        /// The page answered; its title or image may still be missing.
        case loaded(Preview)
        /// The page did not answer: the card stays a plain link.
        case failed
    }

    /// A page that has not answered by then is shown as a plain link.
    private static let fetchTimeout: TimeInterval = 12
    /// Previews kept, newest first out; a long conversation does not hold
    /// every image it ever showed.
    private static let capacity = 120

    @Published private(set) var entries: [URL: Entry] = [:]
    private var order: [URL] = []
    /// The links found in each message's words, by the words: worked out
    /// once rather than on every redraw. Not published, so reading it while
    /// drawing changes nothing that is observed.
    private var linkCache: [String: [URL]] = [:]

    private init() {}

    /// The web links in an agent's message, in order and each once.
    func links(in text: String) -> [URL] {
        if let known = linkCache[text] { return known }
        let found = InstinctMessagesSupport.links(in: text)
        if linkCache.count > Self.capacity * 4 { linkCache.removeAll() }
        linkCache[text] = found
        return found
    }

    /// Starts fetching a link's preview unless it is known or on its way.
    func load(_ url: URL) {
        guard entries[url] == nil else { return }
        remember(url, .loading)
        let provider = LPMetadataProvider()
        provider.timeout = Self.fetchTimeout
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            guard let metadata, error == nil else {
                DispatchQueue.main.async { self?.remember(url, .failed) }
                return
            }
            let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let site = (metadata.url ?? metadata.originalURL ?? url).host ?? url.absoluteString
            let finish: (NSImage?) -> Void = { image in
                DispatchQueue.main.async {
                    self?.remember(url, .loaded(Preview(title: title?.isEmpty == false ? title : nil,
                                                        site: Self.displayHost(site), image: image)))
                }
            }
            guard let provider = metadata.imageProvider ?? metadata.iconProvider,
                  provider.canLoadObject(ofClass: NSImage.self) else {
                finish(nil)
                return
            }
            provider.loadObject(ofClass: NSImage.self) { image, _ in finish(image as? NSImage) }
        }
    }

    private func remember(_ url: URL, _ entry: Entry) {
        if entries[url] == nil { order.append(url) }
        entries[url] = entry
        while order.count > Self.capacity {
            entries[order.removeFirst()] = nil
        }
    }

    /// `www.` says nothing about which site it is.
    private static func displayHost(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
