import Foundation
import OptimizerCore

struct SessionTests {
    let original = DraftSnapshot(targetID: "window1/editor1/chatA", text: "请帮我写一份周报\n保留 $& 和 $$")
    let enhanced = "请根据我提供的工作记录整理周报，包含完成事项、问题和下周安排；保留 $& 和 $$，不要虚构数据。"

    func appliedSession() throws -> OptimizationSession {
        let session = OptimizationSession()
        let id = try session.begin(original)
        let edit = try session.accept(id: id, result: enhanced, current: original)
        try session.recordApplied(edit, observed: .init(targetID: original.targetID, text: enhanced))
        return session
    }

    func testOptimizationProducesOneReplaceAndRestorePreservesExactOriginal() throws {
        let s = try appliedSession()
        let undo = try s.restore(current: .init(targetID: original.targetID, text: enhanced))
        XCTAssertEqual(undo.expected, enhanced)
        XCTAssertEqual(undo.replacement, "请帮我写一份周报\n保留 $& 和 $$")
    }
    func testUserEditsDuringGenerationAreNotOverwritten() throws {
        let s = OptimizationSession(); let id = try s.begin(original)
        XCTAssertThrowsError(try s.accept(id: id, result: enhanced, current: .init(targetID: original.targetID, text: "我已改稿")))
    }
    func testSwitchingChatIsNotOverwrittenEvenWhenDraftTextMatches() throws {
        let s = OptimizationSession(); let id = try s.begin(original)
        XCTAssertThrowsError(try s.accept(id: id, result: enhanced, current: .init(targetID: "window1/editor1/chatB", text: original.text)))
    }
    func testCancellationRejectsLateResult() throws {
        let s = OptimizationSession(); let id = try s.begin(original); s.cancel()
        XCTAssertThrowsError(try s.accept(id: id, result: enhanced, current: original))
    }
    func testOldResultCannotReplaceNewRequest() throws {
        let s = OptimizationSession(); let old = try s.begin(original); let latest = try s.begin(original)
        XCTAssertThrowsError(try s.accept(id: old, result: "过期", current: original))
        let edit = try s.accept(id: latest, result: enhanced, current: original)
        XCTAssertEqual(edit.replacement, enhanced)
    }
    func testRestoreDoesNotOverwriteLaterTypingOrOtherEditor() throws {
        let s = try appliedSession()
        XCTAssertThrowsError(try s.restore(current: .init(targetID: original.targetID, text: enhanced + " 新增要求")))
        XCTAssertThrowsError(try s.restore(current: .init(targetID: "other", text: enhanced)))
    }
    func testFailedPasteDoesNotClaimRestoreIsAvailable() throws {
        let s = OptimizationSession(); let id = try s.begin(original)
        let edit = try s.accept(id: id, result: enhanced, current: original)
        XCTAssertThrowsError(try s.recordApplied(edit, observed: original))
        XCTAssertFalse(s.canRestore(current: original))
    }
    func testCancelBetweenResultAndApplyPreventsCommit() throws {
        let s = OptimizationSession(); let id = try s.begin(original)
        let edit = try s.accept(id: id, result: enhanced, current: original); s.cancel()
        XCTAssertThrowsError(try s.recordApplied(edit, observed: .init(targetID: original.targetID, text: enhanced)))
    }
    func testBlankAndOversizedInputsCannotStart() {
        let s = OptimizationSession()
        for text in ["", " \n\t", String(repeating: "字", count: 30001)] {
            XCTAssertThrowsError(try s.begin(.init(targetID: "a", text: text)))
        }
    }
    func testEmptyOutputDoesNotReplaceDraft() throws {
        let s = OptimizationSession(); let id = try s.begin(original)
        XCTAssertThrowsError(try s.accept(id: id, result: " \n", current: original))
    }
    func testRestoreRequiresVerifiedApplyAndCannotRepeatAfterAcknowledgment() throws {
        let s = try appliedSession()
        let current = DraftSnapshot(targetID: original.targetID, text: enhanced)
        XCTAssertTrue(s.canRestore(current: current))
        let undo = try s.restore(current: current)
        try s.recordApplied(undo, observed: original)
        XCTAssertFalse(s.canRestore(current: current))
    }
    func testInvalidResponseIsRejectedAndUnicodeIsPreserved() throws {
        XCTAssertEqual(try OptimizerResponse.decode(Data("{\"optimized\":\"优化：保留 $&、$$ 和中文\\n第二行\"}".utf8)), "优化：保留 $&、$$ 和中文\n第二行")
        for json in ["{}", "{\"optimized\":\" \"}", "not json"] {
            XCTAssertThrowsError(try OptimizerResponse.decode(Data(json.utf8)))
        }
    }
}

