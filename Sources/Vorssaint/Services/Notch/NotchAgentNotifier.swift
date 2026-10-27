// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os.log
import UserNotifications

/// An agent's message as a notification, the way Messages posts one: the
/// agent's name as the title, its words as the body, its mark on the
/// banner, and one thread per agent in Notification Center. Clicking it opens
/// the island on that agent's page. It replaces the island opening by itself
/// whenever an agent wrote.
enum NotchAgentNotifier {
    /// Which agent a notification came from, to open its page on a click.
    static let agentKey = "com.vorssaint.notification.agent"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "agent-notifications")

    static func post(agent: NotchHermesChatService.Agent, title: String, body: String) {
        let words = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                deliver(agent: agent, title: title, body: words, in: center)
            case .notDetermined:
                // The first message asks once; it is shown if allowed.
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { deliver(agent: agent, title: title, body: words, in: center) }
                }
            default:
                log.notice("agent notification dropped: notifications are off for the app")
            }
        }
    }

    private static func deliver(agent: NotchHermesChatService.Agent, title: String, body: String,
                                in center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = identifier(agent)
        content.userInfo = [agentKey: identifier(agent)]
        if let avatar = avatarCopy(agent),
           let attachment = try? UNNotificationAttachment(identifier: "avatar", url: avatar, options: nil) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                log.error("agent notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func identifier(_ agent: NotchHermesChatService.Agent) -> String {
        agent == .vertus ? "vertus" : "instinct"
    }

    static func agent(from response: UNNotificationResponse) -> NotchHermesChatService.Agent? {
        switch response.notification.request.content.userInfo[agentKey] as? String {
        case "vertus": return .vertus
        case "instinct": return .instinct
        default: return nil
        }
    }

    static func isAgentNotification(_ notification: UNNotification) -> Bool {
        notification.request.content.userInfo[agentKey] != nil
    }

    /// The system moves an attachment's file into its own store, so each
    /// notification gets a fresh copy of the bundled mark.
    private static func avatarCopy(_ agent: NotchHermesChatService.Agent) -> URL? {
        let name = agent == .vertus ? "vertus-avatar" : "instinct-avatar"
        guard let source = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Images")
        else { return nil }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).png")
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        } catch {
            return nil
        }
    }
}
