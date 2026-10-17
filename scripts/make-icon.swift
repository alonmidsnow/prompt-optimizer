import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let image = NSImage(size: NSSize(width: px, height: px))
        image.lockFocus()
        NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: px, height: px).fill()
        let pad = CGFloat(px) * 0.05
        let rect = NSRect(x: pad, y: pad, width: CGFloat(px)-2*pad, height: CGFloat(px)-2*pad)
        let round = NSBezierPath(roundedRect: rect, xRadius: CGFloat(px)*0.22, yRadius: CGFloat(px)*0.22)
        NSGradient(colors: [NSColor(calibratedRed: 0.25, green: 0.26, blue: 0.42, alpha: 1), NSColor(calibratedRed: 0.055, green: 0.069, blue: 0.10, alpha: 1)])!.draw(in: round, angle: -90)
        NSColor(calibratedRed: 0.56, green: 0.52, blue: 1, alpha: 0.7).setStroke()
        round.lineWidth = max(1,CGFloat(px)*0.012); round.stroke()
        let c = CGFloat(px)/2, r = CGFloat(px)*0.24, k = CGFloat(px)*0.055
        let path = NSBezierPath(); path.move(to: NSPoint(x:c,y:c+r))
        path.curve(to:NSPoint(x:c+r,y:c),controlPoint1:NSPoint(x:c+k,y:c+k),controlPoint2:NSPoint(x:c+k,y:c+k))
        path.curve(to:NSPoint(x:c,y:c-r),controlPoint1:NSPoint(x:c+k,y:c-k),controlPoint2:NSPoint(x:c+k,y:c-k))
        path.curve(to:NSPoint(x:c-r,y:c),controlPoint1:NSPoint(x:c-k,y:c-k),controlPoint2:NSPoint(x:c-k,y:c-k))
        path.curve(to:NSPoint(x:c,y:c+r),controlPoint1:NSPoint(x:c-k,y:c+k),controlPoint2:NSPoint(x:c-k,y:c+k))
        NSColor.white.setFill(); path.fill(); image.unlockFocus()
        let data = NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try data.write(to:folder.appendingPathComponent(name))
    }
}
