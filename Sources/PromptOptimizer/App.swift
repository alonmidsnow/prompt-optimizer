import AppKit
import ApplicationServices
import OptimizerCore
import Darwin

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OptimizerApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var access: any EditorGateway = EditorAccess()
    private var practice: PracticeEditor?
    private var localShortcut: Any?
    private let session = OptimizationSession()
    private let shortcut = UndoShortcut()
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var widget: OrbWidget!
    private var message = NSTextField(wrappingLabelWithString: "在 Codex 或 Claude 输入需求，点“优化提示词”。")
    private let hint = NSTextField(wrappingLabelWithString: "优化使用 Codex 额度 · 不自动发送")
    private var optimizeButton = NSButton()
    private var quitButton = NSButton()
    private var originalButton = NSButton()
    private var timer: Timer?
    private var job: Task<Void, Never>?
    private var requestID: UUID?
    private var pendingDraft: DraftSnapshot?
    private var usageHint = "Codex CLI · 使用 CLI 登录额度"
    private var busy = false
    private var applying = false
    private var wasTrusted = false
    private var recordedPermission: Bool?
    private var operationStage = "idle"
    private var recordedStage: String?
    private var operationDetails: [String: Int] = [:]
    private var recordedDetails: [String: Int] = [:]
    private var instanceLockFD: Int32 = -1
    private var lastOriginal: String?
    private var originalWindow: NSWindow?
    private var manualShow = true
    private var manuallyHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard requireInstalledLocation() else { return }
        if CommandLine.arguments.contains("--practice") || Bundle.main.object(forInfoDictionaryKey: "OptimizerPractice") as? Bool == true {
            let editor = PracticeEditor(); practice = editor; access = editor
        }
        if let live = access as? EditorAccess {
            live.reportStep = { [weak self] step, details in self?.setOperation("applying_" + step, details: details) }
        }
        makePanel()
        practice?.mount(widget)
        if CommandLine.arguments.contains("--preview") {
            setMessage("界面预览：点击优化时自动识别输入框。此模式不访问 Codex、不调用模型。")
            for button in [optimizeButton, originalButton] { button.isEnabled = false }
            widget.show()
            return
        }
        makeMenu()
        shortcut.handleUndo = { [weak self] in
            guard let self, !self.busy, !self.applying,
                  let current = try? self.access.current(), self.session.canRestore(current: current) else { return false }
            self.undoNative(); return true
        }
        if practice != nil {
            localShortcut = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let mods = event.modifierFlags.intersection([.control, .command, .option, .shift])
                if event.keyCode == 6, mods == .control, self?.shortcut.handleUndo?() == true { return nil }
                return event
            }
            setMessage("练习模式：模拟优化，不访问 Codex，不消耗额度。")
        }
        timer = Timer.scheduledTimer(timeInterval: 0.4, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        widget.show()
        poll()
        checkPermissionOnEntry()
        if practice == nil {
            do { usageHint = try OptimizerConfiguration.load().usageHint }
            catch { setOperation("failed_configuration"); setMessage(error.localizedDescription) }
        }
        if let practice {
            print("Practice window IDs: editor=\(practice.window.windowNumber) orb=\(panel.windowNumber) menu=\(widget.menu.windowNumber)")
            fflush(stdout)
        }
    }
    private func requireInstalledLocation() -> Bool {
        guard Bundle.main.bundleIdentifier == "cn.sangengxue.codex-prompt-optimizer" else { return true }
        let actual = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let accepted = InstallationPaths.candidates()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ownPID &&
            $0.bundleURL.map { InstallationPaths.isInstalled($0) } == true
        }.min { $0.processIdentifier < $1.processIdentifier }
        if let existing, !InstallationPaths.isInstalled(actual) || existing.processIdentifier < ownPID {
            existing.activate(options: [.activateIgnoringOtherApps]); NSApp.terminate(nil); return false
        }
        if InstallationPaths.isInstalled(actual) {
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexPromptOptimizer")
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            catch { NSApp.terminate(nil); return false }
            let fd = open(folder.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { NSApp.terminate(nil); return false }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); NSApp.terminate(nil); return false }
            instanceLockFD = fd
            return true
        }
        // A second copy must never present itself as the authorised installed app.
        guard let installed = accepted.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            let alert = NSAlert(); alert.messageText = "请先安装提示词助手"
            alert.informativeText = "请将助手拖入“应用程序”（/Applications），再从那里启动。也支持 ~/Applications；不要从 DMG 或下载目录直接运行。"
            alert.runModal(); NSApp.terminate(nil); return false
        }
        let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: installed, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return false
    }
    private func recordPermissionState(_ trusted: Bool) {
        guard practice == nil, Bundle.main.bundleIdentifier == "cn.sangengxue.codex-prompt-optimizer", (recordedPermission != trusted || recordedStage != operationStage || recordedDetails != operationDetails) else { return }
        recordedPermission = trusted; recordedStage = operationStage; recordedDetails = operationDetails
        // Diagnostics contain only this app's identity and OS trust result, never draft text or keys.
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexPromptOptimizer")
        let data: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
                                  "appPath": Bundle.main.bundleURL.path,
                                  "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                                  "accessibilityTrusted": trusted, "operationStage": operationStage, "operationDetails": operationDetails,
                                  "updatedAt": ISO8601DateFormatter().string(from: Date())]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let target = folder.appendingPathComponent("runtime-status.json")
            try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: target, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch { /* Diagnostics must never block the helper. */ }
    }
    private func setOperation(_ stage: String, details: [String: Int] = [:]) {
        operationStage = stage; operationDetails = details
        if widget != nil {
            switch stage {
            case "preparingTarget", "generating", "modelReturned", "applying", "undoing": widget.orb.phase = .working
            case "applied": widget.orb.phase = .completed
            case "noChange", "cancelled", "undone": widget.orb.phase = .idle
            default:
                if stage.hasPrefix("applying_") { widget.orb.phase = .working }
                else if stage.hasPrefix("failed_") || stage == "targetUnavailable" || stage == "undoUnconfirmed" { widget.orb.phase = .failed }
            }
        }
        recordPermissionState(access.isTrusted)
    }
    private func makePanel() {
        optimizeButton = MenuRow("优化提示词", symbol: "sparkles", shortcut: "AI", target: self, action: #selector(optimize))
        originalButton = MenuRow("查看原文", symbol: "doc.text", target: self, action: #selector(showOriginal))
        quitButton = MenuRow("退出", symbol: "power", target: self, action: #selector(quitApp))
        optimizeButton.toolTip = "自动识别当前 Codex / Claude 草稿并优化，保留原文，不自动发送"
        quitButton.toolTip = "退出会取消优化并清除本次会话的原文备份"
        widget = OrbWidget(message: message, hint: hint, rows: [optimizeButton, originalButton, quitButton])
        panel = widget.orbPanel
        optimizeButton.isEnabled = false; originalButton.isEnabled = false
    }
    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✦ 优化"
        statusItem.button?.toolTip = "Codex 提示词助手"
        // The menu bar item simply reopens the same four-action menu.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showPanel)
    }
    private func checkPermissionOnEntry() {
        guard practice == nil, !CommandLine.arguments.contains("--preview"), !access.isTrusted else { return }
        setMessage("系统尚未确认当前安装版的授权。已打开设置，请仅添加你安装到“应用程序”的本应用。")
        access.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    private func setMessage(_ text: String) { message.stringValue = text; widget?.reveal() }
    @objc private func poll() {
        guard !applying else { return }
        let trusted = access.isTrusted
        recordPermissionState(trusted)
        if practice == nil {
            if trusted && !shortcut.isActive { shortcut.start() }
            if !trusted && shortcut.isActive { shortcut.stop() }
            if trusted != wasTrusted {
                setMessage(trusted ? "权限已就绪。点中 Codex 或 Claude 草稿，再点“优化提示词”。" : "控制权限已失效。下次打开助手将自动调起系统授权。")
            }
        }
        wasTrusted = trusted
        let current = try? access.current()
        // A transient AX/focus read failure is not proof that the user edited the draft.
        // Before applying a result, accept() and replace() always revalidate the actual target and text.
        if busy, let before = pendingDraft, let current, current != before {
            cancelWork(); setMessage("检测到草稿或目标已改变，已停止本次优化，未回填。")
        }
        optimizeButton.isEnabled = trusted && !busy
        widget.layout()
        originalButton.isEnabled = lastOriginal != nil
        hint.stringValue = access.isTrusted
            ? (session.hasBackup ? "⌘Z 原生撤销 · Ctrl+Z 兼容\n" : "不自动发送 · 原文仅本次保留\n") + usageHint
            : "点击优化才调用配置的模型\n原文保存在内存，退出即清除"
        if practice != nil { hint.stringValue = "练习模式 · 仅模拟改写，不调用模型\n" + (session.hasBackup ? "⌘Z 原生撤销 · Ctrl+Z 兼容" : "不访问 Codex，无需系统权限") }
        if access.targetIsFrontmost {
            if !manuallyHidden { widget.show() }
            manualShow = false
        } else if !manualShow && NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            widget.hide()
        }
    }
    @objc private func optimize() {
        guard !busy, !applying else { return }
        guard access.isTrusted else { checkPermissionOnEntry(); return }
        applying = true; optimizeButton.isEnabled = false
        setOperation("preparingTarget")
        setMessage("正在识别当前输入框…")
        Task { [weak self] in
            guard let self else { return }
            do {
                try await access.prepareForOptimization()
                applying = false
                optimizePrepared()
            } catch {
                applying = false; setOperation("targetUnavailable", details: operationDetails)
                setMessage(error.localizedDescription); poll()
            }
        }
    }
    private func optimizePrepared() {
        guard !busy, !applying else { return }
        do {
            guard access.isTrusted else { checkPermissionOnEntry(); return }
            // Preserve the current target identity for retries; acquire a new focused editor only on explicit Optimize.
            let before: DraftSnapshot
            if let current = try? access.current() { before = current }
            else { before = try access.bind() }
            let id = try session.begin(before)
            let configuration = practice == nil ? try OptimizerConfiguration.load() : nil
            if let configuration { usageHint = configuration.usageHint }
            // Keep the last committed recovery text through failed, cancelled or unchanged retries.
            if lastOriginal == nil { lastOriginal = before.text }
            originalWindow?.close(); originalWindow = nil
            requestID = id; pendingDraft = before; busy = true
            setOperation("generating")
            setMessage("正在优化…请保持原输入框。改稿会停止优化；退出可取消请求。")
            job = Task { [weak self] in
                guard let self else { return }
                do {
                    let text: String
                    if let practice { text = try await practice.simulatedOptimization(before.text) }
                    else if let configuration { text = try await configuration.optimize(before.text) }
                    else { throw OptimizerError.cliMissing }
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    setOperation("modelReturned")
                    let edit = try session.accept(id: id, result: text, current: access.current())
                    applying = true
                    setOperation("applying")
                    setMessage("优化稿已生成，正在回填并核验输入框…")
                    optimizeButton.isEnabled = false
                    let observed = try await access.replace(edit)
                    let changed = try session.recordApplied(edit, observed: observed)
                    if session.canRestore(current: observed) { access.rememberRecoveryTarget() }
                    if changed {
                        lastOriginal = before.text
                        originalWindow?.close(); originalWindow = nil
                    }
                    setOperation(changed ? "applied" : "noChange")
                    setMessage(!changed ? (text == before.text ? "模型返回了原文，输入框未修改。" : "文字内容未变，仅输入框换行显示有差异。") : "优化完成，已回填。可按 ⌘Z 撤销（Ctrl+Z 兼容）；原文可查看。")
                } catch {
                    if requestID == id {
                        session.cancel()
                        setOperation(error is CancellationError ? "cancelled" : "failed_" + operationStage, details: operationDetails)
                        setMessage(error is CancellationError ? "已取消，未继续应用结果。" : error.localizedDescription)
                    }
                }
                if requestID == id { busy = false; applying = false; pendingDraft = nil; requestID = nil; job = nil; poll() }
            }
            poll()
        } catch { session.cancel(); setOperation("failed_preparing"); setMessage(error.localizedDescription) }
    }
    private func undoNative() {
        guard !busy, !applying else { return }
        applying = true
        setOperation("undoing")
        optimizeButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let edit = try session.restore(current: access.current())
                let observed = try await access.nativeUndo()
                try session.recordApplied(edit, observed: observed)
                setOperation("undone")
                setMessage("已核验原生撤销，原文仍可查看。")
            } catch {
                session.cancel(); setOperation("undoUnconfirmed")
                setMessage("未确认原生撤销，请核对输入框；可从“查看原文”复制备份。")
            }
            applying = false; poll()
        }
    }
    private func cancelWork() {
        guard !applying else { return }
        if busy { setOperation("cancelled") }
        session.cancel(); requestID = nil; pendingDraft = nil; job?.cancel(); job = nil; busy = false
    }
    @objc private func showPanel() {
        manualShow = true; manuallyHidden = false
        widget.show()
        widget.reveal()
        checkPermissionOnEntry()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { manuallyHidden = true }
    }
    @objc private func showOriginal() {
        guard let text = lastOriginal else { setMessage("当前没有保存的原文。") ; return }
        if let originalWindow { originalWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.title = "优化前原文（仅保存在内存）"; win.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: win.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.font = .systemFont(ofSize: 14); view.string = text
        view.textContainerInset = NSSize(width: 14, height: 14)
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view; win.contentView?.addSubview(scroll)
        originalWindow = win; win.center(); win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Never interrupt a native paste/clipboard restoration half way through.
        if applying { setMessage("正在完成输入框替换，请稍后退出。") ; return .terminateCancel }
        if instanceLockFD >= 0 { close(instanceLockFD); instanceLockFD = -1 }
        cancelWork(); shortcut.stop(); if let localShortcut { NSEvent.removeMonitor(localShortcut) }; session.discard(); lastOriginal = nil; originalWindow?.close(); timer?.invalidate()
        return .terminateNow
    }
}
