//
//  LogicTests.swift
//  GrokWatch
//
//  Runs on the Mac (Tests/run.sh): everything that doesn't need a watch. The stream fixtures follow
//  the Responses API events as they arrive live.
//

import Foundation

@main
struct LogicTests {
    static var failures = 0
    static var count = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        count += 1
        if !condition() {
            failures += 1
            print("FAIL line \(line): \(message)")
        }
    }

    static func main() {
        sse()
        events()
        errors()
        requestBody()
        models()
        answerText()
        conversation()
        profile()
        reminders()
        spending()
        prompt()
        speech()
        print("\(count - failures)/\(count) checks passed")
        exit(failures == 0 ? 0 : 1)
    }

    static func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    static func events(_ text: String) -> [GrokStreamEvent]? {
        try? GrokClient.events(from: json(text), eventName: nil)
    }

    // MARK: -

    static func sse() {
        var parser = SSEParser()
        check(parser.feed("event: response.output_text.delta") == nil, "event line buffers")
        check(parser.feed(#"data: {"a":1}"#) == nil, "data line buffers")
        check(parser.feed("") == SSEEvent(event: "response.output_text.delta", data: #"{"a":1}"#), "blank line ends an event")
        check(parser.feed(": keep-alive") == nil && parser.feed("") == nil, "comments ignored")
        _ = parser.feed("data: one")
        _ = parser.feed("data: two\r")
        check(parser.flush()?.data == "one\ntwo", "multi-line data joins, CR dropped")
    }

    static func events() {
        check(events(#"{"type":"response.output_text.delta","delta":"Hello"}"#) == [.textDelta("Hello")], "text delta")
        check(events(#"{"type":"response.reasoning_summary_text.delta","delta":"hm"}"#) == [.activity(.thinking)], "reasoning is thinking")
        check(events(#"{"type":"response.output_item.added","item":{"type":"reasoning"}}"#) == [.activity(.thinking)], "reasoning item")
        check(events(#"{"type":"response.web_search_call.in_progress"}"#) == [.activity(.searchingWeb)], "web search")
        check(events(#"{"type":"response.output_item.added","item":{"type":"custom_tool_call","name":"x_keyword_search"}}"#) == [.activity(.searchingX)], "X search")
        check(events(#"{"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://www.lemonde.fr/a","title":"1"}}"#)
              == [.citation(URL(string: "https://www.lemonde.fr/a")!)], "citation")
        check(events(#"{"type":"response.created","response":{}}"#)?.isEmpty == true, "other events ignored")

        let done = events(#"{"type":"response.completed","response":{"model":"grok-4.3","output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"4.","annotations":[{"url":"https://example.com/x","title":"1"}]}]}],"usage":{"input_tokens":120,"output_tokens":2,"cost_in_usd_ticks":1650000}}}"#)
        if case .completed(let result)? = done?.first {
            check(result.text == "4.", "completed text")
            check(abs((result.usage?.costUSD ?? 0) - 0.000165) < 1e-12, "cost from ticks")
            check(result.model == "grok-4.3", "model")
            check(result.citations == [URL(string: "https://example.com/x")!], "citations from the final message")
        } else {
            check(false, "completed event")
        }

        do {
            _ = try GrokClient.events(from: json(#"{"type":"response.failed","response":{"error":{"message":"boom"}}}"#), eventName: nil)
            check(false, "a failed response throws")
        } catch let error as GrokError {
            check(error == .badResponse("boom"), "failed response message")
        } catch {
            check(false, "failed response error type")
        }
    }

    static func response(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.x.ai/v1/responses")!, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    static func expect(_ code: Int, _ body: String, _ expected: GrokError, _ name: String) {
        do {
            try GrokClient.check(response(code), data: Data(body.utf8))
            check(false, "\(name) should throw")
        } catch let error as GrokError {
            check(error == expected, "\(name): got \(error)")
        } catch {
            check(false, "\(name): wrong error type")
        }
    }

    static func errors() {
        expect(401, "{}", .invalidKey, "401")
        expect(400, #"{"code":"Client specified an invalid argument","error":"Incorrect API key provided: xa***00. You can obtain an API key from https://console.x.ai."}"#, .invalidKey, "400 bad key")
        expect(404, #"{"error":"The model grok-9.1 does not exist or your team does not have access to it."}"#, .modelUnavailable("grok-9.1"), "404 model")
        expect(400, #"{"error":"Model not found: grok-4.1-fast."}"#, .modelUnavailable("grok-4.1-fast"), "400 model")
        expect(403, #"{"error":"Your team has run out of credits."}"#, .noCredits, "403 credits")
        expect(429, "{}", .rateLimited, "429")
        expect(500, #"{"error":{"message":"oops"}}"#, .server(500, "oops"), "500")
        check((try? GrokClient.check(response(200), data: Data())) != nil, "200 passes")
        check(GrokClient.networkError(URLError(.notConnectedToInternet)) as? GrokError == .offline, "offline")
        check(GrokClient.networkError(URLError(.networkConnectionLost)) as? GrokError == .connectionLost, "connection lost")
        check(GrokClient.networkError(URLError(.timedOut)) as? GrokError == .timedOut, "timed out")
        check(GrokClient.networkError(URLError(.cancelled)) is CancellationError, "cancelled stays a cancellation")
        check(GrokError.invalidKey.errorDescription?.contains("Settings") == true, "English wording")
    }

    static func requestBody() {
        let request = GrokRequest(model: "grok-4.3", instructions: "x", input: [GrokTurn(role: .user, text: "2+2")],
                                  tools: [.webSearch, .xSearch], maxTurns: 3, maxOutputTokens: 1500,
                                  reasoningEffort: "none", promptCacheKey: "k")
        let body = request.body(stream: true)
        check(body["store"] as? Bool == false, "store false")
        check(body["stream"] as? Bool == true, "stream")
        check(body["model"] as? String == "grok-4.3", "model")
        check((body["tools"] as? [[String: Any]])?.compactMap { $0["type"] as? String } == ["web_search", "x_search"], "tools")
        check((body["reasoning"] as? [String: Any])?["effort"] as? String == "none", "effort")
        check(body["max_turns"] as? Int == 3 && body["max_output_tokens"] as? Int == 1500, "caps")
        check(body["prompt_cache_key"] as? String == "k", "cache key")
        let input = body["input"] as? [[String: Any]]
        check(input?.first?["role"] as? String == "user" && input?.first?["content"] as? String == "2+2", "input")
        let plain = GrokRequest(model: "m", instructions: "i", input: []).body(stream: false)
        check(plain["tools"] == nil && plain["reasoning"] == nil && plain["max_turns"] == nil, "optional fields left out")
        check(JSONSerialization.isValidJSONObject(body), "valid JSON")
    }

    static func models() {
        func model(_ id: String, _ price: Double?) -> GrokModelInfo {
            var info = GrokModelInfo(id: id)
            info.inputPerMillion = price
            return info
        }
        let list = [model("grok-4.7", 3), model("grok-imagine-image", 0.5), model("grok-4.3", 1.25),
                    model("grok-imagine-video", 1), model("grok-4.5", 2)]
        check(ModelChoice.chatModels(list).map(\.id) == ["grok-4.3", "grok-4.5", "grok-4.7"], "text models, cheapest first")
        check(ModelChoice.replacement(for: "grok-4-1-fast", in: list) == "grok-4.3", "a retired model is replaced by grok-4.3")
        check(ModelChoice.replacement(for: "grok-4.3", in: list) == "grok-4.5", "else by the cheapest other")
        check(ModelChoice.replacement(for: "x", in: []) == nil, "nothing to replace with")
        check(ModelChoice.effort(wanted: "none", supported: ["low", "medium", "high"]) == "low", "none becomes low")
        check(ModelChoice.effort(wanted: "none", supported: ["none", "low"]) == "none", "kept when supported")
        check(ModelChoice.effort(wanted: "high", supported: nil) == "high", "unknown support: as wanted")
        check(ModelChoice.effort(wanted: "xhigh", supported: ["low", "high"]) == "high", "capped at the highest")
        let parsed = GrokModelInfo(json: ["id": "grok-4.3", "prompt_text_token_price": 12500, "completion_text_token_price": 25000,
                                          "capabilities": ["reasoning_effort": ["none", "low"]]])
        check(parsed?.inputPerMillion == 1.25 && parsed?.outputPerMillion == 2.5, "prices per million")
        check(parsed?.reasoningEfforts == ["none", "low"], "reasoning efforts")
    }

    static func answerText() {
        check(AnswerText.clean("It’s 11 °C [[1]](https://meteofrance.com/x).") == "It’s 11 °C.", "citation markers removed")
        check(AnswerText.clean("## Title\nText") == "Title\nText", "heading marks removed")
        check(AnswerText.plain("**42.** That’s *it*.") == "42. That’s it.", "plain text")
        check(AnswerText.plain("line 1\nline 2") == "line 1\nline 2", "line breaks kept")
        check(String(AnswerText.attributed("**bold").characters).contains("bold"), "unfinished Markdown still shows")
        var hosts: [String] = []
        AnswerText.addHost(of: URL(string: "https://www.lemonde.fr/a")!, to: &hosts)
        AnswerText.addHost(of: URL(string: "https://lemonde.fr/b")!, to: &hosts)
        check(hosts == ["lemonde.fr"], "hosts once, without www")
    }

    static func conversation() {
        let q1 = ChatMessage(role: .user, text: "a")
        let a1 = ChatMessage(role: .grok, text: "b [[1]](https://x.com/y)")
        let q2 = ChatMessage(role: .user, text: "c")
        let a2 = ChatMessage(role: .grok, text: "", state: .failed, errorText: "x")
        let q3 = ChatMessage(role: .user, text: "d")
        let a3 = ChatMessage(role: .grok, text: "", state: .streaming)
        var conversation = Conversation(messages: [q1, a1, q2, a2, q3, a3])
        let turns = conversation.turns(through: q3.id, limit: 20)
        check(turns.map(\.text) == ["a", "b", "c", "d"], "failed and pending answers left out, markers cleaned: \(turns.map(\.text))")
        check(turns.map(\.role) == [.user, .assistant, .user, .user], "roles")
        check(conversation.turns(through: q3.id, limit: 2).map(\.text) == ["c", "d"], "newest kept")
        check(conversation.turns(through: q1.id, limit: 20).map(\.text) == ["a"], "only up to the question")
        conversation.settleUnfinished()
        check(conversation.messages.last?.state == .failed, "an empty unfinished answer settles as failed")
        let data = try? JSONEncoder().encode(conversation)
        check(data.flatMap { try? JSONDecoder().decode(Conversation.self, from: $0) } == conversation, "saves and loads")
    }

    static func profile() {
        let expiry = Date(timeIntervalSince1970: 1_820_000_000)
        let certificateEnd = Date(timeIntervalSince1970: 1_810_000_000)
        let plist: [String: Any] = ["ExpirationDate": expiry, "DeveloperCertificates": [Data([1]), Data([2])],
                                    "Name": "iOS Team Provisioning Profile: com.myrhex.GrokWatch.watchkitapp"]
        let xml = (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
        let wrapped = Data([0x30, 0x82, 0x01, 0x00]) + xml + Data([0x00, 0xA0, 0x82])
        let info = ProvisioningProfile.info(from: wrapped) { der in
            der == Data([1]) ? certificateEnd : Date(timeIntervalSince1970: 1_830_000_000)
        }
        check(info?.profileExpiry == expiry, "profile end")
        check(info?.certificateExpiry == certificateEnd, "earliest certificate end")
        check(info?.expiry == certificateEnd, "the install ends with the certificate when it ends first")
        check(ProvisioningProfile.info(from: Data("junk".utf8)) { _ in nil } == nil, "junk gives nothing")

        // A real profile from this Mac, when there is one: its dates come out.
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles")
        if let name = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.first,
           let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
            check(ProvisioningProfile.info(from: data) { _ in nil }?.profileExpiry != nil, "a real profile parses")
        }
    }

    static func reminders() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let expiry = calendar.date(from: DateComponents(year: 2027, month: 7, day: 14, hour: 16, minute: 46))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 23))!
        let list = ProvisioningProfile.reminders(for: expiry, now: now, calendar: calendar)
        check(list.map(\.id) == ["expiry-7", "expiry-2", "expiry-1"], "three reminders")
        let parts = list.map { calendar.dateComponents([.month, .day, .hour], from: $0.date) }
        check(parts.map(\.day) == [7, 12, 13] && parts.map(\.hour) == [10, 10, 18], "a week, two days, the evening before")
        check(list.first?.body.contains("July 14, 2027 at 4:46") == true, "date in English: \(list.first?.body ?? "")")
        let late = calendar.date(from: DateComponents(year: 2027, month: 7, day: 12, hour: 12))!
        check(ProvisioningProfile.reminders(for: expiry, now: late, calendar: calendar).map(\.id) == ["expiry-1"], "past reminders left out")
        let info = InstallInfo(profileExpiry: expiry, certificateExpiry: nil)
        check(info.daysLeft(from: now, calendar: calendar) == 243, "days left: \(info.daysLeft(from: now, calendar: calendar))")
        check(ProvisioningProfile.notice(daysLeft: 1).contains("tomorrow"), "tomorrow")
        check(ProvisioningProfile.notice(daysLeft: 0).contains("today"), "today")
    }

    static func spending() {
        let defaults = UserDefaults(suiteName: "grokwatch-tests-\(UUID().uuidString)")!
        let date = Date(timeIntervalSince1970: 1_794_000_000)
        Spending.add(0.004, on: date, defaults: defaults)
        Spending.add(0.5, on: date, defaults: defaults)
        Spending.add(-1, on: date, defaults: defaults)
        check(abs(Spending.total(on: date, defaults: defaults) - 0.504) < 1e-9, "adds up, ignores nonsense")
        check(Spending.formatted(0.504) == "$0.50", "format")
        check(Spending.formatted(0.004) == "<\u{00A0}$0.01", "tiny amounts")
        check(Spending.formatted(0) == "$0", "zero")
    }

    static func speech() {
        let body = String(decoding: SpeechClient.body(boundary: "B", audio: Data("AUDIO".utf8), fileName: "q.m4a", language: "fr"), as: UTF8.self)
        check(body.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nfr\r\n"), "language comes first")
        check(body.contains("name=\"format\"\r\n\r\ntrue\r\n"), "digits for spoken numbers when the language is set")
        check(body.components(separatedBy: "name=\"keyterm\"").count == 3, "two key terms, one field each")
        if let file = body.range(of: "name=\"file\"; filename=\"q.m4a\""), let term = body.range(of: "name=\"keyterm\"", options: .backwards) {
            check(term.lowerBound < file.lowerBound, "the file comes after every option")
        } else {
            check(false, "file and key term fields present")
        }
        check(body.contains("Content-Type: audio/mp4\r\n\r\nAUDIO\r\n--B--\r\n"), "audio then the closing boundary")
        let automatic = String(decoding: SpeechClient.body(boundary: "B", audio: Data(), fileName: "q.m4a", language: nil), as: UTF8.self)
        check(!automatic.contains("name=\"language\"") && !automatic.contains("name=\"format\""), "no language: no format either")
        let transcript = try? SpeechClient.transcript(from: Data(#"{"text":" What’s 2 + 2? ","language":"fr","duration":2.4,"words":[]}"#.utf8))
        check(transcript == SpeechClient.Transcript(text: "What’s 2 + 2?", duration: 2.4), "transcript read and trimmed")
        check((try? SpeechClient.transcript(from: Data(#"{"text":"","duration":1}"#.utf8)))?.text == "", "silence is an empty transcript")
        check((try? SpeechClient.transcript(from: Data("{}".utf8))) == nil, "no text is an error")
    }

    static func prompt() {
        let zone = TimeZone(identifier: "Europe/Paris")!
        let now = ISO8601DateFormatter().date(from: "2026-11-13T13:05:00Z")!
        let text = Prompt.instructions(now: now, timeZone: zone, canSearch: true)
        check(text.contains("Friday, November 13, 2026"), "English date")
        check(text.contains("2:05"), "local time")
        check(text.contains("Reply in English"), "English first")
        check(text.contains("search the web before answering"), "search line with tools")
        check(text.contains("who leads a country"), "who holds an office counts as current")
        let offline = Prompt.instructions(now: now, timeZone: zone, canSearch: false)
        check(!offline.contains("search the web") && offline.contains("may be out of date"), "no search line without tools, a warning instead")
        check(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "no long dashes")
    }
}
