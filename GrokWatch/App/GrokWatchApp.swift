//
//  GrokWatchApp.swift
//  GrokWatch
//
//  Grok on the wrist, with the user's own SpaceXSI key: ask by voice or keyboard, read the
//  answer. Nothing is spoken aloud.
//

import SwiftUI
import WatchKit

@main
struct GrokWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences: Preferences
    @State private var chat: ChatModel

    init() {
        let preferences = Preferences()
        _preferences = State(initialValue: preferences)
        _chat = State(initialValue: ChatModel(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(chat)
                .environment(preferences)
        }
    }
}
