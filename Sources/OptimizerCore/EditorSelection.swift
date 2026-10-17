import Foundation

public enum EditorSelection {
    /// Check the actual acknowledged selection, not whether the AX request was merely accepted.
    public static func coversDraft(_ draft: String, location: Int, length: Int, selectedText: String?) -> Bool {
        guard location == 0, length >= 0 else { return false }
        if let selectedText {
            return length == selectedText.utf16.count && EditorText.matchesRendered(draft, requested: selectedText)
        }
        return length == draft.utf16.count
    }
}
