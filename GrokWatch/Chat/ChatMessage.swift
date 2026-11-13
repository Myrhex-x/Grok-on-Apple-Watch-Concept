//
//  ChatMessage.swift
//  GrokWatch
//
//  One conversation on the wrist: the questions, Grok's answers, and what each answer cost.
//

import Foundation

nonisolated struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, grok }
    enum State: String, Codable, Sendable {
        case complete
        case streaming
        case failed
        /// Stopped before the end (by the user, or the app was closed mid-answer).
        case interrupted
    }

    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    var state: State = .complete
    /// The sites a searching answer drew on, as host names.
    var sources: [String] = []
    var costUSD: Double?
    var errorText: String?
}

nonisolated struct Conversation: Codable, Equatable, Sendable {
    var id = UUID()
    var messages: [ChatMessage] = []
    var updatedAt = Date()

    /// What goes to Grok with a question: the turns up to it, failed answers left out, newest last.
    func turns(through questionID: UUID, limit: Int) -> [GrokTurn] {
        guard let end = messages.firstIndex(where: { $0.id == questionID }) else { return [] }
        let turns: [GrokTurn] = messages[...end].compactMap { message in
            switch message.role {
            case .user:
                return GrokTurn(role: .user, text: message.text)
            case .grok:
                guard message.state == .complete || message.state == .interrupted, !message.text.isEmpty else { return nil }
                return GrokTurn(role: .assistant, text: AnswerText.clean(message.text))
            }
        }
        return Array(turns.suffix(limit))
    }

    /// An answer still marked as being written when the app stopped will never finish.
    mutating func settleUnfinished() {
        for index in messages.indices where messages[index].state == .streaming {
            messages[index].state = messages[index].text.isEmpty ? .failed : .interrupted
            if messages[index].text.isEmpty {
                messages[index].errorText = "The answer didn’t come through."
            }
        }
    }
}
