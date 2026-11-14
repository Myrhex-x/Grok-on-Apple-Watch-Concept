//
//  DebugHooks.swift
//  GrokWatch
//
//  Debug builds only: launch arguments for the simulator, so every screen can be reached and
//  checked without a voice, a keyboard or the real key.
//
//    -GrokWatchSimulated YES       a pretend Grok (nothing sent, nothing billed)
//    -GrokWatchKey <key>           use this key for the run, without saving it
//    -GrokWatchAsk "<question>"    ask this at launch
//    -GrokWatchFresh YES           start on a new conversation
//    -GrokWatchDemo YES            start with a short conversation on screen
//    -GrokWatchFakeExpiryDays 5    pretend the install ends in 5 days
//    -GrokWatchPage settings|key   open that page at launch
//    -GrokWatchNoAutoDictation YES never open the microphone by itself
//    -GrokWatchListenFor 2         listen at launch, send after 2 s
//

#if DEBUG
import Foundation

nonisolated enum DebugHooks {
    private static var defaults: UserDefaults { .standard }

    static var keyOverride: String? {
        if defaults.bool(forKey: "GrokWatchSimulated") { return GrokClient.simulatedKey }
        return defaults.string(forKey: "GrokWatchKey")
    }

    static var ask: String? { defaults.string(forKey: "GrokWatchAsk") }
    /// Start on a new conversation (the current one becomes the previous one).
    static var fresh: Bool { defaults.bool(forKey: "GrokWatchFresh") }
    static var demo: Bool { defaults.bool(forKey: "GrokWatchDemo") }
    static var page: String? { defaults.string(forKey: "GrokWatchPage") }

    static var fakeExpiryDays: Double? {
        defaults.object(forKey: "GrokWatchFakeExpiryDays") == nil ? nil : defaults.double(forKey: "GrokWatchFakeExpiryDays")
    }

    /// Start listening at launch and send after this many seconds (the simulator can't be spoken to).
    static var listenFor: Double? {
        defaults.object(forKey: "GrokWatchListenFor") == nil ? nil : defaults.double(forKey: "GrokWatchListenFor")
    }

    static var noAutoDictation: Bool {
        defaults.bool(forKey: "GrokWatchNoAutoDictation") || ask != nil || demo || page != nil || listenFor != nil
    }
}
#endif
