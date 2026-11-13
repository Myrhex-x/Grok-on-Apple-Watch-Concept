//
//  Dictation.swift
//  GrokWatch
//
//  Straight to dictation in one tap. SwiftUI's TextFieldLink opens the input screen first (keyboard,
//  Scribble, the dictation button); WatchKit's text input controller, given no suggestions and plain
//  text, starts listening at once. It needs a visible interface controller; when there is none the
//  app falls back to TextFieldLink.
//

import WatchKit

enum Dictation {
    static var isAvailable: Bool {
        WKApplication.shared().visibleInterfaceController != nil
    }

    /// Opens dictation and hands back what was said (nothing when cancelled).
    @discardableResult
    static func start(_ completion: @escaping (String) -> Void) -> Bool {
        guard let controller = WKApplication.shared().visibleInterfaceController else { return false }
        controller.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            guard let text = results?.compactMap({ $0 as? String }).first(where: { !$0.isEmpty }) else { return }
            DispatchQueue.main.async { completion(text) }
        }
        return true
    }
}
