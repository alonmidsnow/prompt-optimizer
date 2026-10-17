import Foundation
var failures = 0
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    do { let value = try lhs(); if value != rhs { failures += 1; print("FAIL \(file):\(line): values differ") } }
    catch { failures += 1; print("FAIL \(file):\(line): unexpected error \(error)") }
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line): expected true") }
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { XCTAssertTrue(!value, file: file, line: line) }
func XCTAssertThrowsError<T>(_ body: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try body(); failures += 1; print("FAIL \(file):\(line): expected rejection") } catch {}
}
let installation = InstallationTests()
let backend = BackendTests()
let suite = SessionTests()
let compatibility = EditorCompatibilityTests()
let selection = EditorSelectionTests()
let tests: [(String, () throws -> Void)] = [
    ("drag install locations and rejected copies", installation.testSystemAndUserApplicationsAreAcceptedButDownloadsAreNot),
    ("private config and explicit backend reload", backend.testMissingConfigCreatesPrivateDefaultAndReloadsUserChoice),
    ("invalid API config fails closed", backend.testUnsafeOrIncompleteAPIConfigurationFailsClosed),
    ("API request preserves literal draft", backend.testRequestKeepsDraftAsDataAndDoesNotEnableTools),
    ("API response safety", backend.testTruncatedRefusedAndInvalidAPIResponsesNeverBecomeDrafts),
    ("web editor whole selection", selection.testSyntheticParagraphNewlineDoesNotRejectAWholeEditorSelection),
    ("partial and wrong selections rejected", selection.testPartialSelectionOrWrongSelectedTextIsNeverAccepted),
    ("supported target boundaries", compatibility.testSupportedTargetsDoNotExpandToBrowsersOrUnrelatedApps),
    ("helper focus preserves target", compatibility.testHelperActivationKeepsLastTargetWithoutGuessingOne),
    ("weak editor identity rejected", compatibility.testUnidentifiedAndGenericEditorsCannotBeReattached),
    ("editor rebuild continuity", compatibility.testRebuiltEditorKeepsTransactionOnlyWhenAnchorIsUnchanged),
    ("model newline change retains original", suite.testModelChangingOnlyInternalBlankLinesStillCreatesRecovery),
    ("rich text paragraph recovery", suite.testRichTextParagraphRenderingAcknowledgesPasteAndKeepsExactBackup),
    ("paragraph boundaries remain strict", suite.testParagraphNormalizationNeverHidesLostWordsOrSingleLineBreaks),
    ("replace and exact restore", suite.testOptimizationProducesOneReplaceAndRestorePreservesExactOriginal),
    ("typing conflict", suite.testUserEditsDuringGenerationAreNotOverwritten),
    ("chat switch", suite.testSwitchingChatIsNotOverwrittenEvenWhenDraftTextMatches),
    ("cancel late result", suite.testCancellationRejectsLateResult),
    ("old result", suite.testOldResultCannotReplaceNewRequest),
    ("restore conflict", suite.testRestoreDoesNotOverwriteLaterTypingOrOtherEditor),
    ("failed paste", suite.testFailedPasteDoesNotClaimRestoreIsAvailable),
    ("cancel before apply", suite.testCancelBetweenResultAndApplyPreventsCommit),
    ("input boundaries", suite.testBlankAndOversizedInputsCannotStart),
    ("empty result", suite.testEmptyOutputDoesNotReplaceDraft),
    ("restore acknowledged", suite.testRestoreRequiresVerifiedApplyAndCannotRepeatAfterAcknowledgment),
    ("response decoding", suite.testInvalidResponseIsRejectedAndUnicodeIsPreserved),
    ("rendered trailing newline recovery", suite.testRenderedNewlineDoesNotLoseRestoreBackup),
    ("CRLF recovery", suite.testLineEndingNormalizationPreservesOriginalForRestore),
    ("unchanged retry updates rendering", suite.testUnchangedRetryAcknowledgesChangedRenderingWithoutLosingOriginal),
    ("unchanged retry retains original", suite.testUnchangedRetryPreservesPreviousOriginal),
    ("cancelled and failed retries retain original", suite.testCancelledOrFailedRetryPreservesPreviousOriginal),
    ("unchanged first result has no backup", suite.testFirstUnchangedOptimizationDoesNotInventBackup),
    ("meaningful edits rejected", suite.testNormalizationNeverAcceptsUserAddedTextOrMeaningfulSpaces)
]
for (name, test) in tests {
    let before = failures
    do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
    if failures == before { print("PASS \(name)") }
}
let loopback = APILoopbackTests()
let transport = APITransportTests()
let runnerSuite = RunnerTests()
let runnerTests: [(String, () async throws -> Void)] = [
    ("real HTTP API without CLI", loopback.testRealHTTPBackendDoesNotNeedCodexCLI),
    ("real HTTP redirect blocked", loopback.testRealHTTPRedirectIsNotFollowedWithKeyOrDraft),
    ("API URL loading completed response", transport.testActualURLLoadingReturnsOnlyCompletedDraft),
    ("API HTTP failure no retry", transport.testHTTPFailureNeverLeaksResponseBodyOrRetries),
    ("API timeout mapping", transport.testNetworkTimeoutMapsToTimeout),
    ("API cancellation", transport.testCancellationStopsWaitingForAPI),
    ("stdin and cleanup", runnerSuite.testRealProcessReceivesLiteralDraftOnStdinAndCleansWorkspace),
    ("CLI failure", runnerSuite.testProcessFailureDoesNotReturnPartialResult),
    ("CLI timeout", runnerSuite.testTimeoutStopsProcessAndRejectsLateOutput),
    ("CLI cancellation", runnerSuite.testCancellationStopsChild)
]
for (name, test) in runnerTests {
    let before = failures
    do { try await test() } catch { failures += 1; print("FAIL \(name): \(error)") }
    if failures == before { print("PASS \(name)") }
}
print("\(tests.count + runnerTests.count) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
