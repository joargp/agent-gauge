// Draws the disk image window background: an arrow from the app to the
// Applications folder and a one-line hint. Run from the repo root:
//   swift script/make_dmg_background.swift
// It writes Resources/dmg/background.png and background@2x.png.
import AppKit

let width: CGFloat = 640, height: CGFloat = 400

func render(scale: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // A light, even background keeps Finder's black icon labels readable.
    NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1),
               ending: NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // Arrow between the two icons, which sit at y = 180 from the top.
    let arrowY = height - 180
    let arrow = NSBezierPath()
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 268, y: arrowY))
    arrow.line(to: NSPoint(x: 366, y: arrowY))
    arrow.move(to: NSPoint(x: 346, y: arrowY + 18))
    arrow.line(to: NSPoint(x: 370, y: arrowY))
    arrow.line(to: NSPoint(x: 346, y: arrowY - 18))
    NSColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 1).setStroke()
    arrow.stroke()

    // Hint under the icons and their labels.
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let hint = NSAttributedString(string: "Drag Agent Gauge to Applications to install it", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.33, green: 0.33, blue: 0.36, alpha: 1),
        .paragraphStyle: style,
    ])
    hint.draw(in: NSRect(x: 0, y: 72, width: width, height: 24))

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(scale: 1, to: "Resources/dmg/background.png")
render(scale: 2, to: "Resources/dmg/background@2x.png")
