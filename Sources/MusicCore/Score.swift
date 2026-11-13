// Guitar Quest - builds playable scores (scale exercises, songs). Port of web/js/exercises.js.
// Time is counted in ticks: 12 ticks = 1 quarter-note beat, 48 ticks = one 4/4 bar.
import Foundation

public enum Rhythm: String, Codable, Sendable, CaseIterable {
    case q, e, t, s
    public var name: String {
        switch self {
        case .q: return "Quarter notes"
        case .e: return "Eighth notes"
        case .t: return "Triplets"
        case .s: return "Sixteenth notes"
        }
    }
    public var unit: Int { switch self { case .q: return 12; case .e: return 6; case .t: return 4; case .s: return 3 } }
    public var tuplet: Int { self == .t ? 3 : 0 }
}

public enum ExerciseRange: String, Codable, Sendable, CaseIterable { case root, full }

public struct ScoreNote: Hashable, Sendable {
    public var string: Int
    public var fret: Int
    public var midi: Int
    public var spelled: SpelledNote
    public init(string: Int, fret: Int, midi: Int, spelled: SpelledNote) {
        self.string = string; self.fret = fret; self.midi = midi; self.spelled = spelled
    }
    public init(string: Int, fret: Int, spelled: SpelledNote) {
        self.init(string: string, fret: fret, midi: Theory.midiAt(string, fret), spelled: spelled)
    }
}

public struct ScoreEvent: Hashable, Sendable {
    public var i: Int = 0
    public var tick: Int = 0
    public var measure: Int = 0
    public var dur: Int
    public var tuplet: Int
    public var rest: Bool
    public var notes: [ScoreNote]
    public init(dur: Int, tuplet: Int = 0, rest: Bool = false, notes: [ScoreNote]) {
        self.dur = dur; self.tuplet = tuplet; self.rest = rest; self.notes = notes
    }
}

public enum ScoreSource: String, Sendable { case scale, song, single }

public struct Score: Hashable, Sendable {
    public var title: String
    public var subtitle: String
    public var keySig: KeySignature
    public var tempo: Int
    public var source: ScoreSource
    public var time: [Int] = [4, 4]
    public var tpb: Int = Exercises.TPB
    public var bar: Int = Exercises.BAR
    public var events: [ScoreEvent]
    public var measures: [[Int]]
    public var totalTicks: Int
}

public struct ScoreMeta: Sendable {
    public var title: String
    public var subtitle: String
    public var keySig: KeySignature
    public var tempo: Int
    public var source: ScoreSource
    public init(title: String = "", subtitle: String = "", keySig: KeySignature, tempo: Int = 60, source: ScoreSource = .single) {
        self.title = title; self.subtitle = subtitle; self.keySig = keySig; self.tempo = tempo; self.source = source
    }
}

public struct TimelineItem: Hashable, Sendable {
    public var i: Int
    public var beat: Double
    public var beats: Double
    public var rest: Bool
    public var midis: [Int]
}

public enum ScoreError: Error, CustomStringConvertible, Equatable {
    case crossesBar(Int)
    case notOnBarLine(Int)
    case cannotFill(Int)
    case pickAShape
    case badToken(String)
    case unplayable(String)
    case barLength(song: String, bar: Int, ticks: Int)

    public var description: String {
        switch self {
        case .crossesBar(let i): return "Event \(i) crosses a bar line"
        case .notOnBarLine(let t): return "Score does not end on a bar line (\(t) ticks)"
        case .cannotFill(let r): return "Cannot fill \(r)"
        case .pickAShape: return "Pick a shape to practise"
        case .badToken(let t): return "Bad token \(t)"
        case .unplayable(let t): return "Unplayable note \(t)"
        case .barLength(let s, let b, let t): return "\(s): bar \(b) has \(t) ticks"
        }
    }
}

