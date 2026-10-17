import OptimizerCore

struct EditorCompatibilityTests {
    func testSupportedTargetsDoNotExpandToBrowsersOrUnrelatedApps() {
        XCTAssertEqual(EditorApplication.resolve(front: "com.openai.codex", remembered: nil, helper: "helper"), .codex)
        XCTAssertEqual(EditorApplication.resolve(front: "com.anthropic.claudefordesktop", remembered: nil, helper: "helper"), .claude)
        XCTAssertEqual(EditorApplication.resolve(front: "com.google.Chrome", remembered: "com.openai.codex", helper: "helper"), nil)
    }
    func testHelperActivationKeepsLastTargetWithoutGuessingOne() {
        XCTAssertEqual(EditorApplication.resolve(front: "helper", remembered: "com.anthropic.claudefordesktop", helper: "helper"), .claude)
        XCTAssertEqual(EditorApplication.resolve(front: "helper", remembered: "com.openai.codex", helper: "helper"), .codex)
        XCTAssertEqual(EditorApplication.resolve(front: "helper", remembered: nil, helper: "helper"), nil)
        XCTAssertEqual(EditorApplication.resolve(front: "helper", remembered: "com.apple.finder", helper: "helper"), nil)
        XCTAssertEqual(EditorApplication.resolve(front: nil, remembered: "com.openai.codex", helper: nil), nil)
    }
    func testUnidentifiedAndGenericEditorsCannotBeReattached() {
        for signature in ["", "AXTextArea|||", "AXTextArea|提示词|", "AXTextArea|id="] {
            let anchor = TextEditorAnchor(text: "同样的草稿", signature: signature, windowTitle: "same window")
            XCTAssertFalse(EditorContinuity.canReacquire(anchor, anchor))
        }
    }
    func testRebuiltEditorKeepsTransactionOnlyWhenAnchorIsUnchanged() {
        let before = TextEditorAnchor(text: "帮我写周报\n不虚构数据", signature: "AXTextArea|id=prompt-editor", windowTitle: "chat A")
        XCTAssertTrue(EditorContinuity.canReacquire(before, .init(text: "帮我写周报\n不虚构数据", signature: "AXTextArea|id=prompt-editor", windowTitle: "chat A")))
        for other in [TextEditorAnchor(text: "新要求", signature: "AXTextArea|id=prompt-editor", windowTitle: "chat A"),
                      .init(text: "帮我写周报\n不虚构数据", signature: "AXTextArea|id=search-editor", windowTitle: "chat A"),
                      .init(text: "帮我写周报\n不虚构数据", signature: "AXTextArea|id=prompt-editor", windowTitle: "chat B")] {
            XCTAssertFalse(EditorContinuity.canReacquire(before, other))
        }
    }
}
