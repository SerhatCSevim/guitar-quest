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
    /// Continuation of a note tied from the previous event (not plucked again; drawn with a tie).
    public var tied: Bool = false
    /// Playing-technique labels shown above the tab number (imported scores): "h", "p", "/", "b", "PM", "~" …
    public var marks: [String] = []
    public init(string: Int, fret: Int, midi: Int, spelled: SpelledNote, tied: Bool = false, marks: [String] = []) {
        self.string = string; self.fret = fret; self.midi = midi; self.spelled = spelled; self.tied = tied; self.marks = marks
    }
    public init(string: Int, fret: Int, spelled: SpelledNote) {
        self.init(string: string, fret: fret, midi: Theory.midiAt(string, fret), spelled: spelled)
    }
}

public struct ScoreEvent: Hashable, Sendable {
    public var i: Int = 0
    public var tick: Int = 0
    public var measure: Int = 0
    /// Tick where this event's measure starts (set by finalize; measures may have different lengths in imported scores).
    public var barStart: Int = 0
    public var dur: Int
    /// Tuplet "actual" count (0 = none, 3 = triplet …). `tupletNormal` is the "normal" count (3 → 2, 5/6/7 → 4, 2 → 3, 4 → 3).
    public var tuplet: Int
    public var tupletNormal: Int
    public var rest: Bool
    public var notes: [ScoreNote]
    public init(dur: Int, tuplet: Int = 0, tupletNormal: Int? = nil, rest: Bool = false, notes: [ScoreNote]) {
        self.dur = dur; self.tuplet = tuplet; self.rest = rest; self.notes = notes
        self.tupletNormal = tupletNormal ?? ScoreEvent.defaultNormal(for: tuplet)
    }
    public static func defaultNormal(for actual: Int) -> Int {
        switch actual {
        case 0, 1: return 0
        case 2, 4: return 3
        case 3: return 2
        case 5, 6, 7: return 4
        default: return 8
        }
    }
    /// Duration in ticks as it is *written* (a triplet eighth of 4 ticks is written as a 6-tick eighth).
    public var writtenDur: Int { tuplet > 1 && tupletNormal > 0 ? dur * tuplet / tupletNormal : dur }
}

/// A tempo change at a tick (quarter notes per minute).
public struct TempoMark: Hashable, Sendable {
    public var tick: Int
    public var bpm: Double
    public init(tick: Int, bpm: Double) { self.tick = tick; self.bpm = bpm }
}

