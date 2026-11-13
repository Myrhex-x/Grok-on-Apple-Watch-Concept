//
//  SSEParser.swift
//  GrokWatch
//
//  Server-sent events, one line at a time: `event:` and `data:` lines until a blank line.
//

import Foundation

nonisolated struct SSEEvent: Equatable, Sendable {
    var event: String?
    var data: String
}

nonisolated struct SSEParser: Sendable {
    private var eventName: String?
    private var dataLines: [String] = []

    /// Feeds one line (without its trailing newline). Returns an event when a blank line ends one.
    mutating func feed(_ rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") { return nil }  // comment or keep-alive

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event": eventName = value
        case "data": dataLines.append(value)
        default: break
        }
        return nil
    }

    /// Emits whatever is buffered (used at the end of the stream too).
    mutating func flush() -> SSEEvent? {
        defer { eventName = nil; dataLines = [] }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
    }
}