public struct ScaleScoreOptions: Sendable {
    public var tonic: String
    public var scaleId: ScaleID
    public var shapeId: String
    public var pattern: Pattern
    public var rhythm: Rhythm
    public var range: ExerciseRange
    public var tempo: Int
    public init(tonic: String, scaleId: ScaleID, shapeId: String, pattern: Pattern, rhythm: Rhythm, range: ExerciseRange, tempo: Int = 80) {
        self.tonic = tonic; self.scaleId = scaleId; self.shapeId = shapeId; self.pattern = pattern
        self.rhythm = rhythm; self.range = range; self.tempo = tempo
    }
}

public enum Exercises {
    public static let TPB = 12
    public static let BAR = 48
    public static let DUR: [String: Int] = ["w": 48, "h.": 36, "h": 24, "q.": 18, "q": 12, "8.": 9, "8": 6, "16": 3]

    /// Assign ticks and split events into bars. Every bar must add up to exactly one 4/4 bar.
    public static func finalize(_ input: [ScoreEvent], _ meta: ScoreMeta) throws -> Score {
        var events = input
        var tick = 0
        var measures: [[Int]] = []
        for i in events.indices {
            events[i].i = i
            events[i].tick = tick
            let m = tick / BAR
            events[i].measure = m
            if (tick + events[i].dur - 1) / BAR != m { throw ScoreError.crossesBar(i) }
            while measures.count <= m { measures.append([]) }
            measures[m].append(i)
            tick += events[i].dur
        }
        if tick % BAR != 0 { throw ScoreError.notOnBarLine(tick) }
        return Score(title: meta.title, subtitle: meta.subtitle, keySig: meta.keySig, tempo: meta.tempo, source: meta.source,
                     events: events, measures: measures, totalTicks: tick)
    }

    static func longNote(_ remaining: Int) throws -> Int {
        // duration that fills the rest of a bar starting on a beat
        if ![48, 36, 24, 12].contains(remaining) { throw ScoreError.cannotFill(remaining) }
        return remaining
    }

    public static func buildScaleScore(_ opts: ScaleScoreOptions) throws -> Score {
        let tonic = Theory.parseNote(opts.tonic)
        let sc = Theory.scale(opts.scaleId)
        if opts.shapeId == "neck" { throw ScoreError.pickAShape }
        let shape = Theory.buildShape(tonic, opts.scaleId, opts.shapeId, 24)
        var notes = shape.notes
        if opts.range == .root { notes = Theory.rootToRoot(notes) }
        let idx = Theory.patternIndices(notes.count, opts.pattern)
        let r = opts.rhythm
        var events: [ScoreEvent] = []
        let body = idx.dropLast()
        let last = idx[idx.count - 1]
        for k in body {
            let n = notes[k]
            events.append(ScoreEvent(dur: r.unit, tuplet: r.tuplet, notes: [ScoreNote(string: n.string, fret: n.fret, spelled: n.spelled)]))
        }
        var tick = body.count * r.unit
        while tick % TPB != 0 {
            events.append(ScoreEvent(dur: r.unit, tuplet: r.tuplet, rest: true, notes: []))
            tick += r.unit
        }
        let n = notes[last]
        events.append(ScoreEvent(dur: try longNote(BAR - (tick % BAR)), tuplet: 0, notes: [ScoreNote(string: n.string, fret: n.fret, spelled: n.spelled)]))
        let shapeName = Theory.shapeOptions(opts.scaleId).first { $0.id == opts.shapeId }?.name ?? ""
        return try finalize(events, ScoreMeta(
            title: Theory.noteLabel(tonic) + " " + sc.name.lowercased(),
            subtitle: shapeName + " - " + opts.pattern.name + " - " + r.name.lowercased(),
            keySig: Theory.keySignature(tonic, sc.family),
            tempo: opts.tempo,
            source: .scale))
    }

