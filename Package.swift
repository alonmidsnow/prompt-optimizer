// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CodexPromptOptimizer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PromptOptimizer", targets: ["PromptOptimizer"])],
    targets: [
        .target(name: "OptimizerCore"),
        .executableTarget(name: "PromptOptimizer", dependencies: ["OptimizerCore"]),
        .executableTarget(name: "OptimizerChecks", dependencies: ["OptimizerCore"], path: "Tests/OptimizerCoreTests")
    ]
)
