//
//  ConversationStore.swift
//  GrokWatch
//
//  The current conversation and the one before it, as JSON in the app's own container, so a
//  wrist that goes down or an app that gets closed loses nothing.
//

import Foundation

nonisolated enum ConversationStore {
    enum Slot: String, Sendable {
        case current = "conversation"
        case previous = "previous-conversation"
    }

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func url(_ slot: Slot) -> URL {
        folder.appendingPathComponent(slot.rawValue).appendingPathExtension("json")
    }

    static func load(_ slot: Slot) -> Conversation? {
        guard let data = try? Data(contentsOf: url(slot)) else { return nil }
        return try? JSONDecoder().decode(Conversation.self, from: data)
    }

    static func save(_ conversation: Conversation?, as slot: Slot) {
        let target = url(slot)
        guard let conversation, !conversation.messages.isEmpty else {
            try? FileManager.default.removeItem(at: target)
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(conversation)
            try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Nothing to tell the user: the conversation is still on screen.
        }
    }
}
