// Chord diagram. Port of web/js/chords.js diagramSVG (SVG → Canvas).
import SwiftUI
import MusicCore

struct ChordDiagramView: View {
    var voicing: Voicing
    var title: String? = nil
    var width: CGFloat = 120
    var highlightRoot = true

    private var s: CGFloat { width / 120 }
    private var W: CGFloat { 132 * s }
    private var metrics: (top: CGFloat, fh: CGFloat, base: Int, rows: Int, H: CGFloat) {
        let top = (title != nil ? 40 : 18) * s, fh = 19 * s
        let fretted = voicing.frets.filter { $0 > 0 }
        let maxF = fretted.max() ?? 0, minF = fretted.min() ?? 0
        let base = maxF <= 4 ? 1 : minF
        let rows = max(4, maxF - base + 1)
        return (top, fh, base, rows, top + CGFloat(rows) * fh + 14 * s)
    }

    var body: some View {
        let m = metrics
        Canvas { ctx, _ in draw(&ctx, m) }
            .frame(width: W, height: m.H)
    }

    private func draw(_ ctx: inout GraphicsContext, _ m: (top: CGFloat, fh: CGFloat, base: Int, rows: Int, H: CGFloat)) {
        let left = 22 * s, gap = 15 * s
        let rootPc = Theory.notePc(voicing.root)
        if let title {
            ctx.draw(Text(title).font(.system(size: 19 * s, weight: .black)).foregroundColor(Theme.ink), at: CGPoint(x: left + 2.5 * gap, y: 22 * s - 6 * s), anchor: .center)
        }
        for i in 0..<6 {
            let x = left + CGFloat(i) * gap
            var p = Path(); p.move(to: CGPoint(x: x, y: m.top)); p.addLine(to: CGPoint(x: x, y: m.top + CGFloat(m.rows) * m.fh))
            ctx.stroke(p, with: .color(Color(hex: 0x6B7080)), lineWidth: (1 + CGFloat(5 - i) * 0.18) * s)
        }
        for r in 0...m.rows {
            let y = m.top + CGFloat(r) * m.fh
            let nut = r == 0 && m.base == 1
            var p = Path(); p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: left + 5 * gap, y: y))
            ctx.stroke(p, with: .color(nut ? Theme.ink : Color(hex: 0xA3A8B4)), lineWidth: (nut ? 5 : 1.2) * s)
        }
        if m.base > 1 {
            ctx.draw(Text("\(m.base)fr").font(.system(size: 11 * s, weight: .bold)).foregroundColor(Theme.muted),
                     at: CGPoint(x: left + 5 * gap + 11 * s, y: m.top + m.fh * 0.5), anchor: .leading)
        }
        // barre: finger 1 on the same fret across several strings
        if let fingers = voicing.fingers {
            let ones = voicing.frets.enumerated().filter { $0.element > 0 && fingers[$0.offset] == 1 }
            if let minOne = ones.map({ $0.element }).min() {
                let atMin = ones.filter { $0.element == minOne }
                if atMin.count >= 2 {
                    let i0 = atMin.map { $0.offset }.min()!, i1 = atMin.map { $0.offset }.max()!
                    let y = m.top + (CGFloat(minOne - m.base) + 0.5) * m.fh
                    let rect = CGRect(x: left + CGFloat(i0) * gap - 6 * s, y: y - 6 * s, width: CGFloat(i1 - i0) * gap + 12 * s, height: 12 * s)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 6 * s), with: .color(Theme.ink))
                }
            }
        }
        for (i, f) in voicing.frets.enumerated() {
            let x = left + CGFloat(i) * gap
            if f < 0 {
                let y = m.top - 9 * s, d = 4 * s
                var p = Path()
                p.move(to: CGPoint(x: x - d, y: y - d)); p.addLine(to: CGPoint(x: x + d, y: y + d))
                p.move(to: CGPoint(x: x + d, y: y - d)); p.addLine(to: CGPoint(x: x - d, y: y + d))
                ctx.stroke(p, with: .color(Color(hex: 0x6B7080)), lineWidth: 1.6 * s)
                continue
            }
            let midi = Theory.midiAt(6 - i, f)
            let isRoot = Theory.mod(midi, 12) == rootPc && highlightRoot
            if f == 0 {
                let rr = 4.5 * s
                let p = Path(ellipseIn: CGRect(x: x - rr, y: m.top - 9 * s - rr, width: 2 * rr, height: 2 * rr))
                ctx.fill(p, with: .color(.white))
                ctx.stroke(p, with: .color(isRoot ? Theme.bad : Theme.ink), lineWidth: 1.5 * s)
                continue
            }
            let y = m.top + (CGFloat(f - m.base) + 0.5) * m.fh
            let rr = 7 * s
            ctx.fill(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: 2 * rr, height: 2 * rr)), with: .color(isRoot ? Theme.bad : Theme.ink))
            if let fingers = voicing.fingers, fingers[i] != 0 {
                ctx.draw(Text(String(fingers[i])).font(.system(size: 10.5 * s, weight: .heavy)).foregroundColor(.white), at: CGPoint(x: x, y: y), anchor: .center)
            }
        }
    }
}
