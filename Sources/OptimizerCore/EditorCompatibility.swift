import Foundation

public enum EditorApplication: String {
    case codex = "com.openai.codex"
    case claude = "com.anthropic.claudefordesktop"
    public var name: String { self == .codex ? "Codex" : "Claude" }
    /// A helper click can activate our own UI; it must not change the user's last supported target.
    public static func resolve(front: String?, remembered: String?, helper: String?) -> EditorApplication? {
        if let front, let app = Self(rawValue: front) { return app }
        guard let front, let helper, front == helper, let remembered else { return nil }
        return Self(rawValue: remembered)
    }
}

public struct TextEditorAnchor {
    public let text: String
    public let signature: String
    public let windowTitle: String
    public init(text: String, signature: String, windowTitle: String) {
        self.text = text; self.signature = signature; self.windowTitle = windowTitle
    }
}

public enum EditorContinuity {
    /// Call only after verifying the same process and AX window. Rebuilds may change the AX node only.
    public static func canReacquire(_ previous: TextEditorAnchor, _ current: TextEditorAnchor) -> Bool {
        let prefix = "AXTextArea|id="
        return previous.signature.hasPrefix(prefix) && previous.signature.count > prefix.count &&
            previous.signature == current.signature &&
            previous.windowTitle == current.windowTitle && previous.text == current.text
    }
}
