// Score renderer: standard notation (treble clef, guitar written an octave up) + tablature.
// Port of the drawing half of web/js/notation.js (SVG → Canvas). Layout comes from MusicCore.Notation.
import SwiftUI
import MusicCore

// MARK: - drawing

struct NotationDrawer {
    let L: ScoreLayout
    var active: Int?
    var next: Int?

    static let ink = Theme.ink
    static let staffLine = Color(hex: 0x2B2F3A)
    static let tabLine = Color(hex: 0xA3A8B4)
    static let barNum = Color(hex: 0x9AA0AD)
    static let tuplet = Color(hex: 0x4A5163)

    var SP: Double { Notation.SP }
    var HRX: Double { Notation.HRX }
    var HRY: Double { Notation.HRY }
    var TS: Double { Notation.TS }
    var STEM: Double { Notation.STEM }
    func y(_ pos: Int) -> Double { L.yOf(pos) }
    func y(_ pos: Double) -> Double { L.yOf(pos) }

    func line(_ ctx: inout GraphicsContext, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: Color, _ w: Double) {
        var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2))
        ctx.stroke(p, with: .color(color), lineWidth: w)
    }

    func drawSystem(_ ctx: inout GraphicsContext, _ si: Int) {
        let sys = L.systems[si]
        let o = L.opts
        let ks = L.score.keySig
        let xL = 6.0, xR = sys.right
        // cursor (behind everything)
        if let a = active, a >= 0, a < L.prep.count, L.prep[a].system == si {
            let top = o.showStaff ? L.staffTop - 30 : L.tabTop - 16
            let bottom = (L.namesY ?? (o.showTab ? L.tabBottom : L.staffBottom)) + 12
            let rect = CGRect(x: L.prep[a].x - 15, y: top, width: 30, height: bottom - top)
            let p = Path(roundedRect: rect, cornerRadius: 6)
            ctx.fill(p, with: .color(Theme.accent.opacity(0.14)))
            ctx.stroke(p, with: .color(Theme.accent.opacity(0.45)), lineWidth: 1)
        }
        // ---- staff
        if o.showStaff {
            for p in stride(from: 0, through: 8, by: 2) { line(&ctx, xL, y(p), xR, y(p), Self.staffLine, 1) }
            drawClef(&ctx, xL + 3, y(2))
            var x = xL + 38
            let SH = [8, 5, 9, 6, 3, 7, 4], FL = [4, 7, 3, 6, 2, 5, 1]
            for k in ks.list.indices {
                let pos = ks.fifths > 0 ? SH[k] : FL[k]
                accGlyph(&ctx, ks.fifths > 0 ? 1 : -1, x + 4, y(pos))
                x += 9.5
            }
            if sys.first {
                x += ks.list.isEmpty ? 0 : 6
                let f = Font.custom("Georgia", size: 23).weight(.heavy)
                ctx.draw(Text("4").font(f).foregroundColor(Self.ink), at: CGPoint(x: x + 9, y: y(6)), anchor: .center)
                ctx.draw(Text("4").font(f).foregroundColor(Self.ink), at: CGPoint(x: x + 9, y: y(2)), anchor: .center)
            }
        }
        // ---- tab
        if o.showTab {
            for st in 1...6 {
                let yy = L.tabTop + Double(st - 1) * TS
                line(&ctx, xL, yy, xR, yy, Self.tabLine, 1)
            }
            for (k, c) in ["T", "A", "B"].enumerated() {
                let cy = L.tabTop + 14 + Double(k) * 17 - 5
                // white halo so the lines don't cross the letters
                ctx.fill(Path(roundedRect: CGRect(x: xL + 12 - 7, y: cy - 8, width: 14, height: 16), cornerRadius: 4), with: .color(.white))
                ctx.draw(Text(c).font(.system(size: 15, weight: .black)).foregroundColor(Self.staffLine), at: CGPoint(x: xL + 12, y: cy), anchor: .center)
            }
        }
        // ---- bar lines
        let barTop = o.showStaff ? L.staffTop : L.tabTop
        let barBot = o.showTab ? L.tabBottom : L.staffBottom
        let lastSys = si == L.systems.count - 1
        line(&ctx, xL, barTop, xL, barBot, Self.staffLine, 1.2)
        for (k, b) in sys.bars.enumerated() {
            let isEnd = lastSys && k == sys.bars.count - 1
            if isEnd {
                line(&ctx, b.x1 - 5, barTop, b.x1 - 5, barBot, Self.staffLine, 1.2)
                ctx.fill(Path(CGRect(x: b.x1 - 3, y: barTop, width: 3.4, height: barBot - barTop)), with: .color(Self.staffLine))
            } else {
                line(&ctx, b.x1, barTop, b.x1, barBot, Self.staffLine, 1.2)
            }
            if L.score.measures.count > 1 {
                ctx.draw(Text(String(b.m + 1)).font(.system(size: 10).italic()).foregroundColor(Self.barNum),
                         at: CGPoint(x: b.x0 + 3, y: barTop - (o.showStaff ? 26 : 8) - 4), anchor: .leading)
            }
        }
        // ---- events
        for i in sys.events { drawEvent(&ctx, i) }
        // beams and tuplets for groups in this system
        for g in L.beams.all {
            if L.prep[g.items[0]].system != si { continue }
            if g.items.count > 1 && o.showStaff { drawBeam(&ctx, g) }
            if g.items.count > 1 && !o.showStaff && o.showTab { drawTabBeam(&ctx, g) }
            if g.tuplet == 3 { drawTupletMark(&ctx, g) }
        }
    }

    func drawClef(_ ctx: inout GraphicsContext, _ x: Double, _ yG: Double) {
        // Treble clef glyph (U+1D11E) from Apple Symbols, anchored on the G line.
        let t = Text("\u{1D11E}").font(.custom("Apple Symbols", size: 58)).foregroundColor(Self.ink)
        let r = ctx.resolve(t)
        let size = r.measure(in: CGSize(width: 200, height: 200))
        // the glyph's visual centre sits a little above the G line; tuned against the web rendering
        ctx.draw(r, at: CGPoint(x: x + size.width / 2 - 2, y: yG - 4), anchor: .center)
    }

    func drawEvent(_ ctx: inout GraphicsContext, _ i: Int) {
        let o = L.opts
        let p = L.prep[i]
        let ev = p.ev
        let x = p.x
        let isActive = active == i
        if o.showStaff {
            if ev.rest { drawRest(&ctx, p) } else { drawNotes(&ctx, i) }
        }
        if o.showTab && !ev.rest {
            for n in ev.notes {
                let yy = L.tabTop + Double(n.string - 1) * TS
                let txt = String(n.fret)
                let w = 7.5 * Double(txt.count) + 3
                ctx.fill(Path(CGRect(x: x - w / 2, y: yy - 7, width: w, height: 14)), with: .color(isActive ? Color(hex: 0xFFF3EC) : .white))
                let col: Color = isActive ? Theme.accent : (next == i ? Theme.teal : Self.ink)
                ctx.draw(Text(txt).font(.system(size: 13, weight: .heavy)).foregroundColor(col), at: CGPoint(x: x, y: yy), anchor: .center)
            }
        }
        if o.showNames && !ev.rest, let ny = L.namesY {
            var t = Text("")
            for (k, n) in ev.notes.enumerated() {
                let c = o.colors ? Theme.spelledColor(n.spelled) : Color(hex: 0x455A64)
                let label = Theory.noteLabel(n.spelled, o.naming == .both ? .letters : o.naming)
                var piece = Text(label).foregroundColor(c)
                if isActive { piece = piece.underline() }
                t = k == 0 ? piece : t + Text(" ") + piece
            }
            ctx.draw(t.font(.system(size: 12, weight: .heavy)), at: CGPoint(x: x, y: ny - 4), anchor: .center)
        }
        if !o.showStaff && o.showTab && !ev.rest { drawTabRhythm(&ctx, i) }
    }

    func headColor(_ hd: PreparedHead) -> Color? { L.opts.colors ? Theme.spelledColor(hd.spelled) : nil }

    func drawNotes(_ ctx: inout GraphicsContext, _ i: Int) {
        let p = L.prep[i]
        let x = p.x
        let isActive = active == i
        let group = Notation.group(for: i, in: L)
        let dir: StemDirection = group?.dir ?? Notation.stemDir(p.heads)
        let sorted = p.heads.sorted { $0.pos < $1.pos }
        let minPos = sorted.first!.pos, maxPos = sorted.last!.pos
        // ledger lines
        var lp = -2
        while lp >= minPos { line(&ctx, x - 10, y(lp), x + 10, y(lp), Self.staffLine, 1.2); lp -= 2 }
        lp = 10
        while lp <= maxPos { line(&ctx, x - 10, y(lp), x + 10, y(lp), Self.staffLine, 1.2); lp += 2 }
        // heads (seconds inside a chord are pushed to the side)
        var prevShifted = false
        for (k, hd) in sorted.enumerated() {
            let yy = y(hd.pos)
            let isSecond = k > 0 && hd.pos - sorted[k - 1].pos == 1 && !prevShifted
            let shift: Double = isSecond ? (dir == .up ? 2 * HRX - 0.5 : -(2 * HRX - 0.5)) : 0
            prevShifted = shift != 0
            let hx = x + shift
            if let acc = hd.acc { accGlyph(&ctx, acc, x - 15, yy) }
            let col = isActive ? Theme.accent : (headColor(hd) ?? Self.ink)
            switch p.nv.head {
            case .whole:
                let e = Path(ellipseIn: CGRect(x: hx - (HRX + 1.3), y: yy - HRY, width: 2 * (HRX + 1.3), height: 2 * HRY))
                ctx.fill(e, with: .color(.white)); ctx.stroke(e, with: .color(col), lineWidth: 2.6)
            case .half:
                let e = ellipse(hx, yy, HRX, HRY - 0.4, rotate: -22)
                ctx.fill(e, with: .color(.white)); ctx.stroke(e, with: .color(col), lineWidth: 2)
            case .black:
                ctx.fill(ellipse(hx, yy, HRX, HRY, rotate: -22), with: .color(col))
            }
            if p.nv.dots > 0 {
                let dy: Double = hd.pos % 2 == 0 ? -SP / 2 : 0
                ctx.fill(Path(ellipseIn: CGRect(x: hx + HRX + 5 - 1.9, y: yy + dy - 1.9, width: 3.8, height: 3.8)), with: .color(Self.ink))
            }
        }
        if p.nv.head == .whole { return }
        // stem
        let yLow = y(minPos), yHigh = y(maxPos), yMid = y(4)
        var sx: Double, y0: Double, y1: Double
        if dir == .up {
            sx = x + HRX - 0.7; y0 = yLow; y1 = min(yHigh - STEM, yMid)
        } else {
            sx = x - HRX + 0.7; y0 = yHigh; y1 = max(yLow + STEM, yMid)
        }
        if let g = group, g.hasStem { y1 = g.stemEnd(sx) }
        line(&ctx, sx, y0, sx, y1, Self.ink, 1.3)
        if group == nil && p.nv.flags > 0 {
            for k in 0..<p.nv.flags { flag(&ctx, sx, y1 + (dir == .up ? Double(k) * 7 : -Double(k) * 7), dir) }
        }
    }

    func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, rotate deg: Double) -> Path {
        var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: deg * .pi / 180)
        t = t.translatedBy(x: -cx, y: -cy)
        return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)).applying(t)
    }

    func flag(_ ctx: inout GraphicsContext, _ x: Double, _ yy: Double, _ dir: StemDirection) {
        var p = Path()
        let s: Double = dir == .up ? 1 : -1
        p.move(to: CGPoint(x: x, y: yy))
        p.addCurve(to: CGPoint(x: x + 7.5, y: yy + s * 21), control1: CGPoint(x: x + 1, y: yy + s * 7), control2: CGPoint(x: x + 10.5, y: yy + s * 9))
        p.addCurve(to: CGPoint(x: x, y: yy + s * 9.5), control1: CGPoint(x: x + 8.5, y: yy + s * 12.5), control2: CGPoint(x: x + 3, y: yy + s * 10.5))
        p.closeSubpath()
        ctx.fill(p, with: .color(Self.ink))
    }

    func drawBeam(_ ctx: inout GraphicsContext, _ g: BeamGroup) {
        let up = g.dir == .up
        let items = g.items.map { L.prep[$0] }
        let th = 4.6
        func seg(_ xa: Double, _ xb: Double, _ off: Double) {
            let ya = g.stemEnd(xa) + (up ? off : -off), yb = g.stemEnd(xb) + (up ? off : -off)
            let t = up ? th : -th
            var p = Path()
            p.move(to: CGPoint(x: xa, y: ya)); p.addLine(to: CGPoint(x: xb, y: yb))
            p.addLine(to: CGPoint(x: xb, y: yb + t)); p.addLine(to: CGPoint(x: xa, y: ya + t)); p.closeSubpath()
            ctx.fill(p, with: .color(Self.ink))
        }
        seg(g.x0 - 0.6, g.x1 + 0.6, 0)
        // secondary beams for sixteenths
        var k = 0
        while k < items.count {
            if items[k].nv.flags < 2 { k += 1; continue }
            var j = k
            while j + 1 < items.count && items[j + 1].nv.flags >= 2 { j += 1 }
            let xa = Notation.stemX(items[k], up), xb = Notation.stemX(items[j], up)
            if j > k { seg(xa - 0.6, xb + 0.6, 7.2) }
            else if k == items.count - 1 { seg(xa - 8, xa, 7.2) }
            else { seg(xa, xa + 8, 7.2) }
            k = j + 1
        }
    }

    func drawTupletMark(_ ctx: inout GraphicsContext, _ g: BeamGroup) {
        let items = g.items.map { L.prep[$0] }
        let xm = (items[0].x + items[items.count - 1].x) / 2
        let f = Font.system(size: 11, weight: .heavy).italic()
        let yy: Double
        if L.opts.showStaff && g.items.count > 1 && g.hasStem {
            let up = g.dir == .up
            yy = g.stemEnd(xm) + (up ? -7 : 16) - 4
        } else {
            yy = (L.opts.showStaff ? L.staffTop - 10 : (L.rhythmTop.map { $0 + 42 } ?? L.tabTop - 6)) - 4
        }
        ctx.draw(Text("3").font(f).foregroundColor(Self.tuplet), at: CGPoint(x: xm, y: yy), anchor: .center)
    }

    func drawRest(_ ctx: inout GraphicsContext, _ p: PreparedEvent) {
        let x = p.x
        let d = p.ev.tuplet == 3 ? p.ev.dur * 3 / 2 : p.ev.dur
        if d >= 48 { ctx.fill(Path(CGRect(x: x - 6, y: y(6), width: 12, height: 5)), with: .color(Self.ink)); return }
        if d >= 24 { ctx.fill(Path(CGRect(x: x - 6, y: y(4) - 5, width: 12, height: 5)), with: .color(Self.ink)); return }
        if d >= 12 {
            var q = Path()
            q.move(to: CGPoint(x: x - 2.5, y: y(7.6)))
            q.addLine(to: CGPoint(x: x + 3.5, y: y(5.8)))
            q.addLine(to: CGPoint(x: x - 1.8, y: y(4.2)))
            q.addLine(to: CGPoint(x: x + 3.4, y: y(2.6)))
            q.addQuadCurve(to: CGPoint(x: x + 0.8, y: y(0.6)), control: CGPoint(x: x - 4.5, y: y(2.3)))
            ctx.stroke(q, with: .color(Self.ink), style: StrokeStyle(lineWidth: 2.6, lineJoin: .miter))
            return
        }
        let flags = d >= 6 ? 1 : 2
        for k in 0..<flags {
            let yy = y(5) + Double(k) * 8
            let cx = x - 2 - Double(k) * 1.5
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.6, y: yy - 2.6, width: 5.2, height: 5.2)), with: .color(Self.ink))
            var s = Path()
            s.move(to: CGPoint(x: cx, y: yy + 1.6))
            s.addQuadCurve(to: CGPoint(x: x + 3.6 - Double(k) * 1.5, y: yy - 1.5), control: CGPoint(x: x + 1, y: yy + 3))
            ctx.stroke(s, with: .color(Self.ink), lineWidth: 1.5)
        }
        var s = Path()
        s.move(to: CGPoint(x: x + 3.6, y: y(5) - 1.5))
        s.addLine(to: CGPoint(x: x - 1.2 - Double(flags - 1) * 2, y: y(5) + 15 + Double(flags - 1) * 6))
        ctx.stroke(s, with: .color(Self.ink), lineWidth: 1.5)
    }

    // Rhythm stems under the tab (used when the staff is hidden).
    func drawTabRhythm(_ ctx: inout GraphicsContext, _ i: Int) {
        let p = L.prep[i]
        guard p.nv.head != .whole, let y0 = L.rhythmTop else { return }
        let x = p.x, len: Double = p.nv.head == .half ? 14 : 24
        line(&ctx, x, y0, x, y0 + len, Self.ink, 1.3)
        if p.nv.dots > 0 { ctx.fill(Path(ellipseIn: CGRect(x: x + 5 - 1.8, y: y0 + len - 3 - 1.8, width: 3.6, height: 3.6)), with: .color(Self.ink)) }
        if Notation.group(for: i, in: L) == nil && p.nv.flags > 0 {
            for k in 0..<p.nv.flags { flag(&ctx, x, y0 + len - Double(k) * 7, .down) }
        }
    }

    func drawTabBeam(_ ctx: inout GraphicsContext, _ g: BeamGroup) {
        guard let rt = L.rhythmTop else { return }
        let items = g.items.map { L.prep[$0] }
        let yy = rt + 24
        let x0 = items[0].x - 0.6, w = items[items.count - 1].x - items[0].x + 1.2
        ctx.fill(Path(CGRect(x: x0, y: yy - 4, width: w, height: 4)), with: .color(Self.ink))
        if items.allSatisfy({ $0.nv.flags >= 2 }) { ctx.fill(Path(CGRect(x: x0, y: yy - 10, width: w, height: 4)), with: .color(Self.ink)) }
    }

    // MARK: accidental glyphs (drawn paths, so no music font is needed)

    func accGlyph(_ ctx: inout GraphicsContext, _ a: Int, _ x: Double, _ yy: Double) {
        switch a {
        case 1: sharp(&ctx, x, yy)
        case -1: flat(&ctx, x, yy)
        case 0: natural(&ctx, x, yy)
        case 2: ctx.draw(Text("x").font(.system(size: 14, weight: .heavy)).foregroundColor(Self.ink), at: CGPoint(x: x, y: yy), anchor: .center)
        case -2: flat(&ctx, x - 4, yy); flat(&ctx, x + 3, yy)
        default: break
        }
    }

    func sharp(_ ctx: inout GraphicsContext, _ x: Double, _ yy: Double) {
        var v = Path()
        v.move(to: CGPoint(x: x - 2, y: yy - 10)); v.addLine(to: CGPoint(x: x - 2, y: yy + 9))
        v.move(to: CGPoint(x: x + 2, y: yy - 9)); v.addLine(to: CGPoint(x: x + 2, y: yy + 10))
        ctx.stroke(v, with: .color(Self.ink), lineWidth: 1.2)
        var f = Path()
        f.move(to: CGPoint(x: x - 4.6, y: yy - 1.6)); f.addLine(to: CGPoint(x: x + 4.6, y: yy - 4.6)); f.addLine(to: CGPoint(x: x + 4.6, y: yy - 2.2)); f.addLine(to: CGPoint(x: x - 4.6, y: yy + 0.8)); f.closeSubpath()
        f.move(to: CGPoint(x: x - 4.6, y: yy + 4.6)); f.addLine(to: CGPoint(x: x + 4.6, y: yy + 1.6)); f.addLine(to: CGPoint(x: x + 4.6, y: yy + 4)); f.addLine(to: CGPoint(x: x - 4.6, y: yy + 7)); f.closeSubpath()
        ctx.fill(f, with: .color(Self.ink))
    }

    func flat(_ ctx: inout GraphicsContext, _ x: Double, _ yy: Double) {
        var v = Path()
        v.move(to: CGPoint(x: x - 3, y: yy - 13)); v.addLine(to: CGPoint(x: x - 3, y: yy + 4.5))
        ctx.stroke(v, with: .color(Self.ink), lineWidth: 1.3)
        var b = Path()
        b.move(to: CGPoint(x: x - 3, y: yy + 4.5))
        b.addCurve(to: CGPoint(x: x - 3, y: yy - 2), control1: CGPoint(x: x + 6.5, y: yy - 0.5), control2: CGPoint(x: x + 4.5, y: yy - 7.5))
        b.addLine(to: CGPoint(x: x - 3, y: yy - 0.4))
        b.addCurve(to: CGPoint(x: x - 3, y: yy + 4.5), control1: CGPoint(x: x + 2.8, y: yy - 4.2), control2: CGPoint(x: x + 3.2, y: yy + 0.2))
        b.closeSubpath()
        ctx.fill(b, with: .color(Self.ink))
    }

    func natural(_ ctx: inout GraphicsContext, _ x: Double, _ yy: Double) {
        var v = Path()
        v.move(to: CGPoint(x: x - 2.6, y: yy - 10)); v.addLine(to: CGPoint(x: x - 2.6, y: yy + 4))
        v.move(to: CGPoint(x: x + 2.6, y: yy - 4)); v.addLine(to: CGPoint(x: x + 2.6, y: yy + 10))
        ctx.stroke(v, with: .color(Self.ink), lineWidth: 1.2)
        var f = Path()
        f.move(to: CGPoint(x: x - 2.6, y: yy - 2.4)); f.addLine(to: CGPoint(x: x + 2.6, y: yy - 4.6)); f.addLine(to: CGPoint(x: x + 2.6, y: yy - 2.2)); f.addLine(to: CGPoint(x: x - 2.6, y: yy)); f.closeSubpath()
        f.move(to: CGPoint(x: x - 2.6, y: yy + 4)); f.addLine(to: CGPoint(x: x + 2.6, y: yy + 1.8)); f.addLine(to: CGPoint(x: x + 2.6, y: yy + 4.2)); f.addLine(to: CGPoint(x: x - 2.6, y: yy + 6.4)); f.closeSubpath()
        ctx.fill(f, with: .color(Self.ink))
    }
}