    /// Parses `Note+octave[:duration][@string/fret]` or `r[:duration]`.
    public static func parseToken(_ tok: String) throws -> ScoreEvent {
        // ^(r|[A-G](?:#|b)?)(\d)?(?::(w|h\.|h|q\.|q|8\.|8|16))?(?:@(\d)\/(\d+))?$
        var s = Substring(tok)
        guard let first = s.first else { throw ScoreError.badToken(tok) }
        var name = ""
        if first == "r" {
            name = "r"; s = s.dropFirst()
        } else if ("A"..."G").contains(String(first)) {
            name = String(first); s = s.dropFirst()
            if let acc = s.first, acc == "#" || acc == "b" { name.append(acc); s = s.dropFirst() }
        } else { throw ScoreError.badToken(tok) }
        var octave: Int? = nil
        if let d = s.first, d.isNumber, let v = d.wholeNumberValue { octave = v; s = s.dropFirst() }
        var durKey = "q"
        if s.first == ":" {
            s = s.dropFirst()
            let candidates = ["h.", "q.", "8.", "16", "w", "h", "q", "8"]
            guard let c = candidates.first(where: { s.hasPrefix($0) }) else { throw ScoreError.badToken(tok) }
            durKey = c; s = s.dropFirst(c.count)
        }
        var pos: Position? = nil
        if s.first == "@" {
            s = s.dropFirst()
            guard let sd = s.first, let sv = sd.wholeNumberValue else { throw ScoreError.badToken(tok) }
            s = s.dropFirst()
            guard s.first == "/" else { throw ScoreError.badToken(tok) }
            s = s.dropFirst()
            let digits = s.prefix { $0.isNumber }
            guard !digits.isEmpty, let fv = Int(digits) else { throw ScoreError.badToken(tok) }
            s = s.dropFirst(digits.count)
            pos = Position(string: sv, fret: fv)
        }
        guard s.isEmpty else { throw ScoreError.badToken(tok) }
        let dur = DUR[durKey]!
        if name == "r" { return ScoreEvent(dur: dur, tuplet: 0, rest: true, notes: []) }
        let spelled = Theory.parseNote(name)
        let oct = octave ?? 0 // JS: Number(undefined) = NaN → unplayable; octave is always given in the songs
        let midi = (oct + 1) * 12 + Theory.LETTER_PC[spelled.letter] + spelled.alter
        let p = pos ?? Theory.lowestPosition(midi)
        guard octave != nil, let p, Theory.midiAt(p.string, p.fret) == midi else { throw ScoreError.unplayable(tok) }
        return ScoreEvent(dur: dur, tuplet: 0, notes: [ScoreNote(string: p.string, fret: p.fret, midi: midi, spelled: spelled)])
    }

    public static func buildSongScore(_ song: Song) throws -> Score {
        var events: [ScoreEvent] = []
        for (bi, bar) in song.notes.split(separator: "|", omittingEmptySubsequences: false).enumerated() {
            let toks = bar.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
            var sum = 0
            for t in toks {
                var ev = try parseToken(t)
                ev.tuplet = 0
                sum += ev.dur
                events.append(ev)
            }
            if sum != BAR { throw ScoreError.barLength(song: song.id, bar: bi + 1, ticks: sum) }
        }
        let tonic = Theory.parseNote(song.key)
        return try finalize(events, ScoreMeta(title: song.title, subtitle: song.origin + " - " + song.strings,
                                              keySig: Theory.keySignature(tonic, song.family), tempo: song.tempo, source: .song))
    }

    /// Seconds-free timeline for the player: start/duration in beats.
    public static func timeline(_ score: Score) -> [TimelineItem] {
        score.events.map { ev in
            TimelineItem(i: ev.i, beat: Double(ev.tick) / Double(TPB), beats: Double(ev.dur) / Double(TPB), rest: ev.rest,
                         midis: ev.notes.map { $0.midi })
        }
    }

    /// Convenience: a one-bar, whole-note score (used by Explorer, Note Quest and chord detail).
    public static func singleEvent(notes: [ScoreNote], keySig: KeySignature = Theory.keySignature(SpelledNote(0, 0), .major)) -> Score {
        // A single 48-tick event always finalizes.
        return try! finalize([ScoreEvent(dur: 48, tuplet: 0, notes: notes)], ScoreMeta(keySig: keySig, tempo: 60))
    }
}
