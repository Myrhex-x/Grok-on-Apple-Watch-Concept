//
//  ListeningView.swift
//  GrokWatch
//
//  While the question is being said: the microphone with a ring that follows the voice, then the
//  typing dots while SpaceXSI turns it into text.
//

import SwiftUI

struct ListeningView: View {
    @Environment(ChatModel.self) private var chat

    var body: some View {
        let level = chat.recorder.level
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 66 + 44 * level, height: 66 + 44 * level)
                    .animation(.easeOut(duration: 0.1), value: level)
                Circle()
                    .fill(.white)
                    .frame(width: 66, height: 66)
                Image(systemName: "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(height: 112)
            if chat.voice == .transcribing {
                TypingIndicator(label: String(localized: "Transcribing"))
            } else {
                Text("I’m listening")
                    .font(.headline)
            }
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                Button(action: chat.cancelListening) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(DiscButtonStyle(diameter: 46, prominent: false))
                .accessibilityLabel("Cancel")
                if chat.voice == .listening {
                    Button(action: chat.stopListening) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(DiscButtonStyle(diameter: 46))
                    .accessibilityLabel("Send")
                }
            }
            .padding(.bottom, 4)
        }
    }
}
