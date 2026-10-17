import Foundation
import Darwin

private final class RunningProcess: @unchecked Sendable {
    enum Stop { case cancelled, timeout }
    private let lock = NSLock()
    private var process: Process?
    private var reason: Stop?
    func launch(_ p: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if reason != nil { throw CancellationError() }
        process = p
        do { try p.run() } catch { process = nil; throw error }
    }
    func stop(_ why: Stop) {
        lock.lock()
        if reason == nil { reason = why }
        let p = process
        if let p, p.isRunning { kill(p.processIdentifier, SIGTERM) }
        lock.unlock()
        // Enforce cancellation even if a child ignores SIGTERM; don't touch a completed process.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
            lock.lock(); defer { lock.unlock() }
            if let p = process, p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }
    func finish() throws {
        lock.lock(); let stop = reason; process = nil; lock.unlock()
        if let stop {
            switch stop { case .cancelled: throw CancellationError(); case .timeout: throw OptimizerError.timeout }
        }
    }
}

public final class CodexRunner: @unchecked Sendable {
    private let executable: URL
    private let timeout: TimeInterval
    public init(executable: URL, timeout: TimeInterval = 120) { self.executable = executable; self.timeout = timeout }
    public static func locateExecutable() -> URL? {
        let fm = FileManager.default
        let bundled = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        if fm.isExecutableFile(atPath: bundled) { return URL(fileURLWithPath: bundled) }
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let path = String(dir) + "/codex"
            if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        let home = fm.homeDirectoryForCurrentUser
        let versions = home.appendingPathComponent(".nvm/versions/node")
        let dirs = (try? fm.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs.sorted(by: { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }) {
            let path = dir.appendingPathComponent("bin/codex")
            if fm.isExecutableFile(atPath: path.path) { return path }
        }
        return nil
    }
    public func optimize(_ text: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OptimizerError.emptyInput }
        guard text.count <= 30000 else { throw OptimizerError.tooLong }
        let state = RunningProcess()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    do { continuation.resume(returning: try perform(text, state: state)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { state.stop(.cancelled) })
    }
    private func perform(_ text: String, state: RunningProcess) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw OptimizerError.cliMissing }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("codex-prompt-opt-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        let inputURL = root.appendingPathComponent("input.txt")
        let output = root.appendingPathComponent("result.json")
        let schema = root.appendingPathComponent("schema.json")
        let data = try JSONSerialization.data(withJSONObject: ["draft": text], options: [.sortedKeys, .withoutEscapingSlashes])
        let instructions = OptimizationPrompt.instructions + "\n按 JSON Schema 返回 optimized 字段，内容仅为可直接使用的完整提示词。"
        try Data((instructions + "\n\nDRAFT_JSON:\n" + String(decoding: data, as: UTF8.self)).utf8).write(to: inputURL)
        try Data(#"{"type":"object","properties":{"optimized":{"type":"string"}},"required":["optimized"],"additionalProperties":false}"#.utf8).write(to: schema)
        for url in [inputURL, schema] { try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        let input = try FileHandle(forReadingFrom: inputURL)
        defer { try? input.close() }
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = root
        // Keep login in CODEX_HOME, but don't import project/user plugins or API-key environment variables.
        let allowed = Set(["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "SHELL", "CODEX_HOME", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY", "SSL_CERT_FILE", "SSL_CERT_DIR"])
        process.environment = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
        var args = ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never", "-C", root.path,
                    "-c", "model_reasoning_effort=\"low\"", "-c", "web_search=\"disabled\"",
                    "--output-schema", schema.path, "-o", output.path]
        for feature in ["shell_tool", "apps", "plugins", "hooks", "memories", "multi_agent", "computer_use", "browser_use", "browser_use_external", "in_app_browser", "image_generation", "imagegenext"] {
            args += ["--disable", feature]
        }
        args += ["-"]
        process.arguments = args
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try state.launch(process)
        let timeoutTask = DispatchWorkItem { state.stop(.timeout) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
        process.waitUntilExit()
        timeoutTask.cancel()
        try state.finish()
        guard process.terminationStatus == 0 else { throw OptimizerError.cliFailed }
        guard let bytes = try? Data(contentsOf: output) else { throw OptimizerError.invalidResponse }
        return try OptimizerResponse.decode(bytes)
    }
}
