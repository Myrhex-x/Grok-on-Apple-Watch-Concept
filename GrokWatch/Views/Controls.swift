//
//  Controls.swift
//  GrokWatch
//
//  The two ways to ask: speak (one tap and the watch is recording) or type (the watch keyboard,
//  Scribble, or the iPhone's keyboard).
//

import SwiftUI

/// Speak a question (recording starts on the tap), or stop the answer being written.
struct MicButton: View {
    @Environment(ChatModel.self) private var chat

    var body: some View {
        if chat.isBusy {
            Button(action: chat.stop) {
                Image(systemName: "stop.fill")
            }
            .accessibilityLabel("Stop the answer")
        } else {
            Button(action: chat.listen) {
                Image(systemName: "mic.fill")
            }
            .disabled(!chat.hasKey)
            .accessibilityLabel("Ask a question out loud")
        }
    }
}

/// Type a question.
struct KeyboardButton: View {
    @Environment(ChatModel.self) private var chat
    var title: String?

    var body: some View {
        TextFieldLink(prompt: Text("Your question")) {
            if let title {
                Label(title, systemImage: "keyboard")
            } else {
                Image(systemName: "keyboard")
            }
        } onSubmit: { text in
            chat.ask(text)
        }
        .disabled(chat.isBusy || !chat.hasKey)
        .accessibilityLabel("Type a question")
    }
}

/// A round button: white with a black glyph for the main action, a soft grey disc for the others.
struct DiscButtonStyle: ButtonStyle {
    var diameter: CGFloat = 70
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.38, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(prominent ? Color.white : Color.white.opacity(0.18)))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
