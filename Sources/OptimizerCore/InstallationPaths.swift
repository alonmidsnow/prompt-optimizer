import Foundation

public enum InstallationPaths {
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(fileURLWithPath: "/Applications/Codex提示词助手.app"), home.appendingPathComponent("Applications/Codex提示词助手.app")]
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }
    public static func isInstalled(_ app: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        candidates(home: home).contains(app.resolvingSymlinksInPath().standardizedFileURL)
    }
}
