//
//  ChatView.swift
//  GrokWatch
//
//  The one screen: the conversation, with the microphone and the keyboard one tap away.
//

import SwiftUI

enum Page: Hashable {
    case settings
    case key
}

struct ChatView: View {
    @Environment(ChatModel.self) private var chat
    @Environment(Preferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Page] = []
    /// True until the app has been on screen once, and again each time it goes to the background.
    @State private var comingBack = true

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Grok")
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .settings: SettingsView()
                    case .key: KeySetupView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Page.settings) {
                            Image(systemName: "gearshape.fill")
                        }
                        .accessibilityLabel("Settings")
                    }
                    if chat.hasKey && !chat.messages.isEmpty {
                        ToolbarItemGroup(placement: .bottomBar) {
                            KeyboardButton()
                            MicButton()
                                .controlSize(.large)
                                .tint(.white)
                                .buttonStyle(.borderedProminent)
                                .foregroundStyle(.black)
                            Button(action: chat.newConversation) {
                                Image(systemName: "plus")
                            }
                            .disabled(chat.isBusy)
                            .accessibilityLabel("New conversation")
                        }
                    }
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            handle(phase)
        }
        #if DEBUG
        .onAppear {
            switch DebugHooks.page {
            case "settings": path = [.settings]
            case "key": path = [.settings, .key]
            default: break
            }
        }
        #endif
    }

    @ViewBuilder private var content: some View {
        if !chat.hasKey {
            KeyPromptView()
        } else if chat.messages.isEmpty {
            EmptyStateView()
        } else {
            ConversationView()
        }
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            chat.becameActive()
            if comingBack {
                comingBack = false
                chat.reopened()
                dictateIfWanted()
            }
        case .background:
            comingBack = true
        default:
            break
        }
    }

    /// Opening the app for a new question starts listening right away.
    private func dictateIfWanted() {
        guard preferences.dictateOnOpen, chat.hasKey, chat.messages.isEmpty, !chat.isBusy, path.isEmpty else { return }
        #if DEBUG
        if DebugHooks.noAutoDictation { return }
        #endif
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard chat.messages.isEmpty, path.isEmpty, scenePhase == .active else { return }
            Dictation.start(chat.ask)
        }
    }
}

/// The questions and answers, newest at the bottom.
private struct ConversationView: View {
    @Environment(ChatModel.self) private var chat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let notice = chat.expiryNotice {
                        NoticeCard(text: notice)
                    }
                    ForEach(chat.messages) { message in
                        MessageRow(message: message,
                                   activity: message.state == .streaming ? chat.activity : nil,
                                   onRetry: { chat.retry(message) })
                            .id(message.id)
                    }
                }
                // Room to scroll the last line clear of the buttons at the bottom.
                .padding(.bottom, 52)
            }
            .onAppear {
                // Back on screen: show the last question with the start of its answer.
                if let last = chat.messages.last(where: { $0.role == .user }) {
                    proxy.scrollTo(last.id, anchor: .top)
                }
            }
            .onChange(of: chat.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }
}
