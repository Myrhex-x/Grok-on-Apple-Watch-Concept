//
//  Controls.swift
//  GrokWatch
//
//  The two ways to ask: speak (one tap straight into dictation) or type (the watch keyboard,
//  Scribble, or the iPhone's keyboard).
//

import SwiftUI

/// Speak a question, or stop the answer being written.
struct MicButton: View {
    @Environment(ChatModel.self) private var chat

    var body: some View {
        if chat.isBusy {
            Button(action: chat.stop) {
                Image(systemName: "stop.fill")
            }
            .accessibilityLabel("Stop the answer")
        } else if Dictation.isAvailable {
            Button {
                Dictation.start(chat.ask)
            } label: {
                Image(systemName: "mic.fill")
            }
            .disabled(!chat.hasKey)
            .accessibilityLabel("Dictate a question")
        } else {
            TextFieldLink(prompt: Text("Your question")) {
                Image(systemName: "mic.fill")
            } onSubmit: { text in
                chat.ask(text)
            }
            .disabled(!chat.hasKey)
            .accessibilityLabel("Dictate a question")
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

/// White disc, black glyph: the app's one loud control.
struct WhiteDiscButtonStyle: ButtonStyle {
    var diameter: CGFloat = 70

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.38, weight: .semibold))
            .foregroundStyle(.black)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(.white))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
