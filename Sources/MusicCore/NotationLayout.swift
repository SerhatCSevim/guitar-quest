// Guitar Quest - score layout (pure geometry, no drawing). Port of the layout half of web/js/notation.js:
// noteValue, prepare, evWidth, beamGroups, layout, prepareBeams. Drawing lives in the app (NotationView).
import Foundation

public enum HeadKind: String, Codable, Sendable { case whole, half, black }

public struct Glyph: Hashable, Codable, Sendable {
    public var head: HeadKind
    public var flags: Int
    public var dots: Int
    public init(head: HeadKind, flags: Int, dots: Int) { self.head = head; self.flags = flags; self.dots = dots }
}

public struct PreparedHead: Hashable, Sendable {
    public var pos: Int
    public var acc: Int?          // accidental printed before the head (nil = none; 0 = natural sign)
    public var spelled: SpelledNote
    public var string: Int
    public var fret: Int
    public var midi: Int
}

public struct PreparedEvent: Hashable, Sendable {
    public var ev: ScoreEvent
    public var nv: Glyph
    public var heads: [PreparedHead]
    public var hasAcc: Bool
    // filled by layout()
    public var x: Double = 0
    public var slot: (Double, Double) { (slot0, slot1) }
    public var slot0: Double = 0
    public var slot1: Double = 0
    public var system: Int = 0
}

public struct BeamGroup: Hashable, Sendable {
    public var beat: Int
    public var tuplet: Int
    public var items: [Int]
    public var last: Int
    // filled by prepareBeams() for groups with 2+ items
    public var dir: StemDirection? = nil
    public var hasStem = false
    public var base: Double = 0
    public var slope: Double = 0
    public var x0: Double = 0
    public var x1: Double = 0
    public func stemEnd(_ x: Double) -> Double { base + slope * (x - x0) }
}

public enum StemDirection: String, Sendable { case up, down }

public struct SystemBar: Hashable, Sendable {
    public var m: Int
    public var x0: Double
    public var x1: Double
    /// Time signature to print at the start of this measure (only where it changes).
    public var timeSig: [Int]? = nil
}

public struct ScoreSystem: Hashable, Sendable {
    public var measures: [Int]
    public var width: Double
    public var header: Double
    public var first: Bool
    public var scale: Double = 1
    public var bars: [SystemBar] = []
    public var events: [Int] = []
    public var right: Double = 0
}

public struct LayoutOptions: Hashable, Sendable {
    public var width: Double
    public var showStaff: Bool
    public var showTab: Bool
    public var showNames: Bool
    public var colors: Bool
    public var naming: Naming
    public init(width: Double, showStaff: Bool = true, showTab: Bool = true, showNames: Bool = false, colors: Bool = true, naming: Naming = .letters) {
        self.width = width; self.showStaff = showStaff; self.showTab = showTab; self.showNames = showNames; self.colors = colors; self.naming = naming
    }
}

public struct BeamInfo: Sendable {
    /// Groups with 2+ items (the ones that get beams).
    public var groups: [BeamGroup]
    /// Event index → index into `groups` for beamed events.
    public var byEvent: [Int: Int]
    /// Every beamable run, including single events (needed for the tuplet "3").
    public var all: [BeamGroup]
}

public struct ScoreLayout: Sendable {
    public var score: Score
    public var opts: LayoutOptions
    public var prep: [PreparedEvent]
    public var beams: BeamInfo
    public var systems: [ScoreSystem]
    public var staffTop: Double
    public var staffBottom: Double
    public var tabTop: Double
    public var tabBottom: Double
    public var namesY: Double?
    public var rhythmTop: Double?
    public var height: Double

    public func yOf(_ pos: Double) -> Double { staffTop + (8 - pos) * Notation.SP / 2 }
    public func yOf(_ pos: Int) -> Double { yOf(Double(pos)) }
}

public enum Notation {
    public static let SP: Double = 10       // staff space
    public static let HRX: Double = 6.3     // note head radii
    public static let HRY: Double = 4.6
    public static let TS: Double = 13       // tab line spacing
    public static let STEM: Double = 34

    /// Written value → glyph. `tpb` = ticks per quarter note (12 for the built-in scores, 48 for imported ones).
    public static func noteValue(_ ev: ScoreEvent, tpb: Int = Exercises.TPB) -> Glyph {
        let q = Double(ev.writtenDur) / Double(tpb)   // in quarter notes
        // (quarters, head, flags, dots) — longest first; double dots included for imported scores
        let table: [(Double, HeadKind, Int, Int)] = [
            (4, .whole, 0, 0), (3.5, .half, 0, 2), (3, .half, 0, 1), (2, .half, 0, 0),
            (1.75, .black, 0, 2), (1.5, .black, 0, 1), (1, .black, 0, 0),
            (0.875, .black, 1, 2), (0.75, .black, 1, 1), (0.5, .black, 1, 0),
            (0.4375, .black, 2, 2), (0.375, .black, 2, 1), (0.25, .black, 2, 0),
            (0.1875, .black, 3, 1), (0.125, .black, 3, 0),
            (0.09375, .black, 4, 1), (0.0625, .black, 4, 0),
        ]
        for (v, head, flags, dots) in table where abs(q - v) < 1e-6 { return Glyph(head: head, flags: flags, dots: dots) }
        // not a standard value (imported oddity): pick the nearest written value so it still draws
        var best = table[0]
        for row in table where abs(row.0 - q) < abs(best.0 - q) { best = row }
        return Glyph(head: best.1, flags: best.2, dots: best.3)
    }

