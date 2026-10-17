import Foundation

public enum EditorText {
    private static func paragraphRendering(_ text: String) -> String {
        let unix = text.replacingOccurrences(of: "\r\n", with: "\n")
        // A rich-text composer may expose paragraph breaks as a single AX newline after paste.
        // Preserve leading/trailing whitespace and every non-newline character exactly.
        return unix.replacingOccurrences(of: "(?<=[^\n])\n{2,}(?=[^\n])", with: "\n", options: .regularExpression)
    }
    /// Compare a model response with its input. Do not discard internal paragraph edits.
    public static func matchesUnchanged(_ original: String, requested: String) -> Bool {
        let before = original.replacingOccurrences(of: "\r\n", with: "\n")
        let after = requested.replacingOccurrences(of: "\r\n", with: "\n")
        return before == after || before == after + "\n"
    }
    /// Rendering acknowledgment only. Pre-write draft and restore-conflict guards remain exact.
    public static func matchesRendered(_ rendered: String, requested: String) -> Bool {
        let actual = paragraphRendering(rendered)
        let desired = paragraphRendering(requested)
        return actual == desired || actual == desired + "\n"
    }
}
