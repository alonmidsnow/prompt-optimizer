import Foundation
import OptimizerCore

private final class APIProtocol: URLProtocol {
    enum Reply { case response(Int, Data), failure(URLError.Code), hang, redirect }
    static var reply: Reply = .response(200, Data())
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        switch Self.reply {
        case .response(let status, let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"] )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code): client?.urlProtocol(self, didFailWithError: URLError(code))
        case .hang: break
        case .redirect:
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location":"https://other.example/v1/chat/completions"])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://other.example/v1/chat/completions")!), redirectResponse: response)
        }
    }
    override func stopLoading() {}
}

@MainActor
struct APITransportTests {
    private func runner(_ reply: APIProtocol.Reply) throws -> OpenAICompatibleRunner {
        APIProtocol.reply = reply; APIProtocol.requests = 0
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [APIProtocol.self]
        let config = try OptimizerConfiguration.decode(Data(#"{"backend":"openai_compatible","api":{"base_url":"https://api.example/v1","model":"test","api_key":"private-test-token"}}"#.utf8))
        return OpenAICompatibleRunner(configuration: config, sessionConfiguration: settings)
    }
    func testActualURLLoadingReturnsOnlyCompletedDraft() async throws {
        let client = try runner(.response(200, Data(#"{"choices":[{"index":0,"message":{"role":"assistant","content":"请整理真实记录，缺项留空。"},"finish_reason":"stop"}]}"#.utf8)))
        let output = try await client.optimize("整理周报")
        XCTAssertEqual(output, "请整理真实记录，缺项留空。")
        XCTAssertEqual(APIProtocol.requests, 1)
    }
    func testHTTPFailureNeverLeaksResponseBodyOrRetries() async throws {
        let client = try runner(.response(401, Data("private-test-token server secret".utf8)))
        do { _ = try await client.optimize("草稿"); failures += 1; print("FAIL expected HTTP error") }
        catch BackendError.http(let status) { XCTAssertEqual(status, 401) }
        catch { throw error }
        XCTAssertEqual(APIProtocol.requests, 1)
    }
    func testNetworkTimeoutMapsToTimeout() async throws {
        let client = try runner(.failure(.timedOut))
        do { _ = try await client.optimize("草稿"); failures += 1; print("FAIL expected timeout") }
        catch OptimizerError.timeout {} catch { throw error }
    }
    func testCancellationStopsWaitingForAPI() async throws {
        let client = try runner(.hang)
        let job = Task { try await client.optimize("草稿") }
        try await Task.sleep(nanoseconds: 100_000_000)
        job.cancel()
        do { _ = try await job.value; failures += 1; print("FAIL expected API cancellation") }
        catch is CancellationError {} catch { throw error }
    }
}
