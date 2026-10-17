import Foundation
import OptimizerCore

struct InstallationTests {
    func testSystemAndUserApplicationsAreAcceptedButDownloadsAreNot() {
        let home = URL(fileURLWithPath: "/Users/tester")
        XCTAssertTrue(InstallationPaths.isInstalled(URL(fileURLWithPath: "/Applications/Codex提示词助手.app"), home: home))
        XCTAssertTrue(InstallationPaths.isInstalled(URL(fileURLWithPath: "/Users/tester/Applications/Codex提示词助手.app"), home: home))
        XCTAssertFalse(InstallationPaths.isInstalled(URL(fileURLWithPath: "/Users/another/Applications/Codex提示词助手.app"), home: home))
        XCTAssertFalse(InstallationPaths.isInstalled(URL(fileURLWithPath: "/Volumes/Prompt Optimizer/Codex提示词助手.app"), home: home))
        XCTAssertFalse(InstallationPaths.isInstalled(URL(fileURLWithPath: "/Users/tester/Downloads/Codex提示词助手.app"), home: home))
        XCTAssertFalse(InstallationPaths.isInstalled(URL(fileURLWithPath: "/Applications/Other.app"), home: home))
    }
}
