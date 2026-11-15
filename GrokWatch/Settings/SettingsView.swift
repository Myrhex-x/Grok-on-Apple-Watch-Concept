//
//  SettingsView.swift
//  GrokWatch
//

import SwiftUI

struct SettingsView: View {
    @Environment(ChatModel.self) private var chat
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        ScrollViewReader { proxy in
        List {
            Section {
                Picker("Model", selection: $preferences.model) {
                    ForEach(preferences.modelChoices, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                Picker("Thinking", selection: $preferences.reasoning) {
                    ForEach(Reasoning.allCases) { reasoning in
                        Text(reasoning.title).tag(reasoning)
                    }
                }
            } header: {
                Text("Grok")
            } footer: {
                Text("With no thinking, the answer comes fastest.")
            }

            Section {
                Toggle("Web", isOn: $preferences.webSearch)
                Toggle("X", isOn: $preferences.xSearch)
            } header: {
                Text("Search")
            } footer: {
                Text("Grok only searches when the question needs it. An X search costs about $0.10.")
            }
            .tint(.green)

            Section {
                Picker("Spoken language", selection: $preferences.speechLanguage) {
                    ForEach(SpeechLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Toggle("Listen on open", isOn: $preferences.dictateOnOpen)
                    .tint(.green)
            } header: {
                Text("Microphone")
            } footer: {
                Text("The microphone stops when you stop talking. SpaceXSI turns the audio into text, for about $0.10 per hour of audio.")
            }

            Section("SpaceXSI account") {
                NavigationLink(value: Page.key) {
                    LabeledContent("Key", value: chat.keyHint ?? String(localized: "None"))
                }
                LabeledContent("This month", value: Spending.formatted(Spending.total()))
            }

            Section {
                if let install = chat.install {
                    LabeledContent("Until", value: ProvisioningProfile.dayText(install.expiry))
                } else {
                    Text("Test build, no end date.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Installation")
            } footer: {
                if chat.install != nil {
                    Text("To extend it, connect the iPhone to the Mac and install again. A reminder comes a week before.")
                }
            }
            .id("installation")
        }
        #if DEBUG
        .onAppear {
            if DebugHooks.page == "settings-bottom" { proxy.scrollTo("installation", anchor: .bottom) }
        }
        #endif
        }
        .navigationTitle("Settings")
        .task { await chat.refreshModels() }
    }
}
