// Guitar Quest - music theory core. Port of web/js/theory.js (pure functions, no UI).
import Foundation

/// A spelled note: letter index 0..6 (C D E F G A B) and alteration -2..+2 (bb, b, natural, #, ##).
public struct SpelledNote: Hashable, Codable, Sendable {
    public var letter: Int
    public var alter: Int
    public init(_ letter: Int, _ alter: Int) { self.letter = letter; self.alter = alter }
    public init(letter: Int, alter: Int) { self.letter = letter; self.alter = alter }
}

public enum Family: String, Codable, Sendable, CaseIterable { case major, minor }
public enum Naming: String, Codable, Sendable, CaseIterable { case letters, solfege, both }
public enum AccidentalPref: String, Codable, Sendable, CaseIterable { case sharp, flat, both }

public struct Position: Hashable, Codable, Sendable {
    public var string: Int
    public var fret: Int
    public init(string: Int, fret: Int) { self.string = string; self.fret = fret }
}

public struct ScaleStep: Hashable, Sendable {
    public let degree: Int
    public let semis: Int
}

public enum ScaleID: String, Codable, Sendable, CaseIterable {
    case major, minor, majorPent, minorPent, blues
}

public struct ScaleDef: Sendable {
    public let id: ScaleID
    public let name: String
    public let family: Family
    public let pent: Bool
    public let blues: Bool
    public let steps: [ScaleStep]
}

/// A note of a scale or chord: spelling + degree information.
public struct ScaleNote: Hashable, Sendable {
    public var letter: Int
    public var alter: Int
    public var degree: Int
    public var semis: Int
    public var label: String
    public var pc: Int
    public var spelled: SpelledNote { SpelledNote(letter, alter) }
}

public struct KeySignature: Hashable, Sendable {
    public var fifths: Int
    public var alters: [Int]          // per letter 0..6
    public var list: [SpelledNote]    // ordered sharps or flats
    public var majorTonic: SpelledNote
}

public enum ChordType: String, Codable, Sendable, CaseIterable {
    case maj, min, dim, aug, sus2, sus4, power, dom7, maj7, min7, m7b5, dim7
}

public struct ChordTypeDef: Sendable {
    public let id: ChordType
    public let name: String
    public let sym: String
    public let tones: [ScaleStep]
}

public struct HarmonizedChord: Hashable, Sendable {
    public var degree: Int
    public var root: SpelledNote
    public var type: ChordType
    public var roman: String
}

public struct ShapeOption: Hashable, Sendable {
    public let id: String
    public let name: String
}

public struct ShapeNote: Hashable, Sendable {
    public var string: Int
    public var fret: Int
    public var midi: Int
    public var pc: Int
    public var spelled: SpelledNote
    public var degree: Int
    public var label: String
    public var isRoot: Bool
}

public struct Shape: Hashable, Sendable {
    public var notes: [ShapeNote]
    public var minFret: Int
    public var maxFret: Int
}

public enum Pattern: String, Codable, Sendable, CaseIterable {
    case updown, up, down, groups3, groups4, thirds
    public var name: String {
        switch self {
        case .updown: return "Up and down"
        case .up: return "Up only"
        case .down: return "Down only"
        case .groups3: return "Groups of 3"
        case .groups4: return "Groups of 4"
        case .thirds: return "Thirds (skip a note)"
        }
    }
}

/// JavaScript `Math.round`: halves round towards +infinity.
@inlinable public func jsRound(_ x: Double) -> Int { Int(floor(x + 0.5)) }

public enum Theory {
    public static let LETTERS = ["C", "D", "E", "F", "G", "A", "B"]
    public static let LETTER_PC = [0, 2, 4, 5, 7, 9, 11]
    public static let SOLFEGE = ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si"]
    public static let MAJOR_SEMIS = [0, 2, 4, 5, 7, 9, 11]

    /// Standard tuning. Index = string number: 1 = high e (thinnest) ... 6 = low E. Index 0 unused.
    public static let TUNING = [0, 64, 59, 55, 50, 45, 40]
    public static let OPEN_NAMES = ["", "e", "B", "G", "D", "A", "E"]

    /// Always non-negative remainder (Swift `%` keeps the sign of the dividend).
    @inlinable public static func mod(_ n: Int, _ m: Int) -> Int { ((n % m) + m) % m }

