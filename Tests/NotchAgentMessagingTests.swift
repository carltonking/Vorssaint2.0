// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The agents' pages work as Messages does: a reply names the message it
/// answers and comes back as that reply when the thread is read again, files
/// travel with a message, and a notification says something even when a
/// message has no words.
enum NotchAgentMessagingTests {
    static func run(_ suite: TestSuite) {
        typealias Support = NotchAgentReplySupport
        typealias Message = NotchHermesChatMessage

        suite.run("agent replies carry their quote and come back as replies") {
            let original = Message(role: .hermes, text: "Your flight leaves at 9:40 tomorrow.\nGate B12.")
            let sent = Support.outgoing("Can you move it?", quoting: original.text)
            suite.expect(sent == "> Your flight leaves at 9:40 tomorrow.\nCan you move it?", "only the first line is quoted")
            suite.expect(Support.outgoing("hi", quoting: nil) == "hi", "a plain message has no quote")
            let long = String(repeating: "a", count: 200)
            suite.expect(Support.quoteLine(for: long).count == Support.quoteLimit + 2, "a long line is cut short")

            let readBack = Message(role: .person, text: sent)
            let resolved = Support.resolvingReply(readBack, among: [original])
            suite.expect(resolved.text == "Can you move it?" && resolved.replyTo == original.id,
                         "the quote becomes the reply it was")
            let cut = Message(role: .person, text: Support.outgoing("ok", quoting: long))
            let longOriginal = Message(role: .hermes, text: long)
            suite.expect(Support.resolvingReply(cut, among: [longOriginal]).replyTo == longOriginal.id,
                         "a shortened quote still finds its message")
            let stray = Message(role: .person, text: "> something nobody said\nhm")
            suite.expect(Support.resolvingReply(stray, among: [original]) == stray, "an unmatched quote stays as typed")
            let theirs = Message(role: .hermes, text: sent)
            suite.expect(Support.resolvingReply(theirs, among: [original]) == theirs, "only your own messages are read back")
            let thread = Support.resolvingReplies([original, readBack])
            suite.expect(thread.last?.replyTo == original.id, "a whole thread is read back in order")
        }

        suite.run("agent attachments travel with a message") {
            let files = [URL(fileURLWithPath: "/tmp/a b.png"), URL(fileURLWithPath: "/tmp/notes.pdf")]
            suite.expect(Support.prompt("look", attachments: files) == "look\n\nAttached files:\n- /tmp/a b.png\n- /tmp/notes.pdf",
                         "an agent on this Mac gets the paths")
            suite.expect(Support.prompt("look", attachments: []) == "look", "no files, no list")
            suite.expect(Support.attachments(files)?.map(\.isImage) == [true, false], "pictures are told from files")

            let line = #"{"id": 7, "guid": "G7", "is_from_me": false, "text": "\#u{FFFC}", "sender": "+15550001111", "#
                + #""created_at": "2026-10-27T10:00:00Z", "attachments": [{"original_path": "~/Library/Messages/Attachments/x/IMG_1.HEIC", "#
                + #""transfer_name": "IMG_1.HEIC", "is_sticker": false, "missing": false}, {"filename": "s.png", "is_sticker": true}]}"#
            let record = InstinctMessagesSupport.record(fromLine: line)
            suite.expect(record?.attachments.count == 1 && record?.attachments.first?.name == "IMG_1.HEIC",
                         "a photo with no words is a message, stickers left out")
            suite.expect(record?.attachments.first?.path.hasPrefix("/") == true, "its path is expanded")
            suite.expect(InstinctMessagesSupport.historyArguments(chatID: 3).contains("--attachments")
                         && InstinctMessagesSupport.watchArguments(chatID: 3, number: "x", after: nil).contains("--attachments"),
                         "imsg is asked for files")
            suite.expect(InstinctMessagesSupport.sendArguments(number: " +1555 ", file: files[1])
                         == ["send", "--to", "+1555", "--file", "/tmp/notes.pdf"], "a file is sent on its own")
        }

        suite.run("agent notifications always have a body") {
            let words = Message(role: .hermes, text: "  Done.  ")
            suite.expect(Support.notificationBody(words, image: "Image", file: "Attachment") == "Done.", "the words")
            let photo = Message(role: .hermes, text: "", attachments: [.init(path: "/x/p.jpg", name: "p.jpg")])
            suite.expect(Support.notificationBody(photo, image: "Image", file: "Attachment") == "Image", "a picture")
            let pdf = Message(role: .hermes, text: "", attachments: [.init(path: "/x/r.pdf", name: "r.pdf")])
            suite.expect(Support.notificationBody(pdf, image: "Image", file: "Attachment") == "Attachment: r.pdf", "a file")
        }
    }
}
