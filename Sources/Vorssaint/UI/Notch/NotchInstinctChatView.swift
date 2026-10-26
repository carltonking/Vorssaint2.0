// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Instinct settings: the switch, Instinct's number, the page's shortcut,
/// and where the thread stands. The page itself is `NotchHermesChatView`
/// carrying `NotchHermesChatService.instinct`.
struct NotchInstinctChatSettingsControls: View {
    @ObservedObject private var chat = NotchHermesChatService.instinct
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchInstinctChatEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchInstinctNumber) private var number = ""
    @AppStorage(DefaultsKey.notchInstinctShortcutEnabled) private var shortcutEnabled = true
    /// The number the open thread was found by. Opening this page is not a
    /// reason to read the thread again; editing the number is.
    @State private var appliedNumber: String?
    private var words: NotchInstinctChatStrings { FeatureStrings.notchInstinctChat(l10n.language) }
    private var text: NotchHermesChatStrings { chat.strings(l10n.language) }
    private static let editSettleDelay = Duration.milliseconds(700)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(words.enable, isOn: $enabled)
                .disabled(!AppFeature.notchInstinctChat.isAvailable)
            Text(words.description).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                SettingsRow(symbol: "phone", title: words.number) {
                    TextField(words.numberPlaceholder, text: $number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                Text(words.numberHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(L10n.shared.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in chat.syncShortcut() }
                ShortcutPreferenceRow(role: .instinctChat, isEnabled: shortcutEnabled) { chat.syncShortcut() }
                if shortcutEnabled, chat.shortcutRegistrationFailed {
                    Text(L10n.shared.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
                }
                status
            }
        }
        .onAppear {
            if appliedNumber == nil { appliedNumber = number }
        }
        .onChange(of: enabled) { _, _ in
            appliedNumber = number
            chat.syncWithPreferences()
        }
        // One new read for a typed number, once it stops changing, rather
        // than one per keystroke.
        .task(id: number) {
            guard enabled, number != appliedNumber else { return }
            try? await Task.sleep(for: Self.editSettleDelay)
            guard !Task.isCancelled, number != appliedNumber else { return }
            appliedNumber = number
            chat.retry()
        }
    }

    @ViewBuilder private var status: some View {
        switch chat.state {
        case .off:
            EmptyView()
        case .connecting:
            Label(text.connecting, systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        case .ready:
            Label(text.ready, systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 6) {
                Label(chat.describe(failure, language: l10n.language), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if failure == .needsFullDiskAccess {
                        Button(words.openFullDiskAccess) { Permissions.shared.requestFullDiskAccess() }
                            .controlSize(.small)
                    }
                    Button(text.retry) { chat.retry() }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// A link an agent sent, as a card under its message: the page's image,
/// title and site once LinkPresentation has them, a plain link row until
/// then or when the page gives nothing. A click opens it in the default
/// browser.
struct NotchLinkPreviewCard: View {
    let url: URL
    let openTitle: String
    @ObservedObject private var previews = NotchLinkPreviewService.shared
    @State private var hovered = false

    private static let width: CGFloat = 250
    private static let imageHeight: CGFloat = 96

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            content
                .frame(maxWidth: Self.width, alignment: .leading)
                .background(Color.white.opacity(hovered ? 0.13 : 0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
        .accessibilityLabel("\(openTitle): \(preview?.title ?? url.absoluteString)")
        .onHover { hovered = $0 }
        // Asked for once the card is on screen, never while it draws.
        .task(id: url) { previews.load(url) }
    }

    private var preview: NotchLinkPreviewService.Preview? {
        if case .loaded(let preview) = previews.entries[url] { return preview }
        return nil
    }

    @ViewBuilder private var content: some View {
        if let preview, preview.title != nil || preview.image != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let image = preview.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Self.width, height: Self.imageHeight)
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let title = preview.title {
                        Text(title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                    Text(preview.site)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        } else {
            plainRow
        }
    }

    private var plainRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .medium))
            Text(url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? url.absoluteString)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
            if case .loading = previews.entries[url] {
                ProgressView().controlSize(.mini)
            }
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