public enum ScoreSource: String, Sendable { case scale, song, single, imported }

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
    /// Per-measure start tick and length (constant 48 for the built-in 4/4 scores).
    public var measureStarts: [Int] = []
    public var measureLengths: [Int] = []
    /// Time signature per measure (beats, beat type); nil entries mean "same as before".
    public var measureTimes: [[Int]?] = []
    /// Tempo changes (sorted by tick). Empty = constant `tempo`.
    public var tempoMap: [TempoMark] = []
    /// Printed bar numbers (1-based). Differs from the index when repeats were unrolled at import.
    public var measureLabels: [Int] = []
    public func measureLabel(_ m: Int) -> Int { m < measureLabels.count ? measureLabels[m] : m + 1 }

    public func measureStart(_ m: Int) -> Int { m < measureStarts.count ? measureStarts[m] : m * bar }
    public func measureLength(_ m: Int) -> Int { m < measureLengths.count ? measureLengths[m] : bar }
    /// Time signature in force at measure `m`.
    public func timeSignature(at m: Int) -> [Int] {
        var t = time
        if m < measureTimes.count { for k in 0...m { if let ts = measureTimes[k] { t = ts } } }
        return t
    }
    /// Measure index containing `tick` (binary search over measureStarts).
    public func measureIndex(atTick tick: Int) -> Int {
        guard !measureStarts.isEmpty else { return max(0, min(measures.count - 1, tick / bar)) }
        var lo = 0, hi = measureStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if measureStarts[mid] <= tick { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
    /// Index of the event sounding at `tick` (or the next one), nil past the end.
    public func eventIndex(atTick tick: Int) -> Int? {
        guard !events.isEmpty, tick < totalTicks else { return nil }
        var lo = 0, hi = events.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if events[mid].tick <= tick { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
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
            events[i].barStart = m * BAR
            if (tick + events[i].dur - 1) / BAR != m { throw ScoreError.crossesBar(i) }
            while measures.count <= m { measures.append([]) }
            measures[m].append(i)
            tick += events[i].dur
        }
        if tick % BAR != 0 { throw ScoreError.notOnBarLine(tick) }
        var sc = Score(title: meta.title, subtitle: meta.subtitle, keySig: meta.keySig, tempo: meta.tempo, source: meta.source,
                       events: events, measures: measures, totalTicks: tick)
        sc.measureStarts = measures.indices.map { $0 * BAR }
        sc.measureLengths = measures.map { _ in BAR }
        sc.measureTimes = measures.indices.map { $0 == 0 ? [4, 4] : nil }
        return sc
    }

    /// General form for imported scores: explicit measures with their own lengths (ticks) and time signatures, any `tpb`.
    /// Events that overrun their measure are clipped; short measures are padded with a rest so playback stays in time.
    public static func finalizeMeasures(_ input: [[ScoreEvent]], lengths: [Int], times: [[Int]?], tpb: Int, meta: ScoreMeta, tempoMap: [TempoMark]) -> Score {
        var events: [ScoreEvent] = []
        var measures: [[Int]] = []
        var starts: [Int] = []
        var tick = 0
        var realLengths: [Int] = []
        for (m, list) in input.enumerated() {
            // Guitar Pro allows over-full bars: stretch the bar rather than lose notes
            let nominal = m < lengths.count ? lengths[m] : lengths.last ?? 4 * tpb
            let len = max(nominal, list.reduce(0) { $0 + max(0, $1.dur) })
            realLengths.append(len)
            let start = tick
            starts.append(start)
            var ids: [Int] = []
            var used = 0
            for var ev in list {
                if used >= len { break }
                if ev.notes.count > 1 { ev.notes.sort { $0.string > $1.string } }   // low string first, like voicings
                if used + ev.dur > len { ev.dur = len - used; ev.tuplet = 0; ev.tupletNormal = 0 }
                ev.i = events.count; ev.tick = start + used; ev.measure = m; ev.barStart = start
                ids.append(ev.i)
                events.append(ev)
                used += ev.dur
            }
            if used < len {
                var rest = ScoreEvent(dur: len - used, rest: true, notes: [])
                rest.i = events.count; rest.tick = start + used; rest.measure = m; rest.barStart = start
                ids.append(rest.i)
                events.append(rest)
            }
            measures.append(ids)
            tick = start + len
        }
        var sc = Score(title: meta.title, subtitle: meta.subtitle, keySig: meta.keySig, tempo: meta.tempo, source: meta.source,
                       time: times.first.flatMap { $0 } ?? [4, 4], tpb: tpb, bar: 4 * tpb, events: events, measures: measures, totalTicks: tick)
        sc.measureStarts = starts
        sc.measureLengths = realLengths
        sc.measureTimes = measures.indices.map { $0 < times.count ? times[$0] : nil }
        sc.tempoMap = tempoMap.sorted { $0.tick < $1.tick }
        return sc
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
            TimelineItem(i: ev.i, beat: Double(ev.tick) / Double(score.tpb), beats: Double(ev.dur) / Double(score.tpb), rest: ev.rest,
                         midis: ev.notes.filter { !$0.tied }.map { $0.midi })
        }
    }

    /// Timeline whose beats are stretched by the score's tempo map, so a transport running at `baseTempo` BPM
    /// reproduces every tempo change (a passage at half tempo takes twice as many "beats").
    public static func timeline(_ score: Score, baseTempo: Double) -> [TimelineItem] {
        let tm = TempoTimeline(score: score)
        return score.events.map { ev in
            let b0 = tm.seconds(atTick: ev.tick) * baseTempo / 60
            let b1 = tm.seconds(atTick: ev.tick + ev.dur) * baseTempo / 60
            return TimelineItem(i: ev.i, beat: b0, beats: b1 - b0, rest: ev.rest, midis: ev.notes.filter { !$0.tied }.map { $0.midi })
        }
    }

    /// Convenience: a one-bar, whole-note score (used by Explorer, Note Quest and chord detail).
    public static func singleEvent(notes: [ScoreNote], keySig: KeySignature = Theory.keySignature(SpelledNote(0, 0), .major)) -> Score {
        // A single 48-tick event always finalizes.
        return try! finalize([ScoreEvent(dur: 48, tuplet: 0, notes: notes)], ScoreMeta(keySig: keySig, tempo: 60))
    }
}
