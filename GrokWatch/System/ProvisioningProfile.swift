//
//  ProvisioningProfile.swift
//  GrokWatch
//
//  The app is installed from Xcode, not the App Store, so it stops launching on a date: the end of
//  its provisioning profile or of the development certificate that signed it, whichever comes
//  first (a profile is not cut short when its certificate ends earlier). Both dates are read from
//  the profile Xcode embeds in the app.
//

import Foundation

nonisolated struct InstallInfo: Equatable, Sendable {
    var profileExpiry: Date
    var certificateExpiry: Date?

    /// When the watch stops launching the app.
    var expiry: Date { min(profileExpiry, certificateExpiry ?? profileExpiry) }

    /// Whole days left, counted by calendar day (0 on the last day).
    func daysLeft(from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiry)).day ?? 0
    }
}

nonisolated struct ExpiryReminder: Equatable, Sendable {
    let id: String
    let date: Date
    let body: String
}

nonisolated enum ProvisioningProfile {
    /// The XML property list inside a .mobileprovision (a signed CMS envelope around it).
    static func plist(from data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let slice = data[start.lowerBound..<end.upperBound]
        return (try? PropertyListSerialization.propertyList(from: Data(slice), format: nil)) as? [String: Any]
    }

    /// Reads the profile's end and its certificates' (`certificateExpiry` turns one DER
    /// certificate into its "not valid after" date).
    static func info(from data: Data, certificateExpiry: (Data) -> Date?) -> InstallInfo? {
        guard let plist = plist(from: data), let expiry = plist["ExpirationDate"] as? Date else { return nil }
        let certificates = plist["DeveloperCertificates"] as? [Data] ?? []
        return InstallInfo(profileExpiry: expiry, certificateExpiry: certificates.compactMap(certificateExpiry).min())
    }

    // MARK: - Words and reminders

    private static let english = Locale(identifier: "en_US")

    static func dayText(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: english, timeZone: timeZone))
    }

    static func timeText(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: english, timeZone: timeZone))
    }

    /// The line shown in the app when the end is near.
    static func notice(daysLeft: Int) -> String {
        switch daysLeft {
        case ..<1: "Grok stops working on this watch today. Install it again from the Mac."
        case 1: "Grok stops working on this watch tomorrow. Install it again from the Mac."
        default: "Grok stops working on this watch in \(daysLeft) days. Install it again from the Mac."
        }
    }

    /// A week before at 10:00, two days before at 10:00, and the evening before at 18:00, local
    /// time. Reminders already past are left out.
    static func reminders(for expiry: Date, now: Date, calendar: Calendar = .current) -> [ExpiryReminder] {
        let plan: [(id: String, days: Int, hour: Int)] = [
            ("expiry-7", -7, 10),
            ("expiry-2", -2, 10),
            ("expiry-1", -1, 18),
        ]
        let when = "on \(dayText(expiry, timeZone: calendar.timeZone)) at \(timeText(expiry, timeZone: calendar.timeZone))"
        return plan.compactMap { step in
            guard let day = calendar.date(byAdding: .day, value: step.days, to: calendar.startOfDay(for: expiry)),
                  let date = calendar.date(bySettingHour: step.hour, minute: 0, second: 0, of: day),
                  date > now, date < expiry else { return nil }
            let body: String = switch step.days {
            case -7: "Grok stops working on your watch in a week, \(when). Connect the iPhone to the Mac and install it again to keep it."
            case -2: "Two days left before Grok stops working on your watch (\(when)). Install it again from the Mac."
            default: "Grok stops working on your watch tomorrow at \(timeText(expiry, timeZone: calendar.timeZone)). Install it again from the Mac tonight."
            }
            return ExpiryReminder(id: step.id, date: date, body: body)
        }
    }
}
