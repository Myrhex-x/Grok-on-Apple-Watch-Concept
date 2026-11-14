//
//  VoiceRecorder.swift
//  GrokWatch
//
//  Records the question with the watch's microphone: AAC, 16 kHz, mono, about 4 KB a second, small
//  enough to go out quickly even through the iPhone. It stops by itself once the speaking stops,
//  and gives up when nothing is said. The levels it listens for follow the room's own noise, so a
//  noisy street doesn't keep it recording forever.
//

import AVFoundation
import Observation

@Observable
final class VoiceRecorder {
    enum Outcome: Equatable {
        case recorded(URL)
        case nothingHeard
        case cancelled
        case failed(String)
    }

    /// 0 to 1, for the ring around the microphone.
    private(set) var level: Double = 0
    private(set) var isRecording = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meter: Task<Void, Never>?
    @ObservationIgnored private var finish: ((Outcome) -> Void)?

    // In dBFS, AVAudioRecorder's average power. The floor is the quietest moment so far.
    private static let speechAtLeast: Float = -38
    private static let silenceBelow: Float = -46
    private static let speechAboveFloor: Float = 14
    private static let silenceAboveFloor: Float = 6
    private static let silenceToStop: Duration = .milliseconds(1_400)
    private static let waitForSpeech: Duration = .seconds(7)
    private static let longest: Duration = .seconds(45)

    @ObservationIgnored private var isStarting = false

    func start(_ finish: @escaping (Outcome) -> Void) async {
        guard !isRecording, !isStarting else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            finish(.failed("Grok can’t use the microphone. Allow it in Settings > Privacy & Security > Microphone."))
            return
        }
        isStarting = true
        let opened = await Self.open(timeout: .seconds(4))
        isStarting = false
        switch opened {
        case .success(let box):
            recorder = box.recorder
            self.finish = finish
            isRecording = true
            meter = Task { await self.followLevels() }
        case .failure(let failure):
            finish(.failed(failure.message))
        }
    }

    // MARK: - Opening the microphone, away from the screen

    private nonisolated final class RecorderBox: @unchecked Sendable {
        let recorder: AVAudioRecorder
        init(_ recorder: AVAudioRecorder) { self.recorder = recorder }
    }

    private struct OpenFailure: Error {
        let message: String
    }

    /// Lets exactly one of two racers finish the wait. Both run off the main actor, so it is not
    /// isolated to it; the lock is what keeps it safe.
    private nonisolated final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    /// Activating the audio session and starting the recorder can block; it runs on a background
    /// thread, and a microphone that doesn't answer within `timeout` is reported instead of
    /// freezing the screen.
    private static func open(timeout: Duration) async -> Result<RecorderBox, OpenFailure> {
        await withCheckedContinuation { continuation in
            let once = Once()
            Task.detached(priority: .userInitiated) {
                let result = Self.openNow()
                if once.claim() {
                    continuation.resume(returning: result)
                } else if case .success(let late) = result {
                    late.recorder.stop()
                    late.recorder.deleteRecording()
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                if once.claim() {
                    continuation.resume(returning: .failure(OpenFailure(message: "The microphone isn’t responding. Try again in a moment.")))
                }
            }
        }
    }

    private nonisolated static func openNow() -> Result<RecorderBox, OpenFailure> {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            return .failure(OpenFailure(message: "The microphone isn’t available right now."))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("question-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return .failure(OpenFailure(message: "The microphone couldn’t start."))
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return .failure(OpenFailure(message: "The microphone couldn’t start."))
        }
        return .success(RecorderBox(recorder))
    }

    /// Stops and hands the recording over (the user tapped Send, or the speaking stopped).
    func stop() {
        guard let recorder, isRecording else { return }
        recorder.stop()
        end(.recorded(recorder.url))
    }

    func cancel() {
        guard let recorder, isRecording else { return }
        recorder.stop()
        recorder.deleteRecording()
        end(.cancelled)
    }

    private func followLevels() async {
        let clock = ContinuousClock()
        let started = clock.now
        var floor: Float = 0
        var heard = false
        var quietSince: ContinuousClock.Instant?
        while !Task.isCancelled, let recorder, recorder.isRecording {
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            floor = min(floor, power)
            level = Double(max(0, min(1, (power + 55) / 45)))
            let now = clock.now
            let speech = max(Self.speechAtLeast, floor + Self.speechAboveFloor)
            let silence = max(Self.silenceBelow, floor + Self.silenceAboveFloor)
            if power > speech { heard = true }
            if heard {
                if power < silence {
                    quietSince = quietSince ?? now
                } else {
                    quietSince = nil
                }
            }
            if heard, let quietSince, now - quietSince >= Self.silenceToStop {
                stop()
                return
            }
            if !heard, now - started >= Self.waitForSpeech {
                recorder.stop()
                recorder.deleteRecording()
                end(.nothingHeard)
                return
            }
            if now - started >= Self.longest {
                stop()
                return
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    private func end(_ outcome: Outcome) {
        meter?.cancel()
        meter = nil
        recorder = nil
        isRecording = false
        level = 0
        deactivate()
        let finish = self.finish
        self.finish = nil
        finish?(outcome)
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
