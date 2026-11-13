// Draws the Guitar Quest app icon (same artwork as the web icon: dark rounded square + orange pick + three white
// lines) into an .iconset folder. Usage: IconMaker <output.iconset>   (then: iconutil -c icns <output.iconset>)
import AppKit
import Foundation

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ S: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(S)
    // flip to a top-left origin like the SVG
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.addPath(bg); ctx.setFillColor(CGColor(red: 30 / 255, green: 34 / 255, blue: 48 / 255, alpha: 1)); ctx.fillPath()
    // pick: M32 4 C18 4 8 12 8 24 c0 14 14 30 24 36 10-6 24-22 24-36 C56 12 46 4 32 4z (56 units high → 74 % of the icon)
    let scale = s * 0.74 / 56
    let ox = s / 2 - 32 * scale, oy = s / 2 - 32 * scale
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }
    let pick = CGMutablePath()
    pick.move(to: P(32, 4))
    pick.addCurve(to: P(8, 24), control1: P(18, 4), control2: P(8, 12))
    pick.addCurve(to: P(32, 60), control1: P(8, 38), control2: P(22, 54))
    pick.addCurve(to: P(56, 24), control1: P(42, 54), control2: P(56, 38))
    pick.addCurve(to: P(32, 4), control1: P(56, 12), control2: P(46, 4))
    pick.closeSubpath()
    ctx.addPath(pick); ctx.setFillColor(CGColor(red: 224 / 255, green: 103 / 255, blue: 43 / 255, alpha: 1)); ctx.fillPath()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.setLineWidth(3.6 * scale); ctx.setLineCap(.round)
    let lines: [((CGFloat, CGFloat), (CGFloat, CGFloat))] = [((22, 26), (42, 26)), ((24, 34), (40, 34)), ((28, 42), (36, 42))]
    for (a, b) in lines {
        ctx.move(to: P(a.0, a.1)); ctx.addLine(to: P(b.0, b.1)); ctx.strokePath()
    }
    return ctx.makeImage()!
}

for base in [16, 32, 128, 256, 512] {
    for (suffix, mult) in [("", 1), ("@2x", 2)] {
        let img = draw(base * mult)
        let rep = NSBitmapImageRep(cgImage: img)
        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: out.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
print("iconset written to \(out.path)")