    /// Works out written pitch, staff position and which accidentals must be printed (bar-by-bar).
    public static func prepare(_ score: Score) -> [PreparedEvent] {
        let ks = score.keySig
        var out: [PreparedEvent] = []
        var accState: [String: Int] = [:]
        var bar = -1
        for ev in score.events {
            if ev.measure != bar { bar = ev.measure; accState = [:] }
            let nv = noteValue(ev, tpb: score.tpb)
            let heads = ev.notes.map { n -> PreparedHead in
                let oct = Theory.octaveOf(n.midi, n.spelled) + 1 // guitar music is written an octave higher
                let pos = Theory.staffPos(n.spelled.letter, oct)
                let key = "\(n.spelled.letter):\(oct)"
                let current = accState[key] ?? ks.alters[n.spelled.letter]
                var show: Int? = nil
                if current != n.spelled.alter { show = n.spelled.alter; accState[key] = n.spelled.alter }
                return PreparedHead(pos: pos, acc: show, spelled: n.spelled, string: n.string, fret: n.fret, midi: n.midi)
            }
            out.append(PreparedEvent(ev: ev, nv: nv, heads: heads, hasAcc: heads.contains { $0.acc != nil }))
        }
        return out
    }

    public static func evWidth(_ p: PreparedEvent, tpb: Int = Exercises.TPB) -> Double {
        let w = 16 + 32 * pow(Double(p.ev.dur) / Double(tpb), 0.55)
        return w + (p.hasAcc ? 9 : 0) + (p.nv.dots > 0 ? 4 : 0)
    }

    /// Group eighths/sixteenths inside the same beat (triplets: the three of a beat).
    public static func beamGroups(_ prep: [PreparedEvent], _ score: Score) -> BeamInfo {
        var groups: [BeamGroup] = []
        var cur: BeamGroup? = nil
        for (i, p) in prep.enumerated() {
            let ev = p.ev
            let beamable = !ev.rest && p.nv.flags > 0
            let beat = ev.measure * 1000 + (ev.tick - ev.barStart) / score.tpb
            if beamable, var c = cur, c.beat == beat, c.tuplet == ev.tuplet, c.last == i - 1 {
                c.items.append(i); c.last = i
                cur = c
            } else {
                if let c = cur { groups.append(c) }
                cur = beamable ? BeamGroup(beat: beat, tuplet: ev.tuplet, items: [i], last: i) : nil
            }
        }
        if let c = cur { groups.append(c) }
        let multi = groups.filter { $0.items.count > 1 }
        var byEvent: [Int: Int] = [:]
        for (gi, g) in multi.enumerated() { for i in g.items { byEvent[i] = gi } }
        return BeamInfo(groups: multi, byEvent: byEvent, all: groups)
    }

