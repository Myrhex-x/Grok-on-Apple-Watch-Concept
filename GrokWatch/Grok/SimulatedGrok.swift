//
//  SimulatedGrok.swift
//  GrokWatch
//
//  Debug builds only: a pretend Grok for the simulator (`-GrokWatchSimulated YES`). Nothing is
//  sent anywhere and nothing is billed.
//

#if DEBUG
import Foundation

extension GrokClient {
    nonisolated static let simulatedKey = "simulated"

    nonisolated static let simulatedModels: [GrokModelInfo] = {
        var cheap = GrokModelInfo(id: "grok-4.3")
        cheap.inputPerMillion = 1.25
        cheap.outputPerMillion = 2.5
        cheap.reasoningEfforts = ["none", "low", "medium", "high", "xhigh"]
        var big = GrokModelInfo(id: "grok-4.7")
        big.inputPerMillion = 3
        big.outputPerMillion = 15
        big.reasoningEfforts = ["low", "medium", "high"]
        return [cheap, big, GrokModelInfo(id: "grok-imagine-image")]
    }()

    nonisolated func simulatedStream(_ request: GrokRequest) -> AsyncThrowingStream<GrokStreamEvent, Error> {
        let question = request.input.last?.text.lowercased() ?? ""
        let searches = request.tools.contains(.webSearch) && (question.contains("weather") || question.contains("news"))
        let answer: String
        var citations: [URL] = []
        if question.contains("2+2") || question.contains("2 + 2") {
            answer = "4."
        } else if searches {
            answer = "In Paris, 11\u{00A0}°C and cloudy this afternoon. Showers are possible this evening."
            citations = [URL(string: "https://meteofrance.com/previsions-meteo-france/paris/75000")!]
        } else {
            answer = "Simulated answer to “\(request.input.last?.text ?? "")”. Nothing was sent to SpaceXSI, and **nothing was billed**."
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.activity(.thinking))
                    try await Task.sleep(for: .milliseconds(700))
                    if searches {
                        continuation.yield(.activity(.searchingWeb))
                        try await Task.sleep(for: .milliseconds(1200))
                    }
                    var words = answer.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                    if !words.isEmpty { words = [words[0]] + words.dropFirst().map { " " + $0 } }
                    for word in words {
                        try await Task.sleep(for: .milliseconds(45))
                        continuation.yield(.textDelta(word))
                    }
                    continuation.yield(.completed(GrokResult(text: answer, citations: citations,
                                                             usage: GrokUsage(inputTokens: 300, outputTokens: 40, costUSD: 0.0005),
                                                             model: request.model)))
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
