//
//  Spending.swift
//  GrokWatch
//
//  What this watch spent this month, from SpaceXSI's own cost per answer.
//

import Foundation

nonisolated enum Spending {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "spend-%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func add(_ usd: Double, on date: Date = Date(), defaults: UserDefaults = .standard) {
        guard usd > 0, usd.isFinite else { return }
        let key = key(for: date)
        defaults.set(defaults.double(forKey: key) + usd, forKey: key)
    }

    static func total(on date: Date = Date(), defaults: UserDefaults = .standard) -> Double {
        defaults.double(forKey: key(for: date))
    }

    /// "$0.42", "< $0.01", "$0" in English; "0,42 $US" and so on in French.
    static func formatted(_ usd: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: "USD", locale: locale)
        if usd <= 0 { return 0.0.formatted(style.precision(.fractionLength(0))) }
        if usd < 0.01 { return "<\u{00A0}" + 0.01.formatted(style.precision(.fractionLength(2))) }
        return usd.formatted(style.precision(.fractionLength(2)))
    }
}
