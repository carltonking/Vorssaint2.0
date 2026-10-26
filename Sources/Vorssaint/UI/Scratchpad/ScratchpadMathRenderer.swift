// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import WebKit

/// Typesets the editor's `$…$` and `$$…$$` as Obsidian does, and loads the
/// images `![[…]]` embeds, as pictures the live editor draws over the source.
///
/// AppKit has no TeX layout, so one offscreen web view runs KaTeX and each
/// formula comes back as a snapshot, cached by its source, size and colour.
/// KaTeX is fetched from its CDN the first time and kept by WebKit's cache;
/// until it loads, or offline, a formula stays as its typed source. The TeX
/// is passed to the page as an argument, never spliced into script, and
/// KaTeX's `trust` stays off, so a note cannot run code through it.
@MainActor
final class ScratchpadMathRenderer: NSObject, WKNavigationDelegate {
    static let shared = ScratchpadMathRenderer()
    /// Posted when a picture asked for earlier is ready to draw.
    nonisolated static let didRender = Notification.Name("VorssaintScratchpadMathDidRender")

    private struct Key: Hashable {
        let source: String
        /// A table's rows rather than TeX.
        var rows: [[String]]? = nil
        let display: Bool
        let size: Int
        let color: String
    }

    private static let katexVersion = "0.16.11"
    private static let cacheLimit = 400

    private var images: [Key: NSImage] = [:]
    private var order: [Key] = []
    private var failed: Set<Key> = []
    private var queue: [Key] = []
    private var queued: Set<Key> = []
    private var rendering = false
    private var web: WKWebView?
    private var pageReady = false
    private var pageFailedAt: Date?

    private var embeds: [URL: NSImage] = [:]
    private var loadingEmbeds: Set<URL> = []
    private var failedEmbeds: Set<URL> = []

    // MARK: - Math

    /// The typeset formula, or nil while it is being made (or cannot be).
    func image(tex: String, display: Bool, fontSize: CGFloat, color: NSColor) -> NSImage? {
        let key = Key(source: tex, display: display, size: Int(fontSize.rounded()), color: Self.hex(color))
        if let image = images[key] { return image }
        guard !failed.contains(key), !queued.contains(key) else { return nil }
        queued.insert(key)
        queue.append(key)
        pump()
        return nil
    }

    /// A Markdown table drawn as a grid, as Obsidian shows one. Cells go into
    /// the page as text, never as markup.
    func image(table rows: [[String]], fontSize: CGFloat, color: NSColor) -> NSImage? {
        let key = Key(source: "", rows: rows, display: true, size: Int(fontSize.rounded()), color: Self.hex(color))
        if let image = images[key] { return image }
        guard !failed.contains(key), !queued.contains(key) else { return nil }
        queued.insert(key)
        queue.append(key)
        pump()
        return nil
    }

    private func pump() {
        guard !rendering, !queue.isEmpty else { return }
        guard pageReady else {
            loadPageIfNeeded()
            return
        }
        rendering = true
        let key = queue.removeFirst()
        let script = """
        const box = document.getElementById('m');
        box.style.fontSize = size + 'px';
        box.style.color = color;
        if (rows) {
            box.textContent = '';
            const table = document.createElement('table');
            rows.forEach((row, i) => {
                const tr = table.insertRow();
                row.forEach(cell => {
                    const td = document.createElement(i === 0 ? 'th' : 'td');
                    td.textContent = cell;
                    tr.appendChild(td);
                });
            });
            box.appendChild(table);
        } else {
            katex.render(tex, box, {displayMode: display, throwOnError: false, trust: false, output: 'html'});
        }
        await Promise.all([...document.fonts].filter(f => f.status !== 'loaded').map(f => f.load().catch(() => 0)));
        await document.fonts.ready;
        await new Promise(r => setTimeout(r, 0));
        const k = box.querySelector('table') || box.querySelector('.katex-display > .katex') || box.querySelector('.katex') || box;
        const r = k.getBoundingClientRect();
        return [r.left, r.top, r.width, r.height];
        """
        web?.callAsyncJavaScript(script,
                                 arguments: ["tex": key.source, "display": key.display,
                                             "rows": key.rows.map { $0 as Any } ?? NSNull(),
                                             "size": key.size, "color": key.color],
                                 in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let box = value as? [Double], box.count == 4,
                  box[2] > 0, box[3] > 0, let web = self.web else {
                self.finish(key, image: nil)
                return
            }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = NSRect(x: box[0] - 1, y: box[1] - 1, width: box[2] + 2, height: box[3] + 2)
            web.takeSnapshot(with: configuration) { [weak self] image, _ in
                self?.finish(key, image: image)
            }
        }
    }

