//
//  AnswerText.swift
//  GrokWatch
//
//  Grok writes Markdown. The watch shows the inline part (bold, italics, code) and drops what a
//  small screen can't use: citation markers and heading hashes.
//

import Foundation

nonisolated enum AnswerText {
    /// The answer without `[[1]](https://…)` citation markers or `#` heading marks.
    static func clean(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"[ \t]?\[\[\d+\]\]\([^)\s]*\)"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^[ \t]*#{1,6}[ \t]+"#, with: "", options: .regularExpression)
        return result
    }

    static func attributed(_ text: String) -> AttributedString {
        let cleaned = clean(text)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(cleaned)
    }

    /// The answer as plain text (for a notification).
    static func plain(_ text: String) -> String {
        String(attributed(text).characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Adds the host of a cited page ("lemonde.fr") once.
    static func addHost(of url: URL, to hosts: inout [String]) {
        guard var host = url.host?.lowercased() else { return }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if !hosts.contains(host) { hosts.append(host) }
    }
}
