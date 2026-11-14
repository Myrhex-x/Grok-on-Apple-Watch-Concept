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

    func start(_ finish: @escaping (Outcome) -> Void) async {
        guard !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            finish(.failed("Grok can’t use the microphone. Allow it in Settings > Privacy & Security > Microphone."))
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            finish(.failed("The microphone isn’t available right now."))
            return
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
            deactivate()
            finish(.failed("The microphone couldn’t start."))
            return
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            deactivate()
            finish(.failed("The microphone couldn’t start."))
            return
        }
        self.recorder = recorder
        self.finish = finish
        isRecording = true
        meter = Task { await self.followLevels() }
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
