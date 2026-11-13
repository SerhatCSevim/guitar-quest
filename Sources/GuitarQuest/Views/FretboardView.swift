// Interactive fretboard. High e string on top, like tab. Port of web/js/fretboard.js (SVG → Canvas).
import SwiftUI
import MusicCore

enum MarkKind { case note, root, ghost, ring, target }

/// A mark on the fretboard. `color` is the dot (or ring) colour; `textColor` the label colour for filled dots.
struct FretMark: Identifiable, Equatable {
    var string: Int
    var fret: Int
    var label: String = ""
    var color: Color = Color(hex: 0x333333)
    var textColor: Color = .white
    var kind: MarkKind = .note
    var opacity: Double = 1          // ghost .28, soft .8, wrong .5
    var playing = false              // white stroke around the dot
    var pop = false                  // appear with a small scale animation
    var id: String { "\(string):\(fret):\(kind)" }

    /// A mark for a fretboard position, coloured by note (reference: GQ.noteMark).
    static func note(_ string: Int, _ fret: Int, settings: Settings, spelled: SpelledNote? = nil, label: String? = nil, kind: MarkKind = .note) -> FretMark {
        let midi = Theory.midiAt(string, fret)
        let pc = Theory.mod(midi, 12)
        let hex: UInt32 = settings.colors ? (spelled.map { Theme.spelledHex($0) } ?? Theme.pcHex(pc)) : Theme.plainNoteHex
        let nmShort: Naming = settings.naming == .both ? .letters : settings.naming
        let text = label ?? (spelled.map { Theory.noteLabel($0, nmShort) } ?? Theory.pcLabel(pc, nmShort, settings.accidentals))
        return FretMark(string: string, fret: fret, label: text, color: Color(hex: hex), textColor: Theme.inkOn(hex), kind: kind)
    }
}

struct FretFlash: Identifiable {
    let id = UUID()
    let string: Int
    let fret: Int
    let good: Bool
    let start: Date
}

struct FretboardGeometry {
    static let inlays = [3, 5, 7, 9, 15, 17, 19, 21]
    let W: Double = 1000
    let labelW: Double = 26
    let openW: Double = 48
    let nutX: Double
    let endX: Double
    let xs: [Double]
    let gap: Double
    let top: Double = 18
    let boardBottom: Double
    let H: Double
    let maxFret: Int

    init(maxFret: Int, compact: Bool, showNumbers: Bool) {
        self.maxFret = maxFret
        let nut = 26.0 + 48.0, end = 1000.0 - 14
        nutX = nut
        endX = end
        let mf = Double(maxFret)
        let L = (end - nut) / (1 - pow(2, -mf / 12))
        xs = (0...maxFret).map { nut + L * (1 - pow(2, -Double($0) / 12)) }
        gap = compact ? 21 : 26
        boardBottom = top + 5 * gap + top
        H = boardBottom + (showNumbers ? 22 : 4)
    }
    func cx(_ fret: Int) -> Double { fret == 0 ? nutX - openW / 2 : (xs[fret - 1] + xs[fret]) / 2 }
    func cy(_ string: Int) -> Double { top + Double(string - 1) * gap }
    var boardTop: Double { top - gap * 0.55 }
    var boardH: Double { 5 * gap + gap * 1.1 }

    /// Hit test in 1000-unit space.
    func position(at p: CGPoint) -> Position? {
        var string: Int? = nil
        for st in 1...6 where abs(p.y - cy(st)) <= gap / 2 { string = st; break }
        guard let st = string else { return nil }
        for f in 0...maxFret {
            let x0 = f == 0 ? labelW : xs[f - 1], x1 = f == 0 ? nutX - 4 : xs[f]
            if p.x >= x0 && p.x <= x1 { return Position(string: st, fret: f) }
        }
        return nil
    }
}

struct FretboardView: View {
    var maxFret: Int = 15
    var compact = false
    var showNumbers = true
    var interactive = true
    var marks: [FretMark] = []
    var highlightString: Int? = nil
    var onSelect: ((Int, Int) -> Void)? = nil
    @Binding var flashes: [FretFlash]

