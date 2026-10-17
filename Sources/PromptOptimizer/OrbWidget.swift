import AppKit
import QuartzCore

private let ink = NSColor(calibratedRed: 0.055, green: 0.069, blue: 0.10, alpha: 1)
private let accent = NSColor(calibratedRed: 0.56, green: 0.52, blue: 1, alpha: 1)

final class OrbView: NSView {
    enum Phase { case idle, working, completed, failed }
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    var pressed: (() -> Void)?
    var moved: (() -> Void)?
    var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            progress.isHidden = phase != .working
            if phase == .working {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0; spin.toValue = Double.pi * 2
                spin.duration = 1; spin.repeatCount = .infinity
                progress.add(spin, forKey: "optimization-spin")
            } else { progress.removeAnimation(forKey: "optimization-spin") }
            let state: String
            switch phase { case .idle: state = "待优化"; case .working: state = "正在优化提示词"; case .completed: state = "优化完成，已回填"; case .failed: state = "操作未完成，请展开查看" }
            setAccessibilityLabel("提示词助手 · " + state)
            toolTip = state + " · 悬停展开菜单"
            needsDisplay = true
        }
    }
    private let progress = CAShapeLayer()
    private var tracking: NSTrackingArea?
    private var dragPoint: NSPoint?
    private var origin: NSPoint?
    private var dragged = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        progress.strokeColor = accent.cgColor; progress.fillColor = NSColor.clear.cgColor
        progress.lineWidth = 2.5; progress.lineCap = .round
        progress.isHidden = true; layer?.addSublayer(progress)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("提示词助手，悬停展开菜单，拖动调整位置")
        toolTip = "提示词助手 · 悬停展开 · 拖动移动"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        progress.bounds = bounds; progress.position = NSPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: NSPoint(x: bounds.midX, y: bounds.midY), radius: 24, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
        progress.path = path
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
    override func accessibilityPerformPress() -> Bool { pressed?(); return true }
    override func mouseDown(with event: NSEvent) {
        dragPoint = NSEvent.mouseLocation; origin = window?.frame.origin; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragPoint, let origin, let window else { return }
        let p = NSEvent.mouseLocation; let dx = p.x - start.x; let dy = p.y - start.y
        guard abs(dx) + abs(dy) > 3 else { return }
        dragged = true
        let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? window.frame
        window.setFrameOrigin(NSPoint(x: min(max(origin.x + dx, frame.minX), frame.maxX - window.frame.width),
                                      y: min(max(origin.y + dy, frame.minY), frame.maxY - window.frame.height)))
        moved?()
    }
    override func mouseUp(with event: NSEvent) {
        if dragged, let p = window?.frame.origin {
            UserDefaults.standard.set([p.x, p.y], forKey: "orb-position")
        } else { pressed?() }
        dragPoint = nil; origin = nil
    }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
        ink.setFill(); circle.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.29, alpha: 1), ink])?.draw(in: circle, angle: -90)
        accent.withAlphaComponent(0.65).setStroke(); circle.lineWidth = 1.2; circle.stroke()
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        if phase == .completed {
            let check = NSBezierPath()
            check.move(to: NSPoint(x: c.x - 10, y: c.y))
            check.line(to: NSPoint(x: c.x - 3, y: c.y - 7))
            check.line(to: NSPoint(x: c.x + 11, y: c.y + 9))
            check.lineWidth = 3; check.lineCapStyle = .round; check.lineJoinStyle = .round
            NSColor.systemMint.setStroke(); check.stroke(); return
        }
        let star = NSBezierPath()
        star.move(to: NSPoint(x: c.x, y: c.y + 12))
        star.curve(to: NSPoint(x: c.x + 12, y: c.y), controlPoint1: NSPoint(x: c.x + 2, y: c.y + 3), controlPoint2: NSPoint(x: c.x + 3, y: c.y + 2))
        star.curve(to: NSPoint(x: c.x, y: c.y - 12), controlPoint1: NSPoint(x: c.x + 3, y: c.y - 2), controlPoint2: NSPoint(x: c.x + 2, y: c.y - 3))
        star.curve(to: NSPoint(x: c.x - 12, y: c.y), controlPoint1: NSPoint(x: c.x - 2, y: c.y - 3), controlPoint2: NSPoint(x: c.x - 3, y: c.y - 2))
        star.curve(to: NSPoint(x: c.x, y: c.y + 12), controlPoint1: NSPoint(x: c.x - 3, y: c.y + 2), controlPoint2: NSPoint(x: c.x - 2, y: c.y + 3))
        NSColor.white.setFill(); star.fill()
        if phase == .failed {
            let dot = NSBezierPath(ovalIn: NSRect(x: 40, y: 8, width: 8, height: 8))
            NSColor.systemOrange.setFill(); dot.fill()
        }
    }
}

