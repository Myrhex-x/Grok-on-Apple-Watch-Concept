//
//  KeyImport.swift
//  GrokWatch
//
//  The key can come from the Mac instead of the watch keyboard: install-key.sh drops it into this
//  app's own folder on the watch (Library/Caches/import-key.txt) over the developer connection. At
//  launch, and each time the app comes on screen, it is moved into the Keychain and the file is
//  deleted, so it never stays on disk.
//

import Foundation

nonisolated enum KeyImport {
    static let fileName = "import-key.txt"

    private static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
    }

    /// True when a key was found and saved.
    @discardableResult
    static func run() -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        try? FileManager.default.removeItem(at: url)
        let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        return GrokKeyStore.save(key)
    }
}