    public static func midiAt(_ string: Int, _ fret: Int) -> Int { TUNING[string] + fret }
    public static func freqOf(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
    public static func freqOf(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    // MARK: spelled notes

    static let ACC_PARSE: [String: Int] = ["": 0, "#": 1, "♯": 1, "##": 2, "x": 2, "𝄪": 2, "b": -1, "♭": -1, "bb": -2, "𝄫": -2]
    static let ACC_UNI: [Int: String] = [-2: "𝄫", -1: "♭", 0: "", 1: "♯", 2: "𝄪"]
    static let ACC_ASCII: [Int: String] = [-2: "bb", -1: "b", 0: "", 1: "#", 2: "##"]

    /// Accepts `C`, `C#`, `Db`, `C##`/`Cx`, `Dbb` and the Unicode signs. Returns nil for anything else.
    public static func parseNoteOrNil(_ name: String) -> SpelledNote? {
        let s = name.trimmingCharacters(in: .whitespaces)
        guard let first = s.first else { return nil }
        let up = String(first).uppercased()
        guard let l = LETTERS.firstIndex(of: up) else { return nil }
        let rest = String(s.dropFirst())
        guard let a = ACC_PARSE[rest] else { return nil }
        return SpelledNote(l, a)
    }

    /// Same as `parseNoteOrNil` but traps on a bad name (the JS version throws).
    public static func parseNote(_ name: String) -> SpelledNote {
        guard let n = parseNoteOrNil(name) else { preconditionFailure("Bad note name: \(name)") }
        return n
    }

    public static func notePc(_ n: SpelledNote) -> Int { mod(LETTER_PC[n.letter] + n.alter, 12) }
    public static func accText(_ a: Int, ascii: Bool = false) -> String { (ascii ? ACC_ASCII : ACC_UNI)[a] ?? "" }
    public static func sameNote(_ x: SpelledNote, _ y: SpelledNote) -> Bool { x.letter == y.letter && x.alter == y.alter }

    public static func noteLabel(_ n: SpelledNote, _ naming: Naming = .letters) -> String {
        let acc = accText(n.alter)
        switch naming {
        case .solfege: return SOLFEGE[n.letter] + acc
        case .both: return LETTERS[n.letter] + acc + " (" + SOLFEGE[n.letter] + acc + ")"
        case .letters: return LETTERS[n.letter] + acc
        }
    }
    public static func noteAscii(_ n: SpelledNote) -> String { LETTERS[n.letter] + accText(n.alter, ascii: true) }

    static let SHARP_SPELL: [(Int, Int)] = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)]
    static let FLAT_SPELL: [(Int, Int)] = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)]

    /// Natural spelling if possible, otherwise sharp or flat according to `pref` (`.both` behaves like sharp).
    public static func spellPc(_ pc: Int, _ pref: AccidentalPref = .sharp) -> SpelledNote {
        let t = (pref == .flat ? FLAT_SPELL : SHARP_SPELL)[mod(pc, 12)]
        return SpelledNote(t.0, t.1)
    }
    public static func isNaturalPc(_ pc: Int) -> Bool { SHARP_SPELL[mod(pc, 12)].1 == 0 }

    /// Label for an unspelled pitch class. `pref == .both` → `C♯/D♭` for black-key notes.
    public static func pcLabel(_ pc: Int, _ naming: Naming, _ pref: AccidentalPref) -> String {
        if isNaturalPc(pc) { return noteLabel(spellPc(pc), naming) }
        if pref == .both { return noteLabel(spellPc(pc, .sharp), naming) + "/" + noteLabel(spellPc(pc, .flat), naming) }
        return noteLabel(spellPc(pc, pref), naming)
    }

    /// The note `semis` semitones above `tonic`, written on scale degree `degree` (1-based).
    public static func degreeNote(_ tonic: SpelledNote, _ degree: Int, _ semis: Int) -> SpelledNote {
        let l = mod(tonic.letter + degree - 1, 7)
        let target = mod(notePc(tonic) + semis, 12)
        let a = mod(target - LETTER_PC[l] + 6, 12) - 6
        return SpelledNote(l, a)
    }

    /// Written octave of a spelled note that sounds at `midi` (scientific pitch, C4 = 60).
    public static func octaveOf(_ midi: Int, _ n: SpelledNote) -> Int {
        let natural = midi - n.alter - LETTER_PC[n.letter]
        return jsRound(Double(natural) / 12) - 1
    }

    /// Diatonic staff position; 0 = E4 (bottom line of the treble staff), 8 = F5 (top line).
    public static func staffPos(_ l: Int, _ octave: Int) -> Int { octave * 7 + l - (4 * 7 + 2) }

    public static func degreeLabel(_ degree: Int, _ semis: Int) -> String {
        let d = semis - MAJOR_SEMIS[(degree - 1) % 7] - 12 * Int(floor(Double(degree - 1) / 7))
        let acc = d < 0 ? String(repeating: "♭", count: -d) : String(repeating: "♯", count: d)
        return acc + String(degree)
    }

    // MARK: scales

    public static let SCALES: [ScaleID: ScaleDef] = [
        .major: ScaleDef(id: .major, name: "Major", family: .major, pent: false, blues: false,
                         steps: [(1, 0), (2, 2), (3, 4), (4, 5), (5, 7), (6, 9), (7, 11)].map { ScaleStep(degree: $0.0, semis: $0.1) }),
        .minor: ScaleDef(id: .minor, name: "Natural minor", family: .minor, pent: false, blues: false,
                         steps: [(1, 0), (2, 2), (3, 3), (4, 5), (5, 7), (6, 8), (7, 10)].map { ScaleStep(degree: $0.0, semis: $0.1) }),
        .majorPent: ScaleDef(id: .majorPent, name: "Major pentatonic", family: .major, pent: true, blues: false,
                             steps: [(1, 0), (2, 2), (3, 4), (5, 7), (6, 9)].map { ScaleStep(degree: $0.0, semis: $0.1) }),
        .minorPent: ScaleDef(id: .minorPent, name: "Minor pentatonic", family: .minor, pent: true, blues: false,
                             steps: [(1, 0), (3, 3), (4, 5), (5, 7), (7, 10)].map { ScaleStep(degree: $0.0, semis: $0.1) }),
        .blues: ScaleDef(id: .blues, name: "Blues", family: .minor, pent: true, blues: true,
                         steps: [(1, 0), (3, 3), (4, 5), (5, 6), (5, 7), (7, 10)].map { ScaleStep(degree: $0.0, semis: $0.1) }),
    ]
    public static func scale(_ id: ScaleID) -> ScaleDef { SCALES[id]! }

    public static func scaleNotes(_ tonic: SpelledNote, _ scaleId: ScaleID) -> [ScaleNote] {
        scale(scaleId).steps.map { st in
            let n = degreeNote(tonic, st.degree, st.semis)
            return ScaleNote(letter: n.letter, alter: n.alter, degree: st.degree, semis: st.semis,
                             label: degreeLabel(st.degree, st.semis), pc: notePc(n))
        }
    }

    /// Step sizes between neighbouring scale notes, including the step back to the octave.
    public static func stepPattern(_ scaleId: ScaleID) -> [String] {
        let s = scale(scaleId).steps.map { $0.semis } + [12]
        let names = [1: "H", 2: "W", 3: "W+H"]
        var out: [String] = []
        for i in 1..<s.count { out.append(names[s[i] - s[i - 1]] ?? String(s[i] - s[i - 1])) }
        return out
    }

    // MARK: keys

    public static let MAJOR_KEYS = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    public static let MINOR_KEYS = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
    public static func keyNames(_ family: Family) -> [String] { family == .minor ? MINOR_KEYS : MAJOR_KEYS }

    public static func relativeMinorOf(_ majorTonic: SpelledNote) -> SpelledNote { degreeNote(majorTonic, 6, 9) }
    public static func relativeMajorOf(_ minorTonic: SpelledNote) -> SpelledNote { degreeNote(minorTonic, 3, 3) }

    public static let SHARP_ORDER = [3, 0, 4, 1, 5, 2, 6] // F C G D A E B
    public static let FLAT_ORDER = [6, 2, 5, 1, 4, 0, 3]  // B E A D G C F

    public static func keySignature(_ tonic: SpelledNote, _ family: Family) -> KeySignature {
        let majorTonic = family == .minor ? relativeMajorOf(tonic) : tonic
        let sc = scaleNotes(majorTonic, .major)
        var alters = [0, 0, 0, 0, 0, 0, 0]
        for n in sc { alters[n.letter] = n.alter }
        let sharps = SHARP_ORDER.filter { alters[$0] > 0 }
        let flats = FLAT_ORDER.filter { alters[$0] < 0 }
        precondition(sharps.isEmpty || flats.isEmpty, "Mixed key signature")
        let list = !sharps.isEmpty ? sharps.map { SpelledNote($0, alters[$0]) } : flats.map { SpelledNote($0, alters[$0]) }
        return KeySignature(fifths: !sharps.isEmpty ? sharps.count : -flats.count, alters: alters, list: list, majorTonic: majorTonic)
    }

    // MARK: chords

    public static let CHORD_TYPES: [ChordType: ChordTypeDef] = {
        func def(_ id: ChordType, _ name: String, _ sym: String, _ tones: [(Int, Int)]) -> ChordTypeDef {
            ChordTypeDef(id: id, name: name, sym: sym, tones: tones.map { ScaleStep(degree: $0.0, semis: $0.1) })
        }
        return [
            .maj: def(.maj, "Major", "", [(1, 0), (3, 4), (5, 7)]),
            .min: def(.min, "Minor", "m", [(1, 0), (3, 3), (5, 7)]),
            .dim: def(.dim, "Diminished", "dim", [(1, 0), (3, 3), (5, 6)]),
            .aug: def(.aug, "Augmented", "aug", [(1, 0), (3, 4), (5, 8)]),
            .sus2: def(.sus2, "Suspended 2nd", "sus2", [(1, 0), (2, 2), (5, 7)]),
            .sus4: def(.sus4, "Suspended 4th", "sus4", [(1, 0), (4, 5), (5, 7)]),
            .power: def(.power, "Power chord", "5", [(1, 0), (5, 7)]),
            .dom7: def(.dom7, "Dominant 7th", "7", [(1, 0), (3, 4), (5, 7), (7, 10)]),
            .maj7: def(.maj7, "Major 7th", "maj7", [(1, 0), (3, 4), (5, 7), (7, 11)]),
            .min7: def(.min7, "Minor 7th", "m7", [(1, 0), (3, 3), (5, 7), (7, 10)]),
            .m7b5: def(.m7b5, "Half-diminished 7th", "m7♭5", [(1, 0), (3, 3), (5, 6), (7, 10)]),
            .dim7: def(.dim7, "Diminished 7th", "dim7", [(1, 0), (3, 3), (5, 6), (7, 9)]),
        ]
    }()
    public static func chordType(_ t: ChordType) -> ChordTypeDef { CHORD_TYPES[t]! }

    public static func chordTones(_ root: SpelledNote, _ type: ChordType) -> [ScaleNote] {
        chordType(type).tones.map { st in
            let n = degreeNote(root, st.degree, st.semis)
            return ScaleNote(letter: n.letter, alter: n.alter, degree: st.degree, semis: st.semis,
                             label: degreeLabel(st.degree, st.semis), pc: notePc(n))
        }
    }
    public static func chordSymbol(_ root: SpelledNote, _ type: ChordType, _ naming: Naming = .letters) -> String {
        noteLabel(root, naming) + chordType(type).sym
    }
    public static func chordFormula(_ type: ChordType) -> [String] { chordType(type).tones.map { degreeLabel($0.degree, $0.semis) } }

    public static func typeFromIntervals(_ semis: [Int]) -> ChordType? {
        let key = semis.map(String.init).joined(separator: ",")
        let table: [String: ChordType] = [
            "4,7": .maj, "3,7": .min, "3,6": .dim, "4,8": .aug,
            "4,7,11": .maj7, "3,7,10": .min7, "4,7,10": .dom7, "3,6,10": .m7b5, "3,6,9": .dim7,
        ]
        return table[key]
    }

    static let ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII"]
    public static func romanFor(_ degreeIndex: Int, _ type: ChordType?) -> String {
        var r = ROMAN[degreeIndex]
        guard let type else { return r }
        let lower = type == .min || type == .dim || type == .min7 || type == .m7b5 || type == .dim7
        if lower { r = r.lowercased() }
        switch type {
        case .dim: r += "°"
        case .aug: r += "+"
        case .maj7: r += "maj7"
        case .dom7, .min7: r += "7"
        case .m7b5: r += "ø7"
        case .dim7: r += "°7"
        default: break
        }
        return r
    }

    /// Chords built on every step of the major or natural-minor scale.
    public static func harmonize(_ tonic: SpelledNote, _ family: Family, _ sevenths: Bool) -> [HarmonizedChord] {
        let sc = scaleNotes(tonic, family == .minor ? .minor : .major)
        return sc.enumerated().map { i, root in
            let offsets = sevenths ? [2, 4, 6] : [2, 4]
            let stack = offsets.map { sc[(i + $0) % 7] }
            let semis = stack.map { mod($0.pc - root.pc, 12) }
            let type = typeFromIntervals(semis)
            // Every diatonic stack of thirds is one of the known types; `!` mirrors the JS (where a null type would break later).
            return HarmonizedChord(degree: i + 1, root: SpelledNote(root.letter, root.alter), type: type!, roman: romanFor(i, type))
        }
    }

    // MARK: fretboard

    public static func positionsOfMidi(_ midi: Int, _ maxFret: Int) -> [Position] {
        var out: [Position] = []
        for s in 1...6 {
            let f = midi - TUNING[s]
            if f >= 0 && f <= maxFret { out.append(Position(string: s, fret: f)) }
        }
        return out
    }
    public static func positionsOfPc(_ pc: Int, _ maxFret: Int) -> [Position] {
        var out: [Position] = []
        for s in 1...6 {
            for f in 0...maxFret where mod(TUNING[s] + f, 12) == pc { out.append(Position(string: s, fret: f)) }
        }
        return out
    }
    /// First-position style choice: the lowest fret that can play the pitch.
    public static func lowestPosition(_ midi: Int) -> Position? {
        let all = positionsOfMidi(midi, 24)
        guard var best = all.first else { return nil }
        for p in all where p.fret < best.fret { best = p }
        return best
    }

    // MARK: scale shapes

    public static func shapeOptions(_ scaleId: ScaleID) -> [ShapeOption] {
        let sc = scale(scaleId)
        var opts = [ShapeOption(id: "neck", name: "Whole neck")]
        if sc.pent {
            for k in 1...5 { opts.append(ShapeOption(id: "box\(k)", name: "Shape \(k)")) }
        } else {
            opts.append(ShapeOption(id: "open", name: "Open position"))
            opts.append(ShapeOption(id: "r6", name: "Root on 6th string"))
            opts.append(ShapeOption(id: "r5", name: "Root on 5th string"))
            for k in 1...7 { opts.append(ShapeOption(id: "3nps\(k)", name: "3 notes per string - form \(k)")) }
        }
        return opts
    }

    static func decorate(_ list: [Position], _ notesByPc: [Int: ScaleNote], _ tonicPc: Int) -> [ShapeNote] {
        list.map { p in
            let midi = midiAt(p.string, p.fret)
            let n = notesByPc[mod(midi, 12)]!
            return ShapeNote(string: p.string, fret: p.fret, midi: midi, pc: n.pc, spelled: SpelledNote(n.letter, n.alter),
                             degree: n.degree, label: n.label, isRoot: n.pc == tonicPc)
        }
    }

    /// Walk upward from (low E, startFret) collecting scale tones, `perString` on each string.
    static func sequentialShape(_ pcSet: Set<Int>, _ startFret: Int, _ perString: Int) -> [Position] {
        var seq: [Int] = []
        var m = TUNING[6] + startFret
        while seq.count < perString * 6 {
            if pcSet.contains(mod(m, 12)) { seq.append(m) }
            m += 1
        }
        return seq.enumerated().map { i, midi in
            let s = 6 - i / perString
            return Position(string: s, fret: midi - TUNING[s])
        }
    }

    static func windowShape(_ pcSet: Set<Int>, _ lo: Int, _ hi: Int) -> [Position] {
        // Insertion-ordered map (JS Map semantics): the same pitch can appear on G (top of window) and B (bottom of window);
        // keep the one on the higher string (smaller number).
        var order: [Int] = []
        var best: [Int: Position] = [:]
        for s in stride(from: 6, through: 1, by: -1) {
            if max(0, lo) > hi { continue }
            for f in max(0, lo)...hi {
                let midi = midiAt(s, f)
                if !pcSet.contains(mod(midi, 12)) { continue }
                if let cur = best[midi] {
                    if s < cur.string { best[midi] = Position(string: s, fret: f) }
                } else {
                    order.append(midi)
                    best[midi] = Position(string: s, fret: f)
                }
            }
        }
        return order.map { best[$0]! }
    }

    public static func buildShape(_ tonic: SpelledNote, _ scaleId: ScaleID, _ shapeId: String, _ maxFret: Int = 15) -> Shape {
        let sc = scale(scaleId)
        let notes = scaleNotes(tonic, scaleId)
        var byPc: [Int: ScaleNote] = [:]
        for n in notes { byPc[n.pc] = n }
        let pcSet = Set(byPc.keys)
        let tonicPc = notePc(tonic)
        var list: [Position]

        if shapeId == "neck" {
            list = []
            for s in stride(from: 6, through: 1, by: -1) {
                for f in 0...maxFret where pcSet.contains(mod(midiAt(s, f), 12)) { list.append(Position(string: s, fret: f)) }
            }
        } else if shapeId == "open" {
            list = windowShape(pcSet, 0, 4)
        } else if shapeId == "r6" || shapeId == "r5" {
            let s = shapeId == "r6" ? 6 : 5
            var r = mod(tonicPc - TUNING[s], 12)
            if r == 0 { r = 12 }
            list = windowShape(pcSet, r - 1, r + 3)
        } else if shapeId.hasPrefix("box"), let k = Int(shapeId.dropFirst(3)), (1...9).contains(k) {
            // Shapes are numbered from the minor-pentatonic root on the 6th string (shared by relative major).
            let minorTonic = sc.family == .major ? relativeMinorOf(tonic) : tonic
            let minorPent = scaleNotes(minorTonic, .minorPent)
            let pentSet = Set(minorPent.map { $0.pc })
            let startFret = mod(minorPent[k - 1].pc - TUNING[6], 12)
            let shape1Fret = mod(minorPent[0].pc - TUNING[6], 12)
            list = sequentialShape(pentSet, startFret, 2)
            let lowest = list.map { $0.fret }.min()!
            let highest = list.map { $0.fret }.max()!
            // Near the nut a 2-per-string walk can fall below an open string: play it an octave up instead.
            // Shapes that sit below shape 1 also move up when they still fit, so the shapes follow each other up the neck.
            if lowest < 0 || (k > 1 && startFret < shape1Fret && highest + 12 <= maxFret) {
                list = list.map { Position(string: $0.string, fret: $0.fret + 12) }
            }
            if sc.blues {
                let frets = list.map { $0.fret }
                let lo = frets.min()!, hi = frets.max()!
                let bluePc = mod(notePc(minorTonic) + 6, 12)
                for s in stride(from: 6, through: 1, by: -1) {
                    for f in lo...hi where mod(midiAt(s, f), 12) == bluePc { list.append(Position(string: s, fret: f)) }
                }
            }
        } else if shapeId.hasPrefix("3nps"), let k = Int(shapeId.dropFirst(4)), (1...9).contains(k) {
            let startFret = mod(notes[k - 1].pc - TUNING[6], 12)
            list = sequentialShape(pcSet, startFret, 3)
        } else {
            preconditionFailure("Unknown shape \(shapeId)")
        }

        // Sort by MIDI ascending, ties: higher string number first (stable, like JS).
        let out = decorate(list, byPc, tonicPc).enumerated().sorted { a, b in
            if a.element.midi != b.element.midi { return a.element.midi < b.element.midi }
            if a.element.string != b.element.string { return a.element.string > b.element.string }
            return a.offset < b.offset
        }.map { $0.element }
        let frets = out.map { $0.fret }
        return Shape(notes: out, minFret: frets.min() ?? 0, maxFret: frets.max() ?? 0)
    }

    /// Keep only the part of an (ascending) shape between its lowest and highest root.
    public static func rootToRoot(_ notes: [ShapeNote]) -> [ShapeNote] {
        let idx = notes.indices.filter { notes[$0].isRoot }
        if idx.count < 2 { return notes }
        return Array(notes[idx[0]...idx[idx.count - 1]])
    }

    /// Note-index sequences for practice patterns over n ascending notes.
    public static func patternIndices(_ n: Int, _ pattern: Pattern) -> [Int] {
        let up = Array(0..<max(n, 0))
        let down = Array(up.reversed())
        let updown = up + Array(down.dropFirst())
        func group(_ size: Int) -> [Int] {
            if n < size { return updown }
            var out: [Int] = []
            var i = 0
            while i + size <= n { for j in 0..<size { out.append(i + j) }; i += 1 }
            i = n - 1
            while i - size + 1 >= 0 { for j in 0..<size { out.append(i - j) }; i -= 1 }
            return out
        }
        switch pattern {
        case .up: return up
        case .down: return down
        case .updown: return updown
        case .groups3: return group(3)
        case .groups4: return group(4)
        case .thirds:
            if n < 3 { return updown }
            var out: [Int] = []
            var i = 0
            while i + 2 < n { out.append(i); out.append(i + 2); i += 1 }
            i = n - 1
            while i - 2 >= 0 { out.append(i); out.append(i - 2); i -= 1 }
            return out
        }
    }
}
