//
//  ChatModel.swift
//  GrokWatch
//
//  One conversation with Grok: asks, streams the answer in, and makes sure the answer reaches the
//  wrist even when it lands after the wrist went down (as a notification then). Nothing is ever
//  spoken aloud.
//

import Foundation
import Observation
import WatchKit

@Observable
final class ChatModel {
    /// After this long without a word, opening the app starts a fresh conversation (the last one
    /// stays one tap away).
    static let freshAfter: TimeInterval = 60 * 60
    /// How many earlier messages go with a question.
    static let contextLimit = 20

    let preferences: Preferences
    private(set) var conversation: Conversation
    /// The conversation before this one, so a fresh start loses nothing.
    private(set) var previous: Conversation?
    /// What Grok is doing while no words are coming.
    private(set) var activity: GrokActivity?
    private(set) var isBusy = false
    /// The question to bring into view, once per question.
    private(set) var scrollTarget: UUID?
    /// Set when an answer that fits on screen is done: the view scrolls it clear of the buttons.
    private(set) var revealedAnswer: UUID?

    /// Answers up to this length fit above the bottom buttons with their question in view.
    static let shortAnswer = 140

    static func fitsOnScreen(_ message: ChatMessage) -> Bool {
        message.state == .failed || AnswerText.plain(message.text).count <= shortAnswer
    }
    private(set) var keyHint: String?
    private(set) var install: InstallInfo?
    /// Set when the key just arrived from the Mac, until the first question.
    private(set) var keyImportNotice: String?

    /// The microphone: recording the question, then SpaceXAI turning it into text.
    enum Voice: Equatable { case off, listening, transcribing }
    private(set) var voice = Voice.off
    /// A line about the last try with the microphone (nothing heard, no access, an error).
    private(set) var voiceNotice: String?
    let recorder = VoiceRecorder()

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var transcription: Task<Void, Never>?

    init(preferences: Preferences) {
        self.preferences = preferences
        var current = ConversationStore.load(.current) ?? Conversation()
        current.settleUnfinished()
        conversation = current
        previous = ConversationStore.load(.previous)
        let imported = KeyImport.run()
        keyHint = GrokKeyStore.hint()
        install = InstallExpiry.current()
        if imported { keyArrivedFromMac() }
        #if DEBUG
        applyDebugHooks()
        #endif
    }

    var messages: [ChatMessage] { conversation.messages }
    var hasKey: Bool { keyHint != nil }
    var hasPrevious: Bool { previous?.messages.isEmpty == false }

    /// The line to show when the install ends within two weeks.
    var expiryNotice: String? {
        guard let install else { return nil }
        let days = install.daysLeft(from: Date())
        return days <= 14 ? ProvisioningProfile.notice(daysLeft: days) : nil
    }

    private var isStale: Bool {
        !messages.isEmpty && Date().timeIntervalSince(conversation.updatedAt) > Self.freshAfter
    }

    // MARK: - Life cycle

    func becameActive() {
        Notifier.clearDeliveredAnswers()
        install = InstallExpiry.current()
        if KeyImport.run() {
            keyChanged()
            keyArrivedFromMac()
        }
    }

    /// The key came from install-key.sh: say so, then ask for notifications (answers that land
    /// with the wrist down, the reminder before the install ends) and fetch the model list.
    private func keyArrivedFromMac() {
        keyImportNotice = "SpaceXAI key received from the Mac. Grok is ready."
        Task {
            await Notifier.requestAuthorizationIfNeeded()
            await InstallExpiry.refreshReminders()
            await refreshModels()
        }
    }

    /// The app came back on screen from the background (opened again, not just the wrist raised).
    func reopened() {
        if !isBusy, isStale { archiveAndStartFresh() }
    }

    func wentToBackground() {
        keyImportNotice = nil
    }

    func keyChanged() {
        keyHint = GrokKeyStore.hint()
    }

    func refreshModels() async {
        guard let key = GrokKeyStore.read(), let list = try? await GrokClient(apiKey: key).listModels() else { return }
        preferences.adopt(list)
    }

    // MARK: - Asking

    func ask(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        if isStale { archiveAndStartFresh() }
        keyImportNotice = nil
        voiceNotice = nil
        let question = ChatMessage(role: .user, text: text)
        conversation.messages.append(question)
        conversation.updatedAt = Date()
        scrollTarget = question.id
        run(answering: question.id)
    }

    func retry(_ failed: ChatMessage) {
        guard !isBusy, let index = messages.firstIndex(where: { $0.id == failed.id }) else { return }
        conversation.messages.remove(at: index)
        guard let question = messages[..<index].last(where: { $0.role == .user }) else { save(); return }
        scrollTarget = question.id
        run(answering: question.id)
    }

