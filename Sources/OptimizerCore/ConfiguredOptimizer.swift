import Foundation

public enum BackendError: LocalizedError {
    case configuration(String), http(Int), network
    public var errorDescription: String? {
        switch self {
        case .configuration(let message): return "配置错误：" + message
        case .http(let status): return "模型接口返回 HTTP \(status)，未回填。请检查配置、额度和服务状态。"
        case .network: return "无法连接模型接口，未回填。请检查网络和服务地址。"
        }
    }
}

public struct OptimizerConfiguration: Decodable {
    public enum Backend: String, Decodable { case codexCLI = "codex_cli", openAICompatible = "openai_compatible" }
    public struct CLI: Decodable { public let executablePath: String?; enum CodingKeys: String, CodingKey { case executablePath = "executable_path" } }
    public struct API: Decodable {
        public let baseURL: String
        public let model: String
        public let apiKey: String
        enum CodingKeys: String, CodingKey { case baseURL = "base_url", model, apiKey = "api_key" }
    }
    public let backend: Backend
    public let codex: CLI?
    public let api: API?
    private let timeoutValue: Double?
    public var timeout: Double { timeoutValue ?? 120 }
    enum CodingKeys: String, CodingKey { case backend, codex, api, timeoutValue = "timeout_seconds" }
    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexPromptOptimizer/config.json")
    }
    public static let template = """
    {
      "backend": "codex_cli",
      "timeout_seconds": 120,
      "codex": { "executable_path": "" },
      "api": {
        "base_url": "https://api.openai.com/v1",
        "model": "",
        "api_key": ""
      }
    }
    """
    public static func load(at url: URL = fileURL) throws -> OptimizerConfiguration {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                // Never overwrite an existing user configuration, including concurrent creation.
                try Data(template.utf8).write(to: url, options: [.withoutOverwriting])
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 65536 else {
                throw BackendError.configuration("config.json 必须是小于 64KB 的普通文件。")
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return try decode(Data(contentsOf: url))
        } catch let error as BackendError { throw error }
        catch { throw BackendError.configuration("无法读取 config.json，请检查文件和 JSON 格式。") }
    }
    public static func decode(_ data: Data) throws -> OptimizerConfiguration {
        let config: OptimizerConfiguration
        do { config = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw BackendError.configuration("config.json 格式或 backend 无效。") }
        guard config.timeout.isFinite, (5...300).contains(config.timeout) else { throw BackendError.configuration("timeout_seconds 需在 5 到 300 之间。") }
        if config.backend == .openAICompatible { _ = try config.endpoint() }
        return config
    }
    private var localAPI: Bool {
        guard let host = URLComponents(string: api?.baseURL ?? "")?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }
    public func endpoint() throws -> URL {
        guard let api, !api.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !api.model.contains("\n"), !api.apiKey.contains("\n"), !api.apiKey.contains("\r"),
              let parts = URLComponents(string: api.baseURL), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" || (parts.scheme == "http" && localAPI),
              localAPI || !api.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let base = parts.url else {
            throw BackendError.configuration("API 需有效的 HTTPS base_url、model 和 api_key；本机回环服务可用 HTTP 并留空 key。")
        }
        return base.appendingPathComponent("chat/completions")
    }
    public var usageHint: String { backend == .codexCLI ? "Codex CLI · 使用 CLI 登录额度" : "模型 API · 由所配置服务计费" }
    public func optimize(_ text: String) async throws -> String {
        switch backend {
        case .codexCLI:
            let configured = codex?.executablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let executable: URL?
            if configured.isEmpty { executable = CodexRunner.locateExecutable() }
            else {
                guard configured.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: configured) else { throw BackendError.configuration("executable_path 必须是可执行文件的绝对路径。") }
                executable = URL(fileURLWithPath: configured)
            }
            guard let executable else { throw OptimizerError.cliMissing }
            return try await CodexRunner(executable: executable, timeout: timeout).optimize(text)
        case .openAICompatible: return try await OpenAICompatibleRunner(configuration: self).optimize(text)
        }
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public final class OpenAICompatibleRunner {
    private let configuration: OptimizerConfiguration
    private let sessionConfiguration: URLSessionConfiguration
    public init(configuration: OptimizerConfiguration, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration; self.sessionConfiguration = sessionConfiguration
    }
    public func request(for text: String) throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OptimizerError.emptyInput }
        guard text.count <= 30000 else { throw OptimizerError.tooLong }
        let endpoint = try configuration.endpoint()
        guard let api = configuration.api else { throw BackendError.configuration("缺少 api 配置。") }
        var request = URLRequest(url: endpoint, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !api.apiKey.isEmpty { request.setValue("Bearer " + api.apiKey, forHTTPHeaderField: "Authorization") }
        let draft = try JSONSerialization.data(withJSONObject: ["draft": text], options: [.withoutEscapingSlashes])
        let body: [String: Any] = ["model": api.model, "stream": false, "messages": [
            ["role": "system", "content": OptimizationPrompt.instructions + "\n只返回可直接使用的完整提示词正文，不加代码围栏、解释或 JSON 外壳。"],
            ["role": "user", "content": String(decoding: draft, as: UTF8.self)]
        ]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    public static func decodeResponse(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String?; let refusal: String? }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        guard data.count <= 256000, let response = try? JSONDecoder().decode(Response.self, from: data),
              let choice = response.choices.first, choice.finish_reason == "stop", choice.message.refusal == nil,
              let content = choice.message.content else { throw OptimizerError.invalidResponse }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 60000 else { throw OptimizerError.invalidResponse }
        return text
    }
    public func optimize(_ text: String) async throws -> String {
        let request = try request(for: text)
        let settings = sessionConfiguration.copy() as! URLSessionConfiguration
        settings.httpShouldSetCookies = false; settings.httpCookieStorage = nil; settings.urlCache = nil
        settings.urlCredentialStorage = nil
        settings.timeoutIntervalForRequest = configuration.timeout; settings.timeoutIntervalForResource = configuration.timeout
        let delegate = NoRedirect()
        let session = URLSession(configuration: settings, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.network }
            guard http.statusCode == 200 else { throw BackendError.http(http.statusCode) }
            guard response.expectedContentLength <= 256000 else { throw OptimizerError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 256000 else { throw OptimizerError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return try Self.decodeResponse(data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            if error.code == .timedOut { throw OptimizerError.timeout }
            throw BackendError.network
        } catch let error as BackendError { throw error }
        catch let error as OptimizerError { throw error }
        catch { throw BackendError.network }
    }
}