    private func finish(_ key: Key, image: NSImage?) {
        queued.remove(key)
        rendering = false
        if let image {
            images[key] = image
            order.append(key)
            if order.count > Self.cacheLimit {
                images[order.removeFirst()] = nil
            }
            NotificationCenter.default.post(name: Self.didRender, object: self)
        } else {
            failed.insert(key)
        }
        pump()
    }

    private func loadPageIfNeeded() {
        if web != nil { return }
        // After a failed load (offline) try again only after a pause, not on
        // every keystroke.
        if let pageFailedAt, Date().timeIntervalSince(pageFailedAt) < 30 { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1600, height: 800), configuration: configuration)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        self.web = web
        let base = "https://cdn.jsdelivr.net/npm/katex@\(Self.katexVersion)/dist/"
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <link rel="stylesheet" href="\(base)katex.min.css">
        <script src="\(base)katex.min.js"></script>
        <style>html,body{margin:0;padding:8px;background:transparent}
        #m{display:inline-block;font-family:-apple-system,sans-serif}.katex-display{margin:0}.katex{font-size:1.1em}
        table{border-collapse:collapse}th,td{border:1px solid color-mix(in srgb,currentColor 22%,transparent);
        padding:4px 10px;text-align:left}th{font-weight:600;background:color-mix(in srgb,currentColor 7%,transparent)}</style>
        </head><body><div id="m"></div></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://localhost/"))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            webView.evaluateJavaScript("typeof katex !== 'undefined'") { [weak self] value, _ in
                guard let self else { return }
                if value as? Bool == true {
                    self.pageReady = true
                    self.pump()
                } else {
                    self.pageFailed()
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.pageFailed() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in self.pageFailed() }
    }

    /// Nothing to typeset with: the formulas stay as source, and the page is
    /// tried again on a later request.
    private func pageFailed() {
        web = nil
        pageReady = false
        pageFailedAt = Date()
        rendering = false
        queued.removeAll()
        queue.removeAll()
    }

    private static func hex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#ffffff" }
        func byte(_ value: CGFloat) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    // MARK: - Embeds

    /// An embedded image from the vault or the web, loaded off the main
    /// thread the first time it is asked for.
    func image(embed url: URL) -> NSImage? {
        if let image = embeds[url] { return image }
        guard !failedEmbeds.contains(url), !loadingEmbeds.contains(url) else { return nil }
        loadingEmbeds.insert(url)
        Task.detached(priority: .utility) {
            let data = await Self.loadData(from: url)
            await MainActor.run {
                let renderer = ScratchpadMathRenderer.shared
                renderer.loadingEmbeds.remove(url)
                if let data, let image = NSImage(data: data), image.size.width > 0 {
                    renderer.embeds[url] = image
                    NotificationCenter.default.post(name: Self.didRender, object: renderer)
                } else {
                    renderer.failedEmbeds.insert(url)
                }
            }
        }
        return nil
    }

    /// Off the main thread: a vault file or a web image's bytes.
    private nonisolated static func loadData(from url: URL) async -> Data? {
        if url.isFileURL { return try? Data(contentsOf: url) }
        return try? await URLSession.shared.data(from: url).0
    }
}
