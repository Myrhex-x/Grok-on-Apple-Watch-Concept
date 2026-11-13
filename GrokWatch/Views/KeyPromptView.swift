//
//  KeyPromptView.swift
//  GrokWatch
//
//  First launch: the app needs the user's SpaceXAI key before anything else.
//

import SwiftUI

struct KeyPromptView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your SpaceXAI key")
                    .font(.headline)
                Text("Grok answers with your own API key. It stays on the watch and is only used to reach api.x.ai.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink(value: Page.key) {
                    Label("Add key", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
    }
}
