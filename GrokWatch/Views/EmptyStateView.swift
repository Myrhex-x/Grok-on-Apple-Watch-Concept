//
//  EmptyStateView.swift
//  GrokWatch
//
//  A new conversation: one big microphone, the keyboard under it.
//

import SwiftUI

struct EmptyStateView: View {
    @Environment(ChatModel.self) private var chat

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if let notice = chat.keyImportNotice {
                        NoticeCard(text: notice, systemImage: "checkmark.circle.fill")
                    }
                    if let notice = chat.expiryNotice {
                        NoticeCard(text: notice)
                    }
                    Spacer(minLength: 0)
                    MicButton()
                        .buttonStyle(DiscButtonStyle(diameter: 72))
                    Text("Speak")
                        .font(.headline)
                    if let notice = chat.voiceNotice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    KeyboardButton(title: "Type")
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .fixedSize()
                    if chat.hasPrevious {
                        Button("Previous conversation", action: chat.restorePrevious)
                            .font(.footnote)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }
}
