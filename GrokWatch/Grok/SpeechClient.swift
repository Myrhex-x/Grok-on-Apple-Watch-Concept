//
//  SpeechClient.swift
//  GrokWatch
//
//  Speech to text with the same SpaceXSI key: the recorded question goes to POST /v1/stt and comes
//  back as text. watchOS has no speech recognition an app can use, and the system's text input
//  opens on the keyboard, so this is what makes the microphone one tap. SpaceXSI charges about
//  0.10 USD per hour of audio, so a question costs a fraction of a cent.
//

import Foundation

nonisolated struct SpeechClient: Sendable {
    static let url = URL(string: "https://api.x.ai/v1/stt")!
    /// Batch transcription price (SpaceXSI, April 2026).
    static let usdPerHour = 0.10
    /// Words the transcription should expect to hear.
    static let keyTerms = ["Grok", "SpaceXSI"]

    nonisolated struct Transcript: Equatable, Sendable {
        var text: String
        /// Seconds of audio, as SpaceXSI measured it.
        var duration: Double?
    }

    let apiKey: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// `language` is "fr", "en"..., or nil to let SpaceXSI detect it.
    func transcribe(audio: Data, fileName: String, language: String?) async throws -> Transcript {
        #if DEBUG
        if apiKey == GrokClient.simulatedKey {
            try await Task.sleep(for: .milliseconds(700))
            return Transcript(text: "Hey, what’s 2 + 2?", duration: 2.4)
        }
        #endif
        let boundary = "GrokWatch-\(UUID().uuidString)"
        var request = URLRequest(url: Self.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = Self.body(boundary: boundary, audio: audio, fileName: fileName, language: language)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.upload(for: request, from: body)
        } catch {
            throw GrokClient.networkError(error)
        }
        try GrokClient.check(response, data: data)
        return try Self.transcript(from: data)
    }

    /// The options first and the file last: SpaceXSI may ignore fields sent after the file.
    static func body(boundary: String, audio: Data, fileName: String, language: String?) -> Data {
        var body = Data()
        func text(_ string: String) { body.append(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            text("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        if let language {
            field("language", language)
            // Spoken numbers come back as digits; SpaceXSI needs the language for that.
            field("format", "true")
        }
        for term in keyTerms { field("keyterm", term) }
        text("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        text("\r\n--\(boundary)--\r\n")
        return body
    }

    static func transcript(from data: Data) throws -> Transcript {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw GrokError.badResponse("transcription")
        }
        let duration = (json["duration"] as? Double) ?? (json["duration"] as? Int).map(Double.init)
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), duration: duration)
    }
}
