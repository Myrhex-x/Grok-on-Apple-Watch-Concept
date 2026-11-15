//
//  ModelChoice.swift
//  GrokWatch
//
//  Which model to ask and how hard it should think. The app is meant to run for months without an
//  update while SpaceXSI retires models, so a model that disappears is replaced, not fatal.
//

import Foundation

nonisolated enum ModelChoice {
    /// The cheap tier with a 1M context (SpaceXSI retired the "fast" models on 2026-05-15).
    static let preferred = "grok-4.3"

    /// Models that answer in text (the list also carries image and video models), cheapest first.
    static func chatModels(_ models: [GrokModelInfo]) -> [GrokModelInfo] {
        let excluded = ["imag", "video", "embed", "tts", "voice", "audio", "realtime", "transcri", "vision"]
        return models
            .filter { model in !excluded.contains { model.id.lowercased().contains($0) } }
            .sorted { ($0.inputPerMillion ?? .infinity, $0.id) < ($1.inputPerMillion ?? .infinity, $1.id) }
    }

    /// What to use when `current` is gone: the preferred model when it is listed, else the cheapest.
    static func replacement(for current: String, in models: [GrokModelInfo]) -> String? {
        let candidates = chatModels(models).filter { $0.id != current && !$0.aliases.contains(current) }
        if let preferred = candidates.first(where: { $0.id == Self.preferred || $0.aliases.contains(Self.preferred) }) {
            return preferred.id
        }
        return candidates.first?.id
    }

    /// The effort to send: the one wanted when the model takes it, else the nearest above it
    /// (grok-4.7, for one, starts at "low").
    static func effort(wanted: String, supported: [String]?) -> String {
        guard let supported, !supported.isEmpty, !supported.contains(wanted) else { return wanted }
        let order = ["none", "minimal", "low", "medium", "high", "xhigh"]
        func rank(_ effort: String) -> Int { order.firstIndex(of: effort) ?? order.count }
        let sorted = supported.sorted { rank($0) < rank($1) }
        return sorted.first { rank($0) >= rank(wanted) } ?? sorted.last ?? wanted
    }
}
