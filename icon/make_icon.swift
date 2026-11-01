// Draws the Scrollo app icon (1024x1024 PNG): a glass scroll wheel with lit notch ticks and sound waves
// on a deep graphite squircle. Usage: make_icon <output.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let cg = gctx.cgContext

func c(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
let mint = c(120, 232, 190), mintBright = c(190, 255, 232), mintDeep = c(40, 170, 130)

// MARK: Base squircle (Apple's 824pt icon inside a 1024 canvas)
let base = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: NSColor.black.withAlphaComponent(0.5).cgColor)
c(14, 18, 17).setFill(); base.fill()
cg.restoreGState()

cg.saveGState()
base.addClip()
NSGradient(colors: [c(44, 54, 52), c(18, 23, 22), c(8, 11, 10)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: base, angle: -90)
// ambient mint light rising from below the wheel
NSGradient(colors: [mint.withAlphaComponent(0.30), mint.withAlphaComponent(0.06), mint.withAlphaComponent(0)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
    .draw(fromCenter: NSPoint(x: 512, y: 470), radius: 0, toCenter: NSPoint(x: 512, y: 470), radius: 470, options: [])
// faint top sheen
NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)

// MARK: Sound waves: three arcs per side, fading outward, with a soft glow
for (i, r) in [208.0, 272.0, 336.0].enumerated() {
    let a = [1.0, 0.62, 0.32][i]
    for dir in [0.0, 180.0] {
        let p = NSBezierPath()
        p.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: CGFloat(r), startAngle: dir - 31, endAngle: dir + 31)
        p.lineWidth = 24; p.lineCapStyle = .round
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 26, color: mint.withAlphaComponent(0.55 * CGFloat(a)).cgColor)
        mint.withAlphaComponent(CGFloat(a)).setStroke(); p.stroke()
        cg.restoreGState()
    }
}

// MARK: The wheel: a glass capsule
let wheelRect = NSRect(x: 512 - 122, y: 512 - 236, width: 244, height: 472)
let wheel = NSBezierPath(roundedRect: wheelRect, xRadius: 122, yRadius: 122)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: NSColor.black.withAlphaComponent(0.55).cgColor)
c(20, 25, 24).setFill(); wheel.fill()
cg.restoreGState()
cg.saveGState()
cg.setShadow(offset: .zero, blur: 56, color: mint.withAlphaComponent(0.5).cgColor)
c(20, 25, 24).setFill(); wheel.fill()
cg.restoreGState()

cg.saveGState()
wheel.addClip()
NSGradient(colors: [c(70, 84, 80), c(28, 35, 33), c(12, 16, 15)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: wheel, angle: -90)
// inner mint bloom behind the ticks
NSGradient(colors: [mint.withAlphaComponent(0.28), mint.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: 512, y: 512), radius: 0, toCenter: NSPoint(x: 512, y: 512), radius: 190, options: [])

// notch ticks: the middle one is the "click" and glows
for (i, dy) in [-156.0, -78.0, 0.0, 78.0, 156.0].enumerated() {
    let lit = i == 2
    let w: CGFloat = lit ? 140 : 104
    let t = NSBezierPath(roundedRect: NSRect(x: 512 - w / 2, y: 512 + CGFloat(dy) - 10, width: w, height: 20), xRadius: 10, yRadius: 10)
    cg.saveGState()
    if lit { cg.setShadow(offset: .zero, blur: 30, color: mint.cgColor) }
    (lit ? mintBright : mint.withAlphaComponent(0.30 - 0.05 * CGFloat(abs(i - 2)))).setFill()
    t.fill()
    cg.restoreGState()
}

// glass specular: a soft white crescent down the upper left
let spec = NSBezierPath(roundedRect: NSRect(x: 512 - 104, y: 512 + 40, width: 66, height: 180), xRadius: 33, yRadius: 33)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.34), NSColor.white.withAlphaComponent(0)])!.draw(in: spec, angle: -90)
cg.restoreGState()

// rim: mint gradient stroke
cg.saveGState()
wheel.lineWidth = 9
wheel.addClip()
cg.restoreGState()
cg.saveGState()
cg.setLineWidth(9)
let rim = NSBezierPath(roundedRect: wheelRect.insetBy(dx: 2, dy: 2), xRadius: 120, yRadius: 120)
rim.lineWidth = 9
mint.setStroke(); rim.stroke()
// bright catch-light on the rim's upper edge
let catchLight = NSBezierPath()
catchLight.appendArc(withCenter: NSPoint(x: 512, y: 512 + 114), radius: 120, startAngle: 40, endAngle: 140)
catchLight.lineWidth = 5; catchLight.lineCapStyle = .round
mintBright.setStroke(); catchLight.stroke()
cg.restoreGState()
cg.restoreGState()

// MARK: Glass edge on the squircle
let edge = NSBezierPath(roundedRect: NSRect(x: 101.5, y: 101.5, width: 821, height: 821), xRadius: 185, yRadius: 185)
edge.lineWidth = 3
NSGraphicsContext.saveGraphicsState()
edge.addClip()
let edgeGrad = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0.04), NSColor.white.withAlphaComponent(0.10)])!
c(255, 255, 255, 0.0).setStroke()
NSGraphicsContext.restoreGraphicsState()
c(255, 255, 255, 0.14).setStroke(); edge.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
_ = edgeGrad
