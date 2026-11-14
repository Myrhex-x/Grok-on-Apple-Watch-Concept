//
//  GrokClient.swift
//  GrokWatch
//
//  Talks to the SpaceXAI API (api.x.ai) straight from the watch with the user's own key. There is
//  no server in between: nobody but SpaceXAI sees the question, and the user's own account pays.
//  Responses API, streamed, with `store: false` (the watch keeps the conversation itself).
//
//  Everything that comes back is untrusted model output: it is shown as text, never run.
//

import Foundation

// MARK: - Request

nonisolated enum GrokTool: Equatable, Sendable {
    case webSearch
    case xSearch

    var json: [String: Any] {
        switch self {
        case .webSearch: ["type": "web_search"]
        case .xSearch: ["type": "x_search"]
        }
    }
}

nonisolated struct GrokTurn: Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    let text: String
}

nonisolated struct GrokRequest: Sendable {
    var model: String
    var instructions: String
    var input: [GrokTurn]
    var tools: [GrokTool] = []
    /// Caps the turns a searching answer may take, so a search can't run up the bill.
    var maxTurns: Int? = nil
    var maxOutputTokens: Int? = nil
    /// How long the model thinks first ("none", "low", "high"), for models that take it.
    var reasoningEffort: String? = nil
    /// Requests of one conversation share this key, so SpaceXAI's prompt cache finds them.
    var promptCacheKey: String? = nil

    func body(stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input.map { ["role": $0.role.rawValue, "content": $0.text] },
            "stream": stream,
            // The watch sends the history itself: nothing is kept on SpaceXAI's side.
            "store": false,
        ]
        if !tools.isEmpty { body["tools"] = tools.map(\.json) }
        if let maxTurns { body["max_turns"] = maxTurns }
        if let maxOutputTokens { body["max_output_tokens"] = maxOutputTokens }
        if let reasoningEffort { body["reasoning"] = ["effort": reasoningEffort] }
        if let promptCacheKey { body["prompt_cache_key"] = promptCacheKey }
        return body
    }
}

// MARK: - Models

nonisolated struct GrokModelInfo: Equatable, Codable, Identifiable, Sendable {
    let id: String
    var aliases: [String] = []
    /// USD per million input / output tokens. The API reports prices in 1e-10 USD per token.
    var inputPerMillion: Double?
    var outputPerMillion: Double?
    /// The reasoning efforts the model accepts, when the list says (nil: not reported).
    var reasoningEfforts: [String]?

    init(id: String) { self.id = id }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        aliases = json["aliases"] as? [String] ?? []
        inputPerMillion = Self.perMillion(json["prompt_text_token_price"])
        outputPerMillion = Self.perMillion(json["completion_text_token_price"])
        if let capabilities = json["capabilities"] as? [String: Any] {
            reasoningEfforts = capabilities["reasoning_effort"] as? [String]
        }
    }

    private static func perMillion(_ value: Any?) -> Double? {
        if let n = value as? Double { return n / 10_000 }
        if let n = value as? Int { return Double(n) / 10_000 }
        return nil
    }
}

// MARK: - Response

nonisolated struct GrokUsage: Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    /// USD, from SpaceXAI's own accounting (`cost_in_usd_ticks`, 1e10 ticks per dollar), searches included.
    var costUSD: Double?

    init(inputTokens: Int = 0, outputTokens: Int = 0, costUSD: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }

    init?(json: [String: Any]?) {
        guard let json else { return nil }
        inputTokens = (json["input_tokens"] as? Int) ?? 0
        outputTokens = (json["output_tokens"] as? Int) ?? 0
        if let ticks = json["cost_in_usd_ticks"] as? Double {
            costUSD = ticks / 1e10
        } else if let ticks = json["cost_in_usd_ticks"] as? Int {
            costUSD = Double(ticks) / 1e10
        }
    }
}

nonisolated struct GrokResult: Equatable, Sendable {
    var text: String
    var citations: [URL] = []
    var usage: GrokUsage?
    var model: String?
}

/// What Grok is doing while there are no words to show yet.
nonisolated enum GrokActivity: Equatable, Sendable {
    case thinking, searchingWeb, searchingX, searching, runningCode

    var title: String {
        switch self {
        case .thinking: String(localized: "Thinking")
        case .searchingWeb: String(localized: "Searching the web")
        case .searchingX: String(localized: "Searching X")
        case .searching: String(localized: "Searching")
        case .runningCode: String(localized: "Calculating")
        }
    }
}

nonisolated enum GrokStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case activity(GrokActivity)
    case citation(URL)
    case completed(GrokResult)
}

