import AppKit
import OptimizerCore

@MainActor
protocol EditorGateway: AnyObject {
    var isTrusted: Bool { get }
    var targetIsFrontmost: Bool { get }
    func requestPermission()
    func prepareForOptimization() async throws
    func bind() throws -> DraftSnapshot
    func current() throws -> DraftSnapshot
    func anchorFrame() -> CGRect?
    func focusBoundEditor() async throws
    func rememberRecoveryTarget()
    func replace(_ edit: EditProposal) async throws -> DraftSnapshot
    func nativeUndo() async throws -> DraftSnapshot
}

extension EditorGateway {
    func prepareForOptimization() async throws {}
}

/// Isolated practice editor: it never reads Codex, sends a model request, or requires a system grant.
@MainActor
final class PracticeEditor: EditorGateway {
    let window: NSWindow
    let text: NSTextView
    let secondText: NSTextView
    private var bound: (id: String, editor: NSTextView)?
    private var recovery: (id: String, editor: NSTextView)?
    var isTrusted: Bool { true }
    var targetIsFrontmost: Bool { window.isVisible }
    init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "提示词助手 · 练习编辑器（模拟优化，不消耗额度）"
        window.isReleasedWhenClosed = false
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]; window.contentView = root
        let label = NSTextField(wrappingLabelWithString: "练习模式 · 仅操作下方测试文字，不访问 Codex。\n点中下方输入框 → 优化提示词 → ⌘Z / Ctrl+Z 原生撤销。")
        label.font = .systemFont(ofSize: 13); label.frame = NSRect(x: 22, y: 310, width: 596, height: 64)
        label.autoresizingMask = [.width, .minYMargin]; root.addSubview(label)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 600, height: 282))
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        text = NSTextView(frame: scroll.bounds)
        text.isRichText = false; text.allowsUndo = true
        text.font = .systemFont(ofSize: 17); text.textContainerInset = NSSize(width: 18, height: 18)
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.string = "帮我整理周报\n只用我提供的真实工作记录，不虚构数据。"
        text.setAccessibilityLabel("练习草稿输入框")
        scroll.documentView = text; root.addSubview(scroll)
        let secondScroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 600, height: 100))
        secondScroll.hasVerticalScroller = true
        secondText = NSTextView(frame: secondScroll.bounds)
        secondText.isRichText = false; secondText.allowsUndo = true
        secondText.font = .systemFont(ofSize: 15); secondText.textContainerInset = NSSize(width: 18, height: 18)
        secondText.setAccessibilityLabel("第二练习输入框（空白，用于切换目标）")
        secondScroll.documentView = secondText; root.addSubview(secondScroll)
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(text)
        NSApp.activate(ignoringOtherApps: true)
    }
    func mount(_ widget: OrbWidget) {
        window.setContentSize(NSSize(width: 1010, height: 520))
        if let root = window.contentView {
            for view in root.subviews {
                if let scroll = view as? NSScrollView {
                    scroll.autoresizingMask = []
                    scroll.frame = NSRect(x: 20, y: scroll.documentView === text ? 202 : 20, width: 600, height: scroll.documentView === text ? 220 : 170)
                }
                else if let label = view as? NSTextField { label.frame = NSRect(x: 22, y: 438, width: 596, height: 64) }
            }
            widget.embed(in: root)
        }
        window.center()
    }
    func requestPermission() {}
    func bind() throws -> DraftSnapshot {
        guard let editor = window.firstResponder as? NSTextView, editor === text || editor === secondText else { throw EditorFailure(message: "请先点击练习编辑器。") }
        bound = (UUID().uuidString, editor); return try current()
    }
    func current() throws -> DraftSnapshot {
        if let recovery, window.firstResponder === recovery.editor,
           bound == nil || window.firstResponder !== bound?.editor { bound = recovery }
        guard let bound else { throw EditorFailure(message: "请点击优化自动识别练习输入框。") }
        guard window.firstResponder === bound.editor else { throw OptimizerError.conflict }
        return DraftSnapshot(targetID: bound.id, text: bound.editor.string)
    }
    func anchorFrame() -> CGRect? { nil }
    func rememberRecoveryTarget() { recovery = bound }
    func focusBoundEditor() async throws {
        guard let target = recovery ?? bound else { throw OptimizerError.noBackup }
        bound = target; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(target.editor)
    }
    func replace(_ edit: EditProposal) async throws -> DraftSnapshot {
        let before = try current()
        guard before.targetID == edit.targetID, before.text == edit.expected else { throw OptimizerError.conflict }
        guard let text = bound?.editor else { throw OptimizerError.conflict }
        // A native NSTextView transaction, not a state-only fake: exercises the controller with real text undo.
        text.breakUndoCoalescing()
        text.insertText(edit.replacement, replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        text.breakUndoCoalescing()
        return try current()
    }
    func simulatedOptimization(_ original: String) async throws -> String {
        try await Task.sleep(nanoseconds: 600_000_000)
        return "请基于我提供的材料完成以下任务，保留原有事实、范围与约束，缺失信息请明确指出，输出可直接使用的结果：\n\n" + original
    }
    func nativeUndo() async throws -> DraftSnapshot {
        _ = try current()
        guard let text = bound?.editor else { throw OptimizerError.conflict }
        text.undoManager?.undo()
        return try current()
    }
}
