//
//  InstallExpiry.swift
//  GrokWatch
//
//  When this install stops working, and the reminders that come before it (a week, two days and
//  the evening before). Rescheduled at every launch, so a fresh install moves them to its own date.
//

import Foundation
import Security
import UserNotifications

nonisolated enum InstallExpiry {
    /// Nil in the simulator, which embeds no profile.
    static func current() -> InstallInfo? {
        #if DEBUG
        if let days = DebugHooks.fakeExpiryDays {
            return InstallInfo(profileExpiry: Date().addingTimeInterval(days * 86_400), certificateExpiry: nil)
        }
        #endif
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ProvisioningProfile.info(from: data) { der in
            guard let certificate = SecCertificateCreateWithData(nil, der as CFData),
                  let date = SecCertificateCopyNotValidAfterDate(certificate) else { return nil }
            return date as Date
        }
    }

    static func refreshReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("expiry-") })

        guard let info = current() else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        for reminder in ProvisioningProfile.reminders(for: info.expiry, now: Date(), calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = "Grok stops working soon"
            content.body = reminder.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