    func stop() {
        task?.cancel()
    }

    func newConversation() {
        stop()
        archiveAndStartFresh()
    }

    func restorePrevious() {
        guard !isBusy, let previous, !previous.messages.isEmpty else { return }
        let current = conversation
        conversation = previous
        conversation.updatedAt = Date()
        self.previous = current.messages.isEmpty ? nil : current
        save()
        scrollTarget = messages.last(where: { $0.role == .user })?.id
    }

    private func archiveAndStartFresh() {
        var old = conversation
        old.settleUnfinished()
        if !old.messages.isEmpty { previous = old }
        conversation = Conversation()
        activity = nil
        scrollTarget = nil
        save()
    }

    private func save() {
        ConversationStore.save(conversation, as: .current)
        ConversationStore.save(previous, as: .previous)
    }

    // MARK: - Voice

    /// One tap: the watch taps the wrist and starts recording; it stops by itself when the speaking
    /// stops, the words come back from SpaceXAI, and they are asked as the question.
    func listen() {
        guard hasKey, !isBusy, voice == .off else { return }
        voiceNotice = nil
        voice = .listening
        WKInterfaceDevice.current().play(.start)
        Task {
            await recorder.start { [weak self] outcome in
                self?.voiceFinished(outcome)
            }
        }
    }

    /// Sends what has been said so far.
    func stopListening() {
        recorder.stop()
    }

    func cancelListening() {
        if voice == .listening {
            recorder.cancel()
        } else {
            transcription?.cancel()
            transcription = nil
            voice = .off
        }
    }

    private func voiceFinished(_ outcome: VoiceRecorder.Outcome) {
        switch outcome {
        case .recorded(let url):
            WKInterfaceDevice.current().play(.click)
            voice = .transcribing
            transcription = Task { await transcribe(url) }
        case .nothingHeard:
            voice = .off
            voiceNotice = "I didn’t hear anything. Tap the microphone and speak."
        case .cancelled:
            voice = .off
        case .failed(let message):
            voice = .off
            voiceNotice = message
        }
    }

