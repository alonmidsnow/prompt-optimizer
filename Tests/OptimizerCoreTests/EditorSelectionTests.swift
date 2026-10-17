import OptimizerCore

struct EditorSelectionTests {
    func testSyntheticParagraphNewlineDoesNotRejectAWholeEditorSelection() {
        XCTAssertTrue(EditorSelection.coversDraft("中文🙂\n", location: 0, length: 4, selectedText: "中文🙂"))
        XCTAssertTrue(EditorSelection.coversDraft("A\r\nB", location: 0, length: 3, selectedText: "A\nB"))
    }
    func testPartialSelectionOrWrongSelectedTextIsNeverAccepted() {
        XCTAssertFalse(EditorSelection.coversDraft("ABCDE", location: 0, length: 4, selectedText: "ABCD"))
        XCTAssertFalse(EditorSelection.coversDraft("ABCDE", location: 1, length: 5, selectedText: "ABCDE"))
        XCTAssertFalse(EditorSelection.coversDraft("ABCDE", location: 0, length: 5, selectedText: "WRONG"))
        XCTAssertFalse(EditorSelection.coversDraft("ABCDE\n", location: 0, length: 5, selectedText: nil))
        XCTAssertFalse(EditorSelection.coversDraft("ABCDE  ", location: 0, length: 5, selectedText: "ABCDE"))
    }
}
