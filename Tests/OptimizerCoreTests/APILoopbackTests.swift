import Foundation
import OptimizerCore

@MainActor
struct APILoopbackTests {
    private func server() throws -> (Process, Int, URL) {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("optimizer-http-" + UUID().uuidString)
        let script = #"""
import http.server, json, sys
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        with open(sys.argv[1], 'a') as f:
            f.write(json.dumps({'path':self.path, 'body':json.loads(body), 'auth':self.headers.get('Authorization')})+'\n')
        if self.path.startswith('/redirect/'):
            self.send_response(302)
            self.send_header('Location', 'http://127.0.0.1:%d/trap/chat/completions' % self.server.server_port)
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            data = json.dumps({'choices':[{'message':{'role':'assistant','content':'只根据真实记录整理周报。'}, 'finish_reason':'stop'}]}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
server=http.server.HTTPServer(('127.0.0.1',0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
"""#
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", script, log.path]
        let stdout = Pipe(); process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
        try process.run()
        let line = String(decoding: stdout.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(line) else { process.terminate(); throw OptimizerError.invalidResponse }
        return (process, port, log)
    }
    private func config(port: Int, prefix: String) throws -> OptimizerConfiguration {
        let json: [String: Any] = ["backend":"openai_compatible", "api":["base_url":"http://127.0.0.1:\(port)/\(prefix)", "model":"test-local", "api_key":"fake-local-key"]]
        return try OptimizerConfiguration.decode(JSONSerialization.data(withJSONObject: json))
    }
    func testRealHTTPBackendDoesNotNeedCodexCLI() async throws {
        let (process, port, log) = try server()
        defer { process.terminate(); process.waitUntilExit(); try? FileManager.default.removeItem(at: log) }
        let output = try await config(port: port, prefix: "v1").optimize("帮我整理周报")
        XCTAssertEqual(output, "只根据真实记录整理周报。")
        let lines = try String(contentsOf: log).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let request = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        XCTAssertEqual(request["path"] as? String, "/v1/chat/completions")
        XCTAssertEqual(request["auth"] as? String, "Bearer fake-local-key")
    }
    func testRealHTTPRedirectIsNotFollowedWithKeyOrDraft() async throws {
        let (process, port, log) = try server()
        defer { process.terminate(); process.waitUntilExit(); try? FileManager.default.removeItem(at: log) }
        do { _ = try await config(port: port, prefix: "redirect").optimize("测试草稿"); failures += 1; print("FAIL redirect followed") }
        catch BackendError.http(let code) { XCTAssertEqual(code, 302) } catch { throw error }
        let lines = try String(contentsOf: log).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
    }
}
