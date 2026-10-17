import AppKit

@main
struct Launch {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = OptimizerApp()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}
