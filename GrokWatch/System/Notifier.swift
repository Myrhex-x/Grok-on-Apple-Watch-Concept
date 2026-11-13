//
//  Notifier.swift
//  GrokWatch
//
//  An answer that lands after the wrist went down arrives as a notification: the watch taps, and
//  the answer is there when the wrist comes up. Raising the wrist into the app clears it again.
//

import Foundation
import UserNotifications

nonisolated enum Notifier {
    private static let answerPrefix = "answer-"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func postAnswer(_ answer: ChatMessage, question: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Grok"
        if let question, !question.isEmpty {
            content.subtitle = question.count > 60 ? String(question.prefix(58)) + "…" : question
        }
        if answer.state == .failed {
            content.body = answer.errorText ?? "The answer didn’t come through."
        } else {
            let text = AnswerText.plain(answer.text)
            content.body = text.count > 1_500 ? String(text.prefix(1_498)) + "…" : text
        }
        content.sound = .default
        content.threadIdentifier = "answers"
        let request = UNNotificationRequest(identifier: answerPrefix + answer.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func clearDeliveredAnswers() {
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(answerPrefix) }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }
}