    /// Horizontal + vertical layout, then beam geometry (`prepareBeams`). The result is ready to draw.
    public static func layout(_ score: Score, _ opts: LayoutOptions) -> ScoreLayout {
        var prep = prepare(score)
        var beams = beamGroups(prep, score)
        let ksCount = abs(score.keySig.fifths)
        let marginL = 6.0, marginR = 8.0
        let clefW = opts.showStaff ? 38.0 : 30.0
        func headerW(_ first: Bool) -> Double {
            clefW + (opts.showStaff && ksCount > 0 ? Double(ksCount) * 9.5 + 6 : 0) + (first && opts.showStaff ? 26 : 0) + 6
        }
        // a time-signature change inside the piece gets room for its digits at the start of that measure
        var tsChange: [Int: [Int]] = [:]
        var lastTS = score.time
        for m in score.measures.indices where m < score.measureTimes.count {
            if let t = score.measureTimes[m], m > 0, t != lastTS { tsChange[m] = t }
            if let t = score.measureTimes[m] { lastTS = t }
        }
        let mWidths = score.measures.indices.map { m in
            12 + (tsChange[m] != nil ? 26.0 : 0) + score.measures[m].reduce(0.0) { $0 + evWidth(prep[$1], tpb: score.tpb) } + 4
        }
        var systems: [ScoreSystem] = []
        var cur: ScoreSystem? = nil
        for m in score.measures.indices {
            let first = systems.isEmpty && cur == nil
            if cur == nil { cur = ScoreSystem(measures: [], width: 0, header: headerW(first), first: first) }
            let avail = opts.width - marginL - marginR - cur!.header
            if !cur!.measures.isEmpty && cur!.width + mWidths[m] > avail {
                systems.append(cur!)
                cur = ScoreSystem(measures: [], width: 0, header: headerW(false), first: false)
            }
            cur!.measures.append(m); cur!.width += mWidths[m]
        }
        if let c = cur { systems.append(c) }

        // vertical layout
        let staffTop = opts.showStaff ? 52.0 : 0.0
        let staffBottom = staffTop + 4 * SP
        let tabTop = opts.showStaff ? (opts.showTab ? staffBottom + 64 : 0) : 30
        let tabBottom = tabTop + 5 * TS
        var bottom = opts.showTab ? tabBottom : staffBottom + 50
        let namesY: Double? = opts.showNames ? bottom + 22 : nil
        if let n = namesY { bottom = n }
        let rhythmTop: Double? = !opts.showStaff && opts.showTab ? bottom + 8 : nil
        if let r = rhythmTop { bottom = r + 30 }
        let height = bottom + 16

        for si in systems.indices {
            let avail = opts.width - marginL - marginR - systems[si].header
            var scale = avail / systems[si].width
            if si == systems.count - 1 && systems.count > 1 { scale = min(scale, 1.35) }
            if systems.count == 1 { scale = min(scale, 1.6) }
            systems[si].scale = scale
            var x = marginL + systems[si].header
            systems[si].bars = []
            systems[si].events = []
            for m in systems[si].measures {
                let mx = x
                var ex = x + (12 + (tsChange[m] != nil ? 26.0 : 0)) * scale
                for i in score.measures[m] {
                    let w = evWidth(prep[i], tpb: score.tpb) * scale
                    prep[i].x = ex + 6 + (prep[i].hasAcc ? 9 : 0)
                    prep[i].slot0 = ex; prep[i].slot1 = ex + w
                    prep[i].system = si
                    systems[si].events.append(i)
                    ex += w
                }
                x = mx + mWidths[m] * scale
                systems[si].bars.append(SystemBar(m: m, x0: mx, x1: x, timeSig: tsChange[m]))
            }
            systems[si].right = x
        }
        var L = ScoreLayout(score: score, opts: opts, prep: prep, beams: beams, systems: systems, staffTop: staffTop, staffBottom: staffBottom,
                            tabTop: tabTop, tabBottom: tabBottom, namesY: namesY, rhythmTop: rhythmTop, height: height)
        prepareBeams(&L)
        beams = L.beams
        return L
    }

    public static func stemDir(_ heads: [PreparedHead]) -> StemDirection {
        let avg = Double(heads.reduce(0) { $0 + $1.pos }) / Double(heads.count)
        return avg >= 4 ? .down : .up
    }

    public static func stemX(_ p: PreparedEvent, _ up: Bool) -> Double { up ? p.x + HRX - 0.7 : p.x - HRX + 0.7 }

    /// Beam stems are computed before the notes are drawn.
    static func prepareBeams(_ L: inout ScoreLayout) {
        for gi in L.beams.groups.indices {
            var g = L.beams.groups[gi]
            let items = g.items.map { L.prep[$0] }
            let dir = stemDir(items.flatMap { $0.heads })
            g.dir = dir
            let up = dir == .up
            let pts: [(x: Double, tipRef: Double)] = items.map { p in
                let ps = p.heads.map { $0.pos }
                let lo = ps.min()!, hi = ps.max()!
                let x = up ? p.x + HRX - 0.7 : p.x - HRX + 0.7
                let tipRef = up ? L.yOf(hi) : L.yOf(lo)
                return (x, tipRef)
            }
            let first = pts[0], last = pts[pts.count - 1]
            let want0 = first.tipRef + (up ? -STEM : STEM), want1 = last.tipRef + (up ? -STEM : STEM)
            let dx = max(1, last.x - first.x)
            var slope = (want1 - want0) / dx
            let maxRise = 9 / dx
            slope = max(-maxRise, min(maxRise, slope))
            var base = want0
            let MIN = 27.0
            for pt in pts {
                let yb = base + slope * (pt.x - first.x)
                if up && yb > pt.tipRef - MIN { base -= yb - (pt.tipRef - MIN) }
                if !up && yb < pt.tipRef + MIN { base += (pt.tipRef + MIN) - yb }
            }
            g.hasStem = true
            g.base = base; g.slope = slope
            g.x0 = first.x; g.x1 = last.x
            L.beams.groups[gi] = g
            // mirror into `all` so the tuplet mark / golden export see the direction
            if let ai = L.beams.all.firstIndex(where: { $0.items == g.items && $0.beat == g.beat }) { L.beams.all[ai] = g }
        }
    }

    /// The beamed group that contains event `i`, if any (after layout).
    public static func group(for i: Int, in L: ScoreLayout) -> BeamGroup? {
        guard let gi = L.beams.byEvent[i] else { return nil }
        return L.beams.groups[gi]
    }
}