    init(maxFret: Int = 15, compact: Bool = false, showNumbers: Bool = true, interactive: Bool = true, marks: [FretMark] = [],
         highlightString: Int? = nil, flashes: Binding<[FretFlash]> = .constant([]), onSelect: ((Int, Int) -> Void)? = nil) {
        self.maxFret = max(12, min(22, maxFret)); self.compact = compact; self.showNumbers = showNumbers; self.interactive = interactive
        self.marks = marks; self.highlightString = highlightString; self._flashes = flashes; self.onSelect = onSelect
    }

    @State private var appeared: [String: Date] = [:]
    @State private var popAnimating = false

    private var geometry: FretboardGeometry { FretboardGeometry(maxFret: maxFret, compact: compact, showNumbers: showNumbers) }

    var body: some View {
        let g = geometry
        let animating = !flashes.isEmpty || popAnimating
        GeometryReader { geo in
            let s = geo.size.width / g.W
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !animating)) { tl in
                Canvas(rendersAsynchronously: false) { ctx, _ in
                    ctx.scaleBy(x: s, y: s)
                    draw(&ctx, g, now: tl.date)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                guard interactive, let p = g.position(at: CGPoint(x: loc.x / s, y: loc.y / s)) else { return }
                onSelect?(p.string, p.fret)
            }
        }
        .aspectRatio(g.W / g.H, contentMode: .fit)
        .frame(minWidth: compact ? 620 : 760)
        .onChange(of: marks.map(\.id)) { _, _ in
            let t = Date()
            var next: [String: Date] = [:]
            var newPop = false
            for m in marks {
                if appeared[m.id] == nil && m.pop { newPop = true }
                next[m.id] = appeared[m.id] ?? t
            }
            appeared = next
            if newPop {
                // run the 0.28 s pop animation, then let the TimelineView pause again
                popAnimating = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { popAnimating = false }
            }
        }
        .onAppear { let t = Date(); for m in marks { appeared[m.id] = t } }
    }

    private func draw(_ ctx: inout GraphicsContext, _ g: FretboardGeometry, now: Date) {
        let font = Font.system(size: 13, weight: .heavy)
        // open-string area and board
        ctx.fill(Path(roundedRect: CGRect(x: g.labelW, y: g.boardTop, width: g.openW, height: g.boardH), cornerRadius: 6), with: .color(Color(hex: 0xEFE7DA)))
        let board = CGRect(x: g.nutX, y: g.boardTop, width: g.endX - g.nutX, height: g.boardH)
        ctx.fill(Path(board), with: .linearGradient(Gradient(colors: [Color(hex: 0x6B4423), Color(hex: 0x5A371B), Color(hex: 0x4A2C15)]),
                                                     startPoint: CGPoint(x: 0, y: board.minY), endPoint: CGPoint(x: 0, y: board.maxY)))
        // inlays
        for f in FretboardGeometry.inlays + [12] where f <= g.maxFret {
            let x = g.cx(f)
            let dots: [Double] = f == 12 ? [g.cy(2) + g.gap / 2, g.cy(4) + g.gap / 2] : [g.cy(3) + g.gap / 2]
            for y in dots {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11)), with: .color(Color(hex: 0xF3EAD6).opacity(0.85)))
            }
        }
        // frets and nut
        for n in 1...g.maxFret {
            ctx.fill(Path(CGRect(x: g.xs[n] - 1.6, y: g.boardTop, width: 3.2, height: g.boardH)), with: .color(Color(hex: 0xC8CBD0)))
        }
        let nut = Path(roundedRect: CGRect(x: g.nutX - 5, y: g.boardTop - 1, width: 7, height: g.boardH + 2), cornerRadius: 1.5)
        ctx.fill(nut, with: .color(Color(hex: 0xF4EBDC)))
        ctx.stroke(nut, with: .color(Color(hex: 0xCFC3AE)), lineWidth: 1)
        // highlighted string band (behind strings)
        if let hs = highlightString {
            let band = Path(roundedRect: CGRect(x: g.labelW, y: g.cy(hs) - g.gap * 0.43, width: g.endX - g.labelW, height: g.gap * 0.86), cornerRadius: g.gap * 0.43)
            ctx.fill(band, with: .color(Color(red: 1, green: 210 / 255, blue: 122 / 255).opacity(0.22)))
        }
        // strings
        for st in 1...6 {
            let y = g.cy(st)
            let w = 0.9 + Double(st - 1) * 0.42
            var p = Path(); p.move(to: CGPoint(x: g.labelW + 4, y: y)); p.addLine(to: CGPoint(x: g.endX, y: y))
            let col: Color = highlightString == st ? Color(hex: 0xFFD27A) : (st >= 4 ? Color(hex: 0xD9C7A0) : Color(hex: 0xE6E1D6))
            ctx.stroke(p, with: .color(col), lineWidth: w)
            ctx.draw(Text(Theory.OPEN_NAMES[st]).font(font).foregroundColor(Color(hex: 0x6B7080)), at: CGPoint(x: g.labelW / 2, y: y), anchor: .center)
        }
        if showNumbers {
            for n in 0...g.maxFret {
                let dot = FretboardGeometry.inlays.contains(n) || n == 12
                let t = Text(n == 0 ? "open" : String(n)).font(.system(size: 11, weight: dot ? .heavy : .semibold)).foregroundColor(dot ? Color(hex: 0x4A5163) : Color(hex: 0x9AA0AD))
                ctx.draw(t, at: CGPoint(x: g.cx(n), y: g.H - 9), anchor: .center)
            }
        }
        // marks
        let r: Double = compact ? 9.5 : 11.5
        for m in marks where m.fret <= g.maxFret {
            let x = g.cx(m.fret), y = g.cy(m.string)
            var mctx = ctx
            mctx.opacity = m.opacity
            if m.pop, let t0 = appeared[m.id] {
                let u = min(1, now.timeIntervalSince(t0) / 0.28)
                let scale = u < 0.7 ? 0.4 + (1.15 - 0.4) * (u / 0.7) : 1.15 - 0.15 * ((u - 0.7) / 0.3)
                mctx.translateBy(x: x, y: y); mctx.scaleBy(x: scale, y: scale); mctx.translateBy(x: -x, y: -y)
            }
            if m.kind == .ring || m.kind == .target {
                let p = Path(ellipseIn: CGRect(x: x - (r + 1), y: y - (r + 1), width: 2 * (r + 1), height: 2 * (r + 1)))
                let style = m.kind == .target ? StrokeStyle(lineWidth: 3, dash: [4, 3]) : StrokeStyle(lineWidth: 3)
                mctx.stroke(p, with: .color(m.color), style: style)
            } else {
                if m.kind == .root {
                    mctx.stroke(Path(ellipseIn: CGRect(x: x - (r + 3), y: y - (r + 3), width: 2 * (r + 3), height: 2 * (r + 3))), with: .color(.white), lineWidth: 2.4)
                }
                let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                var shadow = mctx
                shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, y: 1))
                shadow.fill(dot, with: .color(m.color))
                if m.playing { mctx.stroke(dot, with: .color(.white), lineWidth: 3) }
            }
            if !m.label.isEmpty && m.kind != .ghost {
                let n = m.label.count
                let size: Double = n > 2 ? (n > 4 ? 7 : 9) : 12
                let col = (m.kind == .ring || m.kind == .target) ? m.color : m.textColor
                mctx.draw(Text(m.label).font(.system(size: size, weight: .heavy)).foregroundColor(col), at: CGPoint(x: x, y: y), anchor: .center)
            }
        }
        // flashes (green/red expanding ring)
        for f in flashes {
            let u = now.timeIntervalSince(f.start) / 0.7
            if u > 1 { continue }
            let scale = 0.8 + 1.4 * u
            let rr = 13 * scale
            var fctx = ctx
            fctx.opacity = 1 - u
            fctx.stroke(Path(ellipseIn: CGRect(x: g.cx(f.fret) - rr, y: g.cy(f.string) - rr, width: 2 * rr, height: 2 * rr)),
                        with: .color(f.good ? Color(hex: 0x6EE7A0) : Color(hex: 0xFF7A7A)), lineWidth: 4)
        }
        if flashes.contains(where: { now.timeIntervalSince($0.start) > 0.8 }) {
            DispatchQueue.main.async { flashes.removeAll { Date().timeIntervalSince($0.start) > 0.8 } }
        }
    }
}