nonisolated enum GrokError: LocalizedError, Equatable, Sendable {
    case missingKey
    case invalidKey
    case noCredits
    case rateLimited
    case modelUnavailable(String)
    case server(Int, String)
    case offline
    case connectionLost
    case timedOut
    case network(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: String(localized: "Add your SpaceXAI key in Settings.")
        case .invalidKey: String(localized: "SpaceXAI rejects this key. Check it in Settings.")
        case .noCredits: String(localized: "SpaceXAI refused the request. Check your team’s credits on console.x.ai.")
        case .rateLimited: String(localized: "Too many requests for this key. Try again in a moment.")
        case .modelUnavailable(let model): String(localized: "The model \(model) isn’t available for this key.")
        case let .server(code, message):
            message.isEmpty ? String(localized: "SpaceXAI returned an error (\(code)).") : String(localized: "SpaceXAI error \(code): \(message)")
        case .offline: String(localized: "No connection. The watch needs Wi-Fi, cellular or the iPhone nearby.")
        case .connectionLost: String(localized: "The connection dropped before the answer was done.")
        case .timedOut: String(localized: "SpaceXAI is taking too long to answer. Try again.")
        case .network(let message): String(localized: "Can’t reach SpaceXAI: \(message)")
        case .badResponse(let message): String(localized: "Unexpected answer from SpaceXAI: \(message)")
        }
    }
}

// MARK: - Client