extension SessionTests {
    func testRenderedNewlineDoesNotLoseRestoreBackup() throws {
        let s = OptimizationSession(); let id = try s.begin(original)
        let edit = try s.accept(id: id, result: enhanced, current: original)
        let rendered = DraftSnapshot(targetID: original.targetID, text: enhanced + "\n")
        try s.recordApplied(edit, observed: rendered)
        XCTAssertTrue(s.canRestore(current: rendered))
        let undo = try s.restore(current: rendered)
        XCTAssertEqual(undo.replacement, original.text)
        try s.recordApplied(undo, observed: .init(targetID: original.targetID, text: original.text + "\n"))
        XCTAssertFalse(s.canRestore(current: rendered))
    }
    func testLineEndingNormalizationPreservesOriginalForRestore() throws {
        let s = OptimizationSession()
        let before = DraftSnapshot(targetID: "editor", text: "原始\r\n原文  ")
        let id = try s.begin(before)
        let edit = try s.accept(id: id, result: "第一行\n第二行", current: before)
        let actual = DraftSnapshot(targetID: "editor", text: "第一行\r\n第二行\r\n")
        try s.recordApplied(edit, observed: actual)
        let undo = try s.restore(current: actual)
        XCTAssertEqual(undo.expected, "第一行\r\n第二行\r\n")
        XCTAssertEqual(undo.replacement, "原始\r\n原文  ")
    }
    func testNormalizationNeverAcceptsUserAddedTextOrMeaningfulSpaces() throws {
        for changed in [enhanced + "\n新增要求", " " + enhanced, enhanced + "  ", enhanced + "\n\n"] {
            let s = OptimizationSession(); let id = try s.begin(original)
            let edit = try s.accept(id: id, result: enhanced, current: original)
            XCTAssertThrowsError(try s.recordApplied(edit, observed: .init(targetID: original.targetID, text: changed)))
        }
    }
}


extension SessionTests {
    func testUnchangedRetryPreservesPreviousOriginal() throws {
        let s = try appliedSession()
        let current = DraftSnapshot(targetID: original.targetID, text: enhanced)
        let id = try s.begin(current)
        let edit = try s.accept(id: id, result: enhanced, current: current)
        try s.recordApplied(edit, observed: current)
        XCTAssertEqual(try s.restore(current: current).replacement, original.text)
    }
    func testCancelledOrFailedRetryPreservesPreviousOriginal() throws {
        for failed in [false, true] {
            let s = try appliedSession()
            let current = DraftSnapshot(targetID: original.targetID, text: enhanced)
            let id = try s.begin(current)
            if failed {
                let edit = try s.accept(id: id, result: "另一个结果", current: current)
                XCTAssertThrowsError(try s.recordApplied(edit, observed: current))
            } else { s.cancel() }
            XCTAssertEqual(try s.restore(current: current).replacement, original.text)
        }
    }
    func testFirstUnchangedOptimizationDoesNotInventBackup() throws {
        let s = OptimizationSession()
        let current = DraftSnapshot(targetID: original.targetID, text: enhanced)
        let id = try s.begin(current)
        let edit = try s.accept(id: id, result: enhanced, current: current)
        try s.recordApplied(edit, observed: current)
        XCTAssertFalse(s.hasBackup)
    }
}


extension SessionTests {
    func testUnchangedRetryAcknowledgesChangedRenderingWithoutLosingOriginal() throws {
        let s = OptimizationSession()
        let id = try s.begin(original)
        let edit = try s.accept(id: id, result: enhanced, current: original)
        let rendered = DraftSnapshot(targetID: original.targetID, text: enhanced + "\n")
        try s.recordApplied(edit, observed: rendered)
        let retryID = try s.begin(rendered)
        let retry = try s.accept(id: retryID, result: enhanced, current: rendered)
        let current = DraftSnapshot(targetID: original.targetID, text: enhanced)
        try s.recordApplied(retry, observed: current)
        XCTAssertEqual(try s.restore(current: current).replacement, original.text)
    }
}


extension SessionTests {
    func testRichTextParagraphRenderingAcknowledgesPasteAndKeepsExactBackup() throws {
        let session = OptimizationSession()
        let original = DraftSnapshot(targetID: "claude-composer", text: "原文\n保留限制")
        let id = try session.begin(original)
        let edit = try session.accept(id: id, result: "目标\n\n- 记录一\n- 记录二\n\n约束", current: original)
        let actual = DraftSnapshot(targetID: "claude-composer", text: "目标\n- 记录一\n- 记录二\n约束")
        try session.recordApplied(edit, observed: actual)
        XCTAssertTrue(session.canRestore(current: actual))
        XCTAssertEqual(try session.restore(current: actual).replacement, "原文\n保留限制")
    }
    func testParagraphNormalizationNeverHidesLostWordsOrSingleLineBreaks() {
        XCTAssertFalse(EditorText.matchesRendered("目标约束", requested: "目标\n约束"))
        XCTAssertFalse(EditorText.matchesRendered("目标\n约束被删", requested: "目标\n\n约束完整"))
        XCTAssertFalse(EditorText.matchesRendered(" 目标\n约束", requested: "目标\n\n约束"))
        XCTAssertFalse(EditorText.matchesRendered("目标\n约束\n\n", requested: "目标\n\n约束"))
    }
}


extension SessionTests {
    func testModelChangingOnlyInternalBlankLinesStillCreatesRecovery() throws {
        let session = OptimizationSession()
        let original = DraftSnapshot(targetID: "editor", text: "A\n\nB")
        let id = try session.begin(original)
        let edit = try session.accept(id: id, result: "A\nB", current: original)
        let actual = DraftSnapshot(targetID: "editor", text: "A\nB")
        let changed = try session.recordApplied(edit, observed: actual)
        XCTAssertTrue(changed)
        XCTAssertEqual(try session.restore(current: actual).replacement, "A\n\nB")
    }
}