    private func transcribe(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let key = GrokKeyStore.read(), let audio = try? Data(contentsOf: url) else {
            voice = .off
            return
        }
        let background = BackgroundActivity.begin(reason: "Grok is listening")
        defer { background.end() }
        do {
            let transcript = try await SpeechClient(apiKey: key)
                .transcribe(audio: audio, fileName: "question.m4a", language: preferences.speechLanguage.code)
            guard !Task.isCancelled else { return }
            if let seconds = transcript.duration { Spending.add(seconds / 3_600 * SpeechClient.usdPerHour) }
            voice = .off
            transcription = nil
            if transcript.text.isEmpty {
                voiceNotice = "I didn’t hear anything. Tap the microphone and speak."
            } else {
                ask(transcript.text)
            }
        } catch {
            guard !Task.isCancelled else { return }
            voice = .off
            transcription = nil
            voiceNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - One answer

    private enum Outcome { case answered, failed, stopped }

    private func run(answering questionID: UUID, mayChangeModel: Bool = true) {
        guard let key = GrokKeyStore.read() else {
            conversation.messages.append(ChatMessage(role: .grok, text: "", state: .failed,
                                                     errorText: GrokError.missingKey.localizedDescription))
            keyChanged()
            save()
            return
        }
        let answer = ChatMessage(role: .grok, text: "", state: .streaming)
        conversation.messages.append(answer)
        let request = makeRequest(through: questionID)
        isBusy = true
        activity = nil
        // Keeps the app alive long enough to finish when the wrist goes down mid-answer.
        let background = BackgroundActivity.begin(reason: "Grok is answering")
        task = Task {
            await self.stream(request, key: key, into: answer.id, answering: questionID, mayChangeModel: mayChangeModel)
            background.end()
        }
    }

    private func makeRequest(through questionID: UUID) -> GrokRequest {
        var tools: [GrokTool] = []
        if preferences.webSearch { tools.append(.webSearch) }
        if preferences.xSearch { tools.append(.xSearch) }
        let effort = ModelChoice.effort(wanted: preferences.reasoning.rawValue, supported: preferences.modelInfo?.reasoningEfforts)
        return GrokRequest(
            model: preferences.model,
            instructions: Prompt.instructions(now: Date(), timeZone: .current, canSearch: !tools.isEmpty),
            input: conversation.turns(through: questionID, limit: Self.contextLimit),
            tools: tools,
            maxTurns: tools.isEmpty ? nil : 3,
            maxOutputTokens: effort == "none" ? 1_500 : 4_000,
            reasoningEffort: effort,
            promptCacheKey: "grokwatch-\(conversation.id.uuidString)")
    }

    private func stream(_ request: GrokRequest, key: String, into answerID: UUID, answering questionID: UUID, mayChangeModel: Bool) async {
        var text = ""
        var hosts: [String] = []
        var lastShown = ContinuousClock.now
        var outcome = Outcome.stopped

        do {
            for try await event in GrokClient(apiKey: key).stream(request) {
                switch event {
                case .textDelta(let delta):
                    text += delta
                    activity = nil
                    // A watch redraws slowly: show the words in small batches, not one by one.
                    let now = ContinuousClock.now
                    if now - lastShown >= .milliseconds(90) {
                        lastShown = now
                        update(answerID) { $0.text = text }
                    }
                case .activity(let next):
                    activity = next
                case .citation(let url):
                    AnswerText.addHost(of: url, to: &hosts)
                case .completed(let result):
                    let final = result.text.isEmpty ? text : result.text
                    for url in result.citations { AnswerText.addHost(of: url, to: &hosts) }
                    update(answerID) {
                        $0.text = final
                        $0.state = final.isEmpty ? .failed : .complete
                        $0.errorText = final.isEmpty ? "Grok didn’t answer. Try again." : nil
                        $0.sources = Array(hosts.prefix(3))
                        $0.costUSD = result.usage?.costUSD
                    }
                    if let cost = result.usage?.costUSD { Spending.add(cost) }
                    outcome = final.isEmpty ? .failed : .answered
                }
            }
            if outcome == .stopped {
                update(answerID) {
                    $0.text = text
                    $0.state = .interrupted
                }
            }
        } catch let error as GrokError {
            if case .modelUnavailable = error, mayChangeModel, await switchModel(key: key) {
                conversation.messages.removeAll { $0.id == answerID }
                finishRun()
                run(answering: questionID, mayChangeModel: false)
                return
            }
            fail(answerID, partial: text, error: error)
            outcome = .failed
        } catch is CancellationError {
            update(answerID) {
                $0.text = text
                $0.state = .interrupted
            }
        } catch {
            fail(answerID, partial: text, error: .network(error.localizedDescription))
            outcome = .failed
        }
        finishRun()
        if let answer = messages.first(where: { $0.id == answerID }), Self.fitsOnScreen(answer) {
            revealedAnswer = answerID
        }
        if outcome != .stopped { announce(answerID) }
    }

    private func finishRun() {
        isBusy = false
        activity = nil
        task = nil
        conversation.updatedAt = Date()
        save()
    }

    private func fail(_ id: UUID, partial: String, error: GrokError) {
        update(id) {
            $0.text = partial
            $0.state = .failed
            $0.errorText = error.localizedDescription
        }
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&conversation.messages[index])
    }

    /// A tap on the wrist when the app is on screen; a notification when it isn't.
    private func announce(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let answer = messages[index]
        if WKApplication.shared().applicationState == .active {
            WKInterfaceDevice.current().play(answer.state == .failed ? .failure : .success)
        } else {
            let question = messages[..<index].last(where: { $0.role == .user })?.text
            Notifier.postAnswer(answer, question: question)
        }
    }

    /// The chosen model is gone: take the replacement SpaceXAI lists, once.
    private func switchModel(key: String) async -> Bool {
        guard let list = try? await GrokClient(apiKey: key).listModels(), !list.isEmpty,
              let replacement = ModelChoice.replacement(for: preferences.model, in: list) else { return false }
        preferences.models = list
        preferences.model = replacement
        return true
    }

    // MARK: - Debug

    #if DEBUG
    private func applyDebugHooks() {
        if DebugHooks.fresh { archiveAndStartFresh() }
        if DebugHooks.demo {
            conversation = Conversation(messages: [
                ChatMessage(role: .user, text: "Hey, what’s 2 + 2?"),
                ChatMessage(role: .grok, text: "4."),
                ChatMessage(role: .user, text: "And the square root of 1764?"),
                ChatMessage(role: .grok, text: "**42.** Also the answer to the great question of life, the universe and everything.", costUSD: 0.0004),
            ])
            scrollTarget = conversation.messages.last(where: { $0.role == .user })?.id
        }
        if let question = DebugHooks.ask {
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                ask(question)
            }
        }
        if let seconds = DebugHooks.listenFor {
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                listen()
                try? await Task.sleep(for: .seconds(seconds))
                stopListening()
            }
        }
    }
    #endif
}