nonisolated struct GrokClient: Sendable {
    static let baseURL = URL(string: "https://api.x.ai/v1")!

    let apiKey: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private func request(path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// The models this key can use, with their prices. Listing them is free.
    func listModels() async throws -> [GrokModelInfo] {
        #if DEBUG
        if apiKey == Self.simulatedKey { return Self.simulatedModels }
        #endif
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: try request(path: "models"))
        } catch {
            throw Self.networkError(error)
        }
        try Self.check(response, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            throw GrokError.badResponse("model list")
        }
        return list.compactMap(GrokModelInfo.init(json:))
    }

    /// Streams an answer as it is written.
    func stream(_ grokRequest: GrokRequest) -> AsyncThrowingStream<GrokStreamEvent, Error> {
        #if DEBUG
        if apiKey == Self.simulatedKey { return simulatedStream(grokRequest) }
        #endif
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try request(path: "responses", method: "POST", body: grokRequest.body(stream: true))
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await Self.session.bytes(for: urlRequest)
                    } catch {
                        throw Self.networkError(error)
                    }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 32_000 { break }
                        }
                        try Self.check(response, data: body)
                    }

                    var parser = SSEParser()
                    var accumulated = ""
                    var citations: [URL] = []
                    var finished = false

                    func handle(_ event: SSEEvent) throws {
                        guard event.data != "[DONE]",
                              let data = event.data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                        for output in try Self.events(from: json, eventName: event.event) {
                            switch output {
                            case .textDelta(let delta):
                                accumulated += delta
                            case .citation(let url):
                                if !citations.contains(url) { citations.append(url) }
                            case .completed(var result):
                                if result.text.isEmpty { result.text = accumulated }
                                for url in citations where !result.citations.contains(url) {
                                    result.citations.append(url)
                                }
                                finished = true
                                continuation.yield(.completed(result))
                                continue
                            case .activity:
                                break
                            }
                            continuation.yield(output)
                        }
                    }

                    // Split on "\n" bytes here: `AsyncBytes.lines` also splits on U+2028, U+2029
                    // and U+0085, which JSON may carry unescaped inside a string.
                    var buffer: [UInt8] = []
                    buffer.reserveCapacity(4096)
                    do {
                        for try await byte in bytes {
                            if byte == 0x0A {
                                if buffer.last == 0x0D { buffer.removeLast() }
                                let line = String(decoding: buffer, as: UTF8.self)
                                buffer.removeAll(keepingCapacity: true)
                                try Task.checkCancellation()
                                if let event = parser.feed(line) { try handle(event) }
                            } else {
                                buffer.append(byte)
                            }
                        }
                    } catch let error as GrokError {
                        throw error
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw Self.networkError(error)
                    }
                    if !buffer.isEmpty, let event = parser.feed(String(decoding: buffer, as: UTF8.self)) { try handle(event) }
                    if let event = parser.flush() { try handle(event) }
                    if !finished {
                        continuation.yield(.completed(GrokResult(text: accumulated, citations: citations, model: grokRequest.model)))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Parsing (static, tested in Tests/LogicTests.swift)

    /// URL errors in the user's words. A cancelled request stays a cancellation.
    static func networkError(_ error: Error) -> Error {
        if error is CancellationError { return error }
        guard let urlError = error as? URLError else { return GrokError.network(error.localizedDescription) }
        switch urlError.code {
        case .cancelled:
            return CancellationError()
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff:
            return GrokError.offline
        case .networkConnectionLost:
            return GrokError.connectionLost
        case .timedOut:
            return GrokError.timedOut
        default:
            return GrokError.network(urlError.localizedDescription)
        }
    }

    static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        let detail: String = {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = json["error"] { return message(from: error) }
                if let code = json["code"] as? String { return code }
            }
            return String(data: data.prefix(300), encoding: .utf8) ?? ""
        }()
        let lower = detail.lowercased()
        switch http.statusCode {
        case 401:
            throw GrokError.invalidKey
        case 403:
            if lower.contains("api key") && (lower.contains("incorrect") || lower.contains("invalid") || lower.contains("disabled") || lower.contains("blocked")) {
                throw GrokError.invalidKey
            }
            // Out of credits, a blocked team, or a key without access to the model.
            throw GrokError.noCredits
        case 400 where lower.contains("api key"):
            throw GrokError.invalidKey
        case 400 where lower.contains("model") && (lower.contains("not found") || lower.contains("does not exist") || lower.contains("not available")),
             404 where lower.contains("model"):
            throw GrokError.modelUnavailable(Self.modelName(in: detail) ?? "choisi")
        case 402:
            throw GrokError.noCredits
        case 429:
            throw GrokError.rateLimited
        default:
            throw GrokError.server(http.statusCode, detail)
        }
    }

    /// The model a "model not found" message names, when it says it plainly.
    static func modelName(in detail: String) -> String? {
        guard let range = detail.range(of: #"grok-[A-Za-z0-9.\-]+"#, options: .regularExpression) else { return nil }
        return String(detail[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    static func message(from error: Any) -> String {
        if let text = error as? String { return text }
        if let dict = error as? [String: Any] {
            return (dict["message"] as? String) ?? (dict["code"] as? String) ?? "unknown error"
        }
        return "unknown error"
    }

    /// Maps one streamed JSON event to zero or more client events.
    static func events(from json: [String: Any], eventName: String?) throws -> [GrokStreamEvent] {
        let type = (json["type"] as? String) ?? eventName ?? ""

        if type.hasSuffix("output_text.delta"), let delta = json["delta"] as? String {
            return [.textDelta(delta)]
        }
        if type.hasSuffix("annotation.added"), let annotation = json["annotation"] as? [String: Any],
           let url = citation(from: annotation) {
            return [.citation(url)]
        }
        if type == "response.completed" || type == "response.done" || type == "response.incomplete" {
            let response = (json["response"] as? [String: Any]) ?? json
            return [.completed(result(fromResponse: response))]
        }
        if type == "response.failed" || type == "error" || type == "response.error" {
            let response = json["response"] as? [String: Any]
            let error = response?["error"] ?? json["error"] ?? json["message"] ?? "the request failed"
            throw GrokError.badResponse(message(from: error))
        }
        if let activity = activity(type: type, json: json) {
            return [.activity(activity)]
        }
        return []
    }

    static func activity(type: String, json: [String: Any]) -> GrokActivity? {
        if type.contains("reasoning") && type.hasSuffix(".delta") { return .thinking }
        var kind = type
        if type.hasSuffix("output_item.added"), let item = json["item"] as? [String: Any], let itemType = item["type"] as? String {
            if itemType == "reasoning" { return .thinking }
            kind = itemType
            // X search runs as custom tool calls named x_keyword_search, x_semantic_search, and so on.
            if itemType == "custom_tool_call" || itemType == "function_call", let name = item["name"] as? String {
                kind = name
            }
        } else if !(type.contains("_call") && (type.hasSuffix("in_progress") || type.hasSuffix("searching"))) {
            return nil
        }
        if kind.hasPrefix("x_") || kind.contains("x_search") || kind.contains("x_keyword") || kind.contains("x_semantic") {
            return .searchingX
        }
        if kind.contains("web_search") || kind.contains("browse") { return .searchingWeb }
        if kind.contains("code") { return .runningCode }
        if kind.contains("search") { return .searching }
        return nil
    }

    static func citation(from annotation: [String: Any]) -> URL? {
        guard let raw = annotation["url"] as? String, let url = URL(string: raw),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    /// Reads the answer text, citations and usage from a full Responses API object.
    static func result(fromResponse json: [String: Any]) -> GrokResult {
        var text = ""
        var citations: [URL] = []
        for item in json["output"] as? [[String: Any]] ?? [] where (item["type"] as? String) == "message" {
            for content in item["content"] as? [[String: Any]] ?? [] {
                if let piece = content["text"] as? String { text += piece }
                for annotation in content["annotations"] as? [[String: Any]] ?? [] {
                    if let url = citation(from: annotation), !citations.contains(url) { citations.append(url) }
                }
            }
        }
        if text.isEmpty, let outputText = json["output_text"] as? String { text = outputText }
        for raw in json["citations"] as? [Any] ?? [] {
            let string = (raw as? String) ?? ((raw as? [String: Any])?["url"] as? String)
            if let string, let url = URL(string: string), url.scheme?.hasPrefix("http") == true, !citations.contains(url) {
                citations.append(url)
            }
        }
        return GrokResult(text: text, citations: citations,
                          usage: GrokUsage(json: json["usage"] as? [String: Any]),
                          model: json["model"] as? String)
    }
}
