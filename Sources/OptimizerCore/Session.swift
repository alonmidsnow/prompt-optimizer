import Foundation

public struct DraftSnapshot: Equatable {
    public let targetID: String
    public let text: String
    public init(targetID: String, text: String) { self.targetID = targetID; self.text = text }
}
public struct EditProposal {
    public let id: UUID
    public let targetID: String
    public let expected: String
    public let replacement: String
    let isRestore: Bool
}
public enum OptimizerError: LocalizedError {
    case emptyInput, tooLong, stale, conflict, emptyResult, invalidResponse, noBackup, pasteFailed, cliMissing, cliFailed, timeout
    public var errorDescription: String? {
        switch self {
        case .emptyInput: return "请先在 Codex 或 Claude 草稿框写下需求。"
        case .tooLong: return "草稿超过 30000 字符，请缩短后再优化。"
        case .stale: return "请求已取消或已过期，未应用结果。"
        case .conflict: return "草稿或目标窗口已改变，为保护新内容，未执行替换。"
        case .emptyResult: return "模型没有返回有效优化稿，原文未改变。"
        case .invalidResponse: return "模型响应格式无效，原文未改变。"
        case .noBackup: return "当前没有可恢复的优化稿。"
        case .pasteFailed: return "未能确认输入框替换成功；已停止，请检查草稿。"
        case .cliMissing: return "未找到 Codex CLI。请安装并登录，或在 config.json 切换为模型 API。"
        case .cliFailed: return "Codex 调用失败，原文未改变。请检查 CLI 登录、网络和额度。"
        case .timeout: return "优化请求超时，已停止，未继续回填。"
        }
    }
}

/// Main-thread owned transaction state. Every write must also be guarded by the editor adapter.
public final class OptimizationSession {
    private var active: (id: UUID, before: DraftSnapshot)?
    private var pending: EditProposal?
    private var backup: (targetID: String, before: String, after: String)?
    public init() {}
    public func begin(_ snapshot: DraftSnapshot) throws -> UUID {
        guard !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OptimizerError.emptyInput }
        guard snapshot.text.count <= 30000 else { throw OptimizerError.tooLong }
        let id = UUID(); active = (id, snapshot); pending = nil
        return id
    }
    public func accept(id: UUID, result: String, current: DraftSnapshot) throws -> EditProposal {
        guard let request = active, request.id == id else { throw OptimizerError.stale }
        active = nil
        guard current == request.before else { throw OptimizerError.conflict }
        let clean = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw OptimizerError.emptyResult }
        guard clean.count <= 60000 else { throw OptimizerError.invalidResponse }
        let edit = EditProposal(id: UUID(), targetID: current.targetID, expected: current.text, replacement: clean, isRestore: false)
        pending = edit
        return edit
    }
    @discardableResult
    public func recordApplied(_ edit: EditProposal, observed: DraftSnapshot) throws -> Bool {
        guard pending?.id == edit.id else { throw OptimizerError.stale }
        pending = nil
        guard observed.targetID == edit.targetID, EditorText.matchesRendered(observed.text, requested: edit.replacement) else { throw OptimizerError.pasteFailed }
        let changed = !EditorText.matchesUnchanged(edit.expected, requested: edit.replacement)
        if edit.isRestore { backup = nil }
        else if changed { backup = (edit.targetID, edit.expected, observed.text) }
        else if let b = backup, b.targetID == edit.targetID, b.after == edit.expected {
            // Editors can change their synthetic trailing newline between native pastes.
            // Refresh only the acknowledged rendering, never the saved original or a stale target.
            backup = (b.targetID, b.before, observed.text)
        }
        return changed
    }
    public var hasBackup: Bool { backup != nil }
    public func cancel() { active = nil; pending = nil }
    public func discard() { cancel(); backup = nil }
    public func restore(current: DraftSnapshot) throws -> EditProposal {
        guard let b = backup else { throw OptimizerError.noBackup }
        guard current.targetID == b.targetID, current.text == b.after else { throw OptimizerError.conflict }
        let edit = EditProposal(id: UUID(), targetID: b.targetID, expected: b.after, replacement: b.before, isRestore: true)
        active = nil; pending = edit
        return edit
    }
    public func canRestore(current: DraftSnapshot) -> Bool {
        guard let b = backup else { return false }
        return b.targetID == current.targetID && b.after == current.text
    }
}
public enum OptimizerResponse {
    private struct Payload: Decodable { let optimized: String }
    public static func decode(_ data: Data) throws -> String {
        guard data.count <= 256000, let p = try? JSONDecoder().decode(Payload.self, from: data) else { throw OptimizerError.invalidResponse }
        let text = p.optimized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OptimizerError.emptyResult }
        guard text.count <= 60000 else { throw OptimizerError.invalidResponse }
        return text
    }
}
