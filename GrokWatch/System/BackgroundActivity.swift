//
//  BackgroundActivity.swift
//  GrokWatch
//
//  Asks watchOS for time to finish an answer after the app leaves the screen. The system calls the
//  block on a background queue and keeps the app running while it waits; when the time is up it
//  calls the block a second time with `expired`, and the wait must end at once.
//

import Foundation

nonisolated final class BackgroundActivity: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var ended = false

    private init() {}

    static func begin(reason: String) -> BackgroundActivity {
        let activity = BackgroundActivity()
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
            if expired {
                activity.end()
            } else {
                // Never hold the app longer than any answer could take.
                _ = activity.done.wait(timeout: .now() + 240)
            }
        }
        return activity
    }

    func end() {
        lock.lock()
        defer { lock.unlock() }
        guard !ended else { return }
        ended = true
        done.signal()
    }
}