final class MenuRow: NSButton {
    let symbol: String
    let shortcut: String
    private var hover = false
    private var tracking: NSTrackingArea?
    init(_ title: String, symbol: String, shortcut: String = "", target: AnyObject, action: Selector) {
        self.symbol = symbol; self.shortcut = shortcut
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        isBordered = false; setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if hover && isEnabled {
            accent.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
        }
        let color = isEnabled ? NSColor.white.withAlphaComponent(0.91) : NSColor.white.withAlphaComponent(0.30)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) {
            let tinted = image.withSymbolConfiguration(.init(paletteColors: [color])) ?? image
            tinted.draw(in: NSRect(x: 12, y: (bounds.height - 16)/2, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: isEnabled ? 0.9 : 0.25)
        }
        (title as NSString).draw(at: NSPoint(x: 40, y: (bounds.height - 17)/2), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color])
        let badge = shortcut as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.38)]
        badge.draw(at: NSPoint(x: bounds.width - badge.size(withAttributes: attrs).width - 12, y: (bounds.height - 13)/2), withAttributes: attrs)
    }
}

private final class HoverSurface: NSView {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
}

@MainActor
final class OrbWidget {
    let orbPanel: FloatingPanel
    let orb: OrbView
    let menu: FloatingPanel
    private let surface: HoverSurface
    private let message: NSTextField
    private let hint: NSTextField
    private let rows: [NSButton]
    private var hideJob: DispatchWorkItem?
    private var overOrb = false
    private var overMenu = false
    private var pinned = false
    private var embedded = false
    var onDrag: (() -> Void)?
    init(message: NSTextField, hint: NSTextField, rows: [NSButton]) {
        self.message = message; self.hint = hint; self.rows = rows
        orbPanel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 56, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        orbPanel.title = "提示词助手 · 悬浮球"
        menu = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 288, height: 360), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        menu.title = "提示词助手 · 功能菜单"
        for panel in [orbPanel, menu] {
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .floating
            panel.hasShadow = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
        }
        orb = OrbView(frame: NSRect(x: 0, y: 0, width: 56, height: 56)); orbPanel.contentView = orb
        surface = HoverSurface(frame: NSRect(x: 0, y: 0, width: 288, height: 360))
        surface.wantsLayer = true; surface.layer?.cornerRadius = 18
        surface.layer?.backgroundColor = ink.cgColor
        surface.layer?.borderWidth = 1; surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        menu.contentView = surface
        menu.appearance = NSAppearance(named: .darkAqua)
        let title = NSTextField(labelWithString: "PROMPT / 提示词助手")
        title.font = .systemFont(ofSize: 11, weight: .semibold); title.textColor = accent
        title.frame = NSRect(x: 20, y: 330, width: 248, height: 16); surface.addSubview(title)
        title.identifier = NSUserInterfaceItemIdentifier("menu-heading")
        message.font = .systemFont(ofSize: 12); message.textColor = .white.withAlphaComponent(0.76)
        message.maximumNumberOfLines = 3; surface.addSubview(message)
        hint.font = .systemFont(ofSize: 10); hint.textColor = .white.withAlphaComponent(0.36)
        hint.maximumNumberOfLines = 2; surface.addSubview(hint)
        rows.forEach { surface.addSubview($0) }
        orb.entered = { [weak self] in self?.overOrb = true; self?.reveal() }
        orb.exited = { [weak self] in self?.overOrb = false; self?.scheduleHide() }
        orb.pressed = { [weak self] in guard let self else { return }; pinned.toggle(); if pinned { reveal() } else { collapse() } }
        orb.moved = { [weak self] in self?.onDrag?(); self?.positionMenu() }
        surface.entered = { [weak self] in self?.overMenu = true; self?.hideJob?.cancel() }
        surface.exited = { [weak self] in self?.overMenu = false; self?.scheduleHide() }
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        var origin = NSPoint(x: frame.maxX - 80, y: frame.midY)
        if let saved = UserDefaults.standard.array(forKey: "orb-position") as? [Double], saved.count == 2 {
            let candidate = NSPoint(x: saved[0], y: saved[1])
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: 0, dy: 0).contains(candidate) }) { origin = candidate }
        }
        orbPanel.setFrameOrigin(origin)
        layout()
    }
    func layout() {
        let visible = rows.filter { !$0.isHidden }
        let height = CGFloat(visible.count) * 38 + 140
        let origin = menu.frame.origin
        menu.setFrame(NSRect(origin: origin, size: NSSize(width: 288, height: height)), display: true)
        surface.frame.size = NSSize(width: 288, height: height)
        surface.subviews.first(where: { $0.identifier?.rawValue == "menu-heading" })?.frame = NSRect(x: 20, y: height - 31, width: 248, height: 16)
        message.frame = NSRect(x: 20, y: height - 91, width: 248, height: 48)
        for (i, row) in visible.enumerated() { row.frame = NSRect(x: 10, y: height - 131 - CGFloat(i) * 38, width: 268, height: 36) }
        hint.frame = NSRect(x: 20, y: 11, width: 248, height: 28)
        if menu.isVisible { positionMenu() }
    }
    func embed(in host: NSView) {
        embedded = true
        orbPanel.contentView = nil; menu.contentView = nil
        orb.frame = NSRect(x: 916, y: host.bounds.height - 88, width: 56, height: 56)
        surface.frame.origin = NSPoint(x: 650, y: 35)
        host.addSubview(orb); host.addSubview(surface)
        surface.isHidden = true
    }
    func reveal() { hideJob?.cancel(); layout(); if embedded { surface.isHidden = false } else { positionMenu(); menu.orderFrontRegardless() } }
    func collapse() { hideJob?.cancel(); pinned = false; menu.orderOut(nil); if embedded { surface.isHidden = true } }
    func show() { if !embedded { orbPanel.orderFrontRegardless() } }
    func hide() { collapse(); orbPanel.orderOut(nil) }
    private func scheduleHide() {
        hideJob?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !overOrb, !overMenu, !pinned else { return }; menu.orderOut(nil); if embedded { surface.isHidden = true }
        }
        hideJob = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func positionMenu() {
        guard !embedded else { return }
        let orbFrame = orbPanel.frame
        let screen = NSScreen.screens.first(where: { $0.frame.contains(orbFrame.origin) }) ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let width = menu.frame.width, height = menu.frame.height
        let x = orbFrame.minX - width - 10 >= bounds.minX ? orbFrame.minX - width - 10 : orbFrame.maxX + 10
        let y = orbFrame.maxY - height
        menu.setFrameOrigin(NSPoint(x: min(max(x, bounds.minX + 8), bounds.maxX - width - 8), y: min(max(y, bounds.minY + 8), bounds.maxY - height - 8)))
    }
}
