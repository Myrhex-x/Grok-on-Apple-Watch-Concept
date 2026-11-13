//
//  Prompt.swift
//  GrokWatch
//
//  The instructions sent with every question: short, and written for a watch screen.
//

import Foundation

nonisolated enum Prompt {
    static func instructions(now: Date, timeZone: TimeZone, canSearch: Bool) -> String {
        let locale = Locale(identifier: "en_US")
        let day = now.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: locale, timeZone: timeZone))
        let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
        var lines = [
            "You are Grok, on the user’s Apple Watch.",
            "Today is \(day), and it is \(time) (time zone \(timeZone.identifier)).",
            "Reply in English, unless the user writes in another language: then reply in theirs.",
            "Your answer shows on a very small screen and is never read aloud. Give the answer directly, with no preamble, without repeating the question and without pleasantries. One to three sentences are usually enough; go into detail only when asked.",
            "For a calculation, a conversion or a precise fact, start with the result.",
            "No tables, no headings, no long code blocks. A short list only if it really helps.",
            "Never use em dashes or en dashes.",
            "Questions are often dictated: if a word looks wrongly transcribed, go with the most likely meaning without mentioning it.",
        ]
        if canSearch {
            lines.append("For news, weather, sports results, prices or anything that changes quickly, search before answering, then answer in one or two sentences.")
        }
        return lines.joined(separator: "\n")
    }
}
