//
//  Preferences.swift
//  GrokWatch
//
//  The few choices the app keeps. Each one is written the moment it changes.
//

import Foundation
import Observation

/// How long Grok thinks before answering. Longer is slower and costs more.
nonisolated enum Reasoning: String, CaseIterable, Identifiable, Sendable {
    case none, low, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .low: "Short"
        case .high: "Deep"
        }
    }
}

/// The language the questions are spoken in, for SpaceXAI's transcription.
nonisolated enum SpeechLanguage: String, CaseIterable, Identifiable, Sendable {
    case french = "fr"
    case english = "en"
    case automatic = "auto"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .french: "French"
        case .english: "English"
        case .automatic: "Automatic"
        }
    }

    /// What the transcription takes (nil: SpaceXAI detects the language).
    var code: String? { self == .automatic ? nil : rawValue }
}

@Observable
final class Preferences {
    private enum Keys {
        static let model = "model"
        static let reasoning = "reasoning"
        static let webSearch = "webSearch"
        static let xSearch = "xSearch"
        static let dictateOnOpen = "dictateOnOpen"
        static let speechLanguage = "speechLanguage"
        static let models = "models"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }
    var reasoning: Reasoning {
        didSet { defaults.set(reasoning.rawValue, forKey: Keys.reasoning) }
    }
    /// Grok may look things up on the web when a question needs it (about 0.005 USD a search).
    var webSearch: Bool {
        didSet { defaults.set(webSearch, forKey: Keys.webSearch) }
    }
    /// Grok may search X too (about 0.10 USD a search, so off unless chosen).
    var xSearch: Bool {
        didSet { defaults.set(xSearch, forKey: Keys.xSearch) }
    }
    /// Opening the app for a new question starts the microphone.
    var dictateOnOpen: Bool {
        didSet { defaults.set(dictateOnOpen, forKey: Keys.dictateOnOpen) }
    }
    var speechLanguage: SpeechLanguage {
        didSet { defaults.set(speechLanguage.rawValue, forKey: Keys.speechLanguage) }
    }
    /// The models the key can use, as SpaceXAI listed them last.
    var models: [GrokModelInfo] {
        didSet { defaults.set(try? JSONEncoder().encode(models), forKey: Keys.models) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        model = defaults.string(forKey: Keys.model) ?? ModelChoice.preferred
        reasoning = defaults.string(forKey: Keys.reasoning).flatMap(Reasoning.init(rawValue:)) ?? .none
        webSearch = defaults.object(forKey: Keys.webSearch) as? Bool ?? true
        xSearch = defaults.object(forKey: Keys.xSearch) as? Bool ?? false
        dictateOnOpen = defaults.object(forKey: Keys.dictateOnOpen) as? Bool ?? true
        speechLanguage = defaults.string(forKey: Keys.speechLanguage).flatMap(SpeechLanguage.init(rawValue:)) ?? .english
        models = defaults.data(forKey: Keys.models).flatMap { try? JSONDecoder().decode([GrokModelInfo].self, from: $0) } ?? []
    }

    var modelInfo: GrokModelInfo? {
        models.first { $0.id == model || $0.aliases.contains(model) }
    }

    /// The choices for the model picker: text models, cheapest first, the current one always in.
    var modelChoices: [String] {
        var ids = ModelChoice.chatModels(models).map(\.id)
        if !ids.contains(model) { ids.insert(model, at: 0) }
        return ids
    }

    /// Takes a fresh model list, and moves off the chosen model if the key can't use it any more.
    func adopt(_ list: [GrokModelInfo]) {
        guard !list.isEmpty else { return }
        models = list
        if modelInfo == nil, let replacement = ModelChoice.replacement(for: model, in: list) {
            model = replacement
        }
    }
}
