import AppKit
import ApplicationServices
import OptimizerCore

struct EditorFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct EditorTarget {
    let editor: AXUIElement
    let window: AXUIElement
    let pid: pid_t
    let title: String
    let id: String
    let snapshot: DraftSnapshot
    let signature: String
    let scope: AXUIElement?
}

/// All entry points run on the main thread. Never searches other apps for an editor.
@MainActor
final class EditorAccess: EditorGateway {
    var reportStep: ((String, [String: Int]) -> Void)?
    private var binding: EditorTarget?
    private var recoveryBinding: EditorTarget?
    private var rememberedApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var collectFocusDiagnostics = false
    init() {
        if let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier, EditorApplication(rawValue: id) != nil { rememberedApp = front }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, EditorApplication(rawValue: id) != nil else { return }
            Task { @MainActor [weak self] in self?.rememberedApp = app }
        }
    }
    deinit { if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) } }
    func prepareForOptimization() async throws {
        let front = NSWorkspace.shared.frontmostApplication
        if let id = front?.bundleIdentifier, EditorApplication(rawValue: id) != nil { rememberedApp = front; return }
        guard front?.bundleIdentifier == Bundle.main.bundleIdentifier, let target = rememberedApp, !target.isTerminated,
              let id = target.bundleIdentifier, EditorApplication(rawValue: id) != nil else {
            throw EditorFailure(message: "请先点中 Codex 或 Claude 的草稿，再点击优化。")
        }
        target.activate(options: [.activateIgnoringOtherApps])
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { return }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw EditorFailure(message: "未能切回原应用，请点中草稿后重试。")
    }
    var isTrusted: Bool { AXIsProcessTrusted() }
    var targetIsFrontmost: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              EditorApplication(rawValue: id) != nil else { return false }
        rememberedApp = app; return true
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    private func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(e, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func value(_ e: AXUIElement) -> String? { attribute(e, kAXValueAttribute) as? String }
    private func focused() throws -> (AXUIElement, AXUIElement, pid_t, String) {
        guard isTrusted else { throw EditorFailure(message: "请先在系统设置中允许本应用使用辅助功能。") }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let supported = EditorApplication.resolve(front: front.bundleIdentifier, remembered: rememberedApp?.bundleIdentifier, helper: Bundle.main.bundleIdentifier) else {
            throw EditorFailure(message: "请在 Codex 或 Claude 桌面版点中要优化的草稿输入框。")
        }
        let app: NSRunningApplication
        if front.bundleIdentifier == supported.rawValue { app = front; rememberedApp = front }
        else if let last = rememberedApp, !last.isTerminated, last.bundleIdentifier == supported.rawValue { app = last }
        else { throw EditorFailure(message: "请先点中 Codex 或 Claude 的草稿，再点击优化。") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let focusedElement = element(root, kAXFocusedUIElementAttribute),
              let window = element(root, kAXFocusedWindowAttribute) else {
            throw EditorFailure(message: "暂时无法读取输入框，请保持目标草稿，稍后重试。")
        }
        var editor: AXUIElement? = focusedElement
        let role = attribute(focusedElement, kAXRoleAttribute) as? String ?? ""
        var owner: pid_t = 0; AXUIElementGetPid(focusedElement, &owner)
        if collectFocusDiagnostics {
            let codes = ["AXTextArea": 1, "AXTextField": 2, "AXGroup": 3, "AXStaticText": 4, "AXWebArea": 5, "AXButton": 6]
            reportStep?("focusedControl", ["roleCode": codes[role] ?? 0, "ownerMatches": owner == app.processIdentifier ? 1 : 0])
        }
        guard owner == app.processIdentifier else { throw OptimizerError.conflict }
        // Chromium may focus a text child within the actual editable text area.
        // Walk ancestors only, never search the window for an arbitrary editor.
        for _ in 0..<8 {
            guard let current = editor else { break }
            AXUIElementSetMessagingTimeout(current, 0.2)
            if attribute(current, kAXRoleAttribute) as? String == kAXTextAreaRole, value(current) != nil { break }
            editor = element(current, kAXParentAttribute)
        }
        guard let editor, attribute(editor, kAXRoleAttribute) as? String == kAXTextAreaRole, value(editor) != nil else {
            throw EditorFailure(message: "当前不是可读取的多行输入框，请点中 Codex 或 Claude 草稿区域。")
        }
        return (editor, window, app.processIdentifier, attribute(window, kAXTitleAttribute) as? String ?? "")
    }
    private func signature(_ editor: AXUIElement) -> String {
        guard let id = attribute(editor, kAXIdentifierAttribute) as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return "AXTextArea|id=" + id
    }
    private func scope(_ editor: AXUIElement) -> AXUIElement? {
        var node = element(editor, kAXParentAttribute)
        for _ in 0..<32 {
            guard let current = node else { return nil }
            AXUIElementSetMessagingTimeout(current, 0.1)
            if attribute(current, kAXRoleAttribute) as? String == "AXWebArea" { return current }
            node = element(current, kAXParentAttribute)
        }
        return nil
    }
    private func sameScope(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        guard let a, let b else { return false }; return CFEqual(a, b)
    }
    @discardableResult func bind() throws -> DraftSnapshot {
        collectFocusDiagnostics = true
        defer { collectFocusDiagnostics = false }
        let (editor, window, pid, title) = try focused()
        // Rebinding always invalidates every old transaction, even if AX reuses a node across chats.
        let id = UUID().uuidString
        let snapshot = DraftSnapshot(targetID: id, text: value(editor) ?? "")
        binding = EditorTarget(editor: editor, window: window, pid: pid, title: title, id: id, snapshot: snapshot, signature: signature(editor), scope: scope(editor))
        return snapshot
    }
    func unbind() { binding = nil }
    func current() throws -> DraftSnapshot {
        let (editor, window, pid, title) = try focused()
        if let recovery = recoveryBinding,
           pid == recovery.pid, CFEqual(editor, recovery.editor), CFEqual(window, recovery.window),
           binding == nil || !CFEqual(editor, binding!.editor) || !CFEqual(window, binding!.window) || pid != binding!.pid {
            binding = recovery
        }
        guard let b = binding else { throw EditorFailure(message: "请点中草稿，再点击“优化提示词”。") }
        guard pid == b.pid, CFEqual(window, b.window), let text = value(editor) else { throw OptimizerError.conflict }
        let sameNode = CFEqual(editor, b.editor)
        let candidateSignature = sameNode ? b.signature : signature(editor)
        let candidateScope = sameNode ? b.scope : scope(editor)
        if !sameNode {
            let old = TextEditorAnchor(text: b.snapshot.text, signature: b.signature, windowTitle: b.title)
            let new = TextEditorAnchor(text: text, signature: candidateSignature, windowTitle: title)
            guard sameScope(b.scope, candidateScope), EditorContinuity.canReacquire(old, new) else { throw OptimizerError.conflict }
        }
        let snapshot = DraftSnapshot(targetID: b.id, text: text)
        binding = EditorTarget(editor: editor, window: window, pid: pid, title: title, id: b.id, snapshot: snapshot, signature: candidateSignature, scope: candidateScope)
        return snapshot
    }
    func anchorFrame() -> CGRect? {
        guard isTrusted, targetIsFrontmost,
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let win = element(root, kAXFocusedWindowAttribute),
              let position = attribute(win, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(win, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    func rememberRecoveryTarget() { recoveryBinding = binding }
    /// Explicit optimize/restore actions only; polling never activates another application.
    private func focusTarget(_ b: EditorTarget) async throws {
        let front = NSWorkspace.shared.frontmostApplication
        guard let target = NSRunningApplication(processIdentifier: b.pid),
              let id = target.bundleIdentifier, EditorApplication(rawValue: id) != nil,
              front?.processIdentifier == b.pid || front?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw EditorFailure(message: "请回到原来的 Codex 或 Claude 草稿，再操作。")
        }
        rememberedApp = target
        if front?.processIdentifier != b.pid { target.activate(options: [.activateIgnoringOtherApps]) }
        _ = AXUIElementPerformAction(b.window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(b.editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        for _ in 0..<15 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == b.pid,
               let current = try? current(), current.targetID == b.id { return }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw EditorFailure(message: "未能找回原输入框。原文仍保留，可从菜单查看并复制。")
    }
    func focusBoundEditor() async throws {
        guard let b = recoveryBinding ?? binding else { throw OptimizerError.noBackup }
        binding = b; try await focusTarget(b)
    }
    /// Only Ctrl+Z compatibility: delegate to the focused editor's native Cmd+Z history.
    /// No activation, selection rewrite, or cross-window recovery here.
    func nativeUndo() async throws -> DraftSnapshot {
        let before = try current()
        guard let b = binding, NSWorkspace.shared.frontmostApplication?.processIdentifier == b.pid,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: false) else { throw OptimizerError.conflict }
        guard try current() == before else { throw OptimizerError.conflict }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(b.pid); up.postToPid(b.pid)
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 40_000_000)
            let observed = try current()
            if observed != before { return observed }
        }
        throw OptimizerError.pasteFailed
    }
    private func acknowledgeWrite(_ edit: EditProposal, previous b: EditorTarget) throws -> EditorTarget {
        let (editor, window, pid, title) = try focused()
        let text = value(editor)
        let nodeMatches = CFEqual(editor, b.editor)
        reportStep?("verifyingPaste", ["frontMatches": NSWorkspace.shared.frontmostApplication?.processIdentifier == b.pid ? 1 : 0,
                                       "processMatches": pid == b.pid ? 1 : 0, "windowMatches": CFEqual(window, b.window) ? 1 : 0,
                                       "nodeMatches": nodeMatches ? 1 : 0, "originalNodeReadable": value(b.editor) == nil ? 0 : 1,
                                       "actualUTF16": text?.utf16.count ?? -1, "requestedUTF16": edit.replacement.utf16.count,
                                       "renderedMatches": text.map { EditorText.matchesRendered($0, requested: edit.replacement) } == true ? 1 : 0,
                                       "hasStrongID": signature(editor).isEmpty ? 0 : 1,
                                       "actualLF": text?.filter { $0 == "\n" }.count ?? -1,
                                       "requestedLF": edit.replacement.filter { $0 == "\n" }.count])
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == b.pid,
              pid == b.pid, CFEqual(window, b.window),
              let text, EditorText.matchesRendered(text, requested: edit.replacement) else { throw OptimizerError.pasteFailed }
        let sameNode = CFEqual(editor, b.editor)
        let candidateSignature = sameNode ? b.signature : signature(editor)
        let candidateScope = sameNode ? b.scope : scope(editor)
        if !sameNode {
            let old = TextEditorAnchor(text: text, signature: b.signature, windowTitle: b.title)
            let new = TextEditorAnchor(text: text, signature: candidateSignature, windowTitle: title)
            guard sameScope(b.scope, candidateScope), EditorContinuity.canReacquire(old, new) else { throw OptimizerError.pasteFailed }
        }
        let snapshot = DraftSnapshot(targetID: b.id, text: text)
        return EditorTarget(editor: editor, window: window, pid: pid, title: title, id: b.id, snapshot: snapshot, signature: candidateSignature, scope: candidateScope)
    }
    func replace(_ edit: EditProposal) async throws -> DraftSnapshot {
        let before = try current()
        guard before.targetID == edit.targetID, before.text == edit.expected, let target = binding else { throw OptimizerError.conflict }
        guard edit.replacement != edit.expected else { return before }
        try await focusTarget(target)
        guard try current() == before, let b = binding else { throw OptimizerError.conflict }
        // Select through AX rather than globally issuing Cmd+A. If selection cannot be verified, never paste.
        var range = CFRange(location: 0, length: edit.expected.utf16.count)
        guard let selection = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(b.editor, kAXSelectedTextRangeAttribute as CFString, selection) == .success else {
            throw EditorFailure(message: "输入框不支持安全选择全文，未替换草稿。")
        }
        reportStep?("selectionRequested", ["expectedUTF16": range.length])
        let selectionDeadline = Date().addingTimeInterval(1)
        var confirmed = false
        while Date() < selectionDeadline {
            var actual = CFRange()
            if let observedRange = attribute(b.editor, kAXSelectedTextRangeAttribute),
               CFGetTypeID(observedRange) == AXValueGetTypeID(), AXValueGetValue(observedRange as! AXValue, .cfRange, &actual) {
                let selected = attribute(b.editor, kAXSelectedTextAttribute) as? String
                reportStep?("checkingSelection", ["expectedUTF16": range.length, "selectedLocation": actual.location,
                                                    "selectedLength": actual.length, "selectedTextUTF16": selected?.utf16.count ?? -1,
                                                    "draftLF": before.text.filter { $0 == "\n" }.count,
                                                    "selectedLF": selected?.filter { $0 == "\n" }.count ?? -1,
                                                    "selectedMatchesDraft": selected.map { EditorText.matchesRendered(before.text, requested: $0) } == true ? 1 : 0])
                if EditorSelection.coversDraft(before.text, location: actual.location, length: actual.length, selectedText: selected) {
                    guard try current() == before else { throw OptimizerError.conflict }
                    confirmed = true; break
                }
            }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        guard confirmed else { throw EditorFailure(message: "未能确认完整选区，未回填；原文仍保留。") }
        reportStep?("selectionVerified", ["expectedUTF16": range.length])
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }; return (type, data)
            }
        }
        pasteboard.clearContents()
        guard pasteboard.setString(edit.replacement, forType: .string) else { throw OptimizerError.pasteFailed }
        let change = pasteboard.changeCount
        defer {
            // A copy performed by the user during the paste wins over our saved clipboard.
            if pasteboard.changeCount == change {
                pasteboard.clearContents()
                let items = saved.map { values -> NSPasteboardItem in
                    let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }
        reportStep?("checkingBeforePaste", [:])
        guard try current() == before else { throw OptimizerError.conflict }
        // Native paste gives the editor a chance to create its normal undo transaction.
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { throw OptimizerError.pasteFailed }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(b.pid); up.postToPid(b.pid)
        reportStep?("pastePosted", [:])
        // The web editor can replace its accessibility node while reconciling a paste.
        // Reacquire only after our own write, within the exact same window and with matching content.
        let deadline = Date().addingTimeInterval(2)
        var verified: EditorTarget?
        var stableSince: Date?
        while Date() < deadline {
            if let observed = try? acknowledgeWrite(edit, previous: b) {
                if verified?.snapshot == observed.snapshot, let since = stableSince, Date().timeIntervalSince(since) >= 0.2 {
                    binding = observed; return observed.snapshot
                }
                if verified?.snapshot != observed.snapshot { stableSince = Date() }
                verified = observed
            } else { verified = nil; stableSince = nil }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw OptimizerError.pasteFailed
    }
}
