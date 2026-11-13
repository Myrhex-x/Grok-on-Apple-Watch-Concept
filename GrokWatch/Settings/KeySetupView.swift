//
//  KeySetupView.swift
//  GrokWatch
//
//  Pasting the key: when the watch asks for text, the iPhone offers to type it instead, and its
//  keyboard can paste. The key is checked against SpaceXAI (listing models is free) before it is
//  kept.
//

import SwiftUI

struct KeySetupView: View {
    @Environment(ChatModel.self) private var chat
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var step = Step.idle

    private enum Step: Equatable {
        case idle
        case checking
        case saved(String)
        case failed(String)
    }

    var body: some View {
        List {
            Section {
                SecureField("Paste key", text: $draft)
                    .textContentType(.password)
                    .onSubmit { Task { await save() } }
                    .disabled(step == .checking)
            } header: {
                Text("SpaceXAI API key")
            } footer: {
                Text("When the text field opens, the iPhone offers to type for the watch: paste the key there. It starts with xai-.")
            }

            switch step {
            case .idle:
                EmptyView()
            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .frame(width: 20, height: 20)
                    Text("Checking…")
                        .foregroundStyle(.secondary)
                }
            case .saved(let message):
                Label(message, systemImage: "checkmark.circle.fill")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
            }

            if chat.hasKey {
                Section {
                    LabeledContent("Saved", value: chat.keyHint ?? "")
                    Button("Delete key", role: .destructive) {
                        GrokKeyStore.delete()
                        chat.keyChanged()
                        step = .idle
                    }
                } footer: {
                    Text("The key stays in the watch’s Keychain. It isn’t backed up anywhere, and it’s only ever sent to api.x.ai.")
                }
            }
        }
        .navigationTitle("Key")
    }

    private func save() async {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        step = .checking
        do {
            let models = try await GrokClient(apiKey: key).listModels()
            guard GrokKeyStore.save(key) else {
                step = .failed("The watch couldn’t save the key.")
                return
            }
            preferences.adopt(models)
            await finish("Key checked and saved.")
        } catch GrokError.invalidKey {
            step = .failed(GrokError.invalidKey.localizedDescription)
        } catch {
            // Offline, or a key allowed to answer but not to list models: keep it, the first
            // question will tell. Only a key SpaceXAI rejects outright is refused.
            guard GrokKeyStore.save(key) else {
                step = .failed("The watch couldn’t save the key.")
                return
            }
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await finish("Key saved without checking it: \(reason)")
        }
    }

    private func finish(_ message: String) async {
        draft = ""
        chat.keyChanged()
        step = .saved(message)
        // Answers that land with the wrist down, and the reminder before the install ends.
        await Notifier.requestAuthorizationIfNeeded()
        await InstallExpiry.refreshReminders()
        try? await Task.sleep(for: .seconds(1.2))
        dismiss()
    }
}
