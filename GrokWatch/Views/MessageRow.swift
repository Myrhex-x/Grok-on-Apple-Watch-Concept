//
//  MessageRow.swift
//  GrokWatch
//
//  A question sits in a bubble on the right; Grok's answer is plain text across the screen, the way
//  grok.com shows it.
//

import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    /// What Grok is doing, for the answer being written.
    let activity: GrokActivity?
    let onRetry: () -> Void

    var body: some View {
        switch message.role {
        case .user: question
        case .grok: answer
        }
    }

    private var question: some View {
        HStack {
            Spacer(minLength: 22)
            Text(message.text)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .accessibilityLabel("You: \(message.text)")
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.text.isEmpty && message.state == .streaming {
                TypingIndicator(label: activity?.title)
            } else if !message.text.isEmpty {
                Text(AnswerText.attributed(message.text))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if message.state == .streaming, !message.text.isEmpty, let activity {
                Text(activity.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !message.sources.isEmpty {
                Text("Sources: " + message.sources.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if message.state == .interrupted {
                Text("Answer interrupted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if message.state == .failed {
                Label {
                    Text(message.errorText ?? "The answer didn’t come through.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote)
                Button("Try again", action: onRetry)
            }
        }
    }
}

/// Three dots while Grok writes, like the app's icon.
struct TypingIndicator: View {
    var label: String?

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1 / 12)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .frame(width: 6, height: 6)
                            .opacity(0.3 + 0.7 * Self.pulse(time, index))
                    }
                }
            }
            if let label {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Grok is writing")
    }

    private static func pulse(_ time: TimeInterval, _ index: Int) -> Double {
        let phase = (time * 1.6 - Double(index) * 0.22).truncatingRemainder(dividingBy: 1)
        let wave = phase < 0 ? phase + 1 : phase
        return wave < 0.5 ? wave * 2 : (1 - wave) * 2
    }
}

/// A short line about the app itself (the key arrived, the install ends soon).
struct NoticeCard: View {
    let text: String
    var systemImage = "clock.badge.exclamationmark"

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
