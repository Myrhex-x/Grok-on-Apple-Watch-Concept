//
//  AppDelegate.swift
//  GrokWatch
//

import UserNotifications
import WatchKit

final class AppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        Task { await InstallExpiry.refreshReminders() }
    }

    /// An answer can land while the app is still frontmost but the wrist is down: it is shown
    /// anyway, since that is how it reaches the wrist.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
