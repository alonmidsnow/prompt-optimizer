import Foundation
import OptimizerCore

@MainActor
struct RunnerTests {
    func fixture(_ script: String) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("optimizer-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let cli = root.appendingPathComponent("fake-codex")
        try Data(("#!/bin/sh\n" + script).utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        return (root, cli)
    }
    func testRealProcessReceivesLiteralDraftOnStdinAndCleansWorkspace() async throws {
        let (root, cli) = try fixture("""
        out=''
        prev=''
        for arg in "$@"; do
          if [ "$prev" = '-o' ]; then out="$arg"; fi
          prev="$arg"
        done
        cat > "$0.request"
        pwd > "$0.cwd"
        printf '%s' '{"optimized":"请根据真实记录写周报，列出进展与问题。"}' > "$out"
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = CodexRunner(executable: cli)
        let output = try await runner.optimize("写周报\n保留 $& $$ `echo nope` 与 \"引号\"")
        XCTAssertEqual(output, "请根据真实记录写周报，列出进展与问题。")
        let request = try String(contentsOf: URL(fileURLWithPath: cli.path + ".request"), encoding: .utf8)
        let suffix = request.components(separatedBy: "DRAFT_JSON:\n").last!
        let json = try JSONSerialization.jsonObject(with: Data(suffix.utf8)) as! [String: String]
        XCTAssertEqual(json["draft"], "写周报\n保留 $& $$ `echo nope` 与 \"引号\"")
        let cwd = try String(contentsOf: URL(fileURLWithPath: cli.path + ".cwd"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwd))
    }
    func testProcessFailureDoesNotReturnPartialResult() async throws {
        let (root, cli) = try fixture("cat >/dev/null\nexit 8")
        defer { try? FileManager.default.removeItem(at: root) }
        do { _ = try await CodexRunner(executable: cli).optimize("测试"); failures += 1; print("FAIL expected CLI failure") }
        catch OptimizerError.cliFailed {} catch { throw error }
    }
    func testTimeoutStopsProcessAndRejectsLateOutput() async throws {
        let (root, cli) = try fixture("cat >/dev/null\nexec /bin/sleep 10")
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date()
        do { _ = try await CodexRunner(executable: cli, timeout: 0.15).optimize("测试"); failures += 1; print("FAIL expected timeout") }
        catch OptimizerError.timeout {} catch { throw error }
        XCTAssertTrue(Date().timeIntervalSince(start) < 5)
    }
    func testCancellationStopsChild() async throws {
        let (root, cli) = try fixture("cat >/dev/null\nexec /bin/sleep 10")
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task { try await CodexRunner(executable: cli).optimize("测试") }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; failures += 1; print("FAIL expected cancellation") }
        catch is CancellationError {} catch { throw error }
    }
}
