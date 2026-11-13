// Guitar Quest - chord voicings (open shapes + moveable barre shapes). Port of web/js/chords.js.
import Foundation

public enum VoicingKind: String, Codable, Sendable {
    case open
    case eShape = "E-shape"
    case aShape = "A-shape"
}

/// Frets and fingers are listed from the 6th (low E) string to the 1st (high e) string.
/// fret -1 = muted (×), 0 = open. finger 0 = none. `fingers == nil` = draw dots without numbers.
public struct Voicing: Hashable, Sendable {
    public var root: SpelledNote
    public var type: ChordType
    public var frets: [Int]
    public var fingers: [Int]?
    public var kind: VoicingKind
    public var rootFret: Int?
    public init(root: SpelledNote, type: ChordType, frets: [Int], fingers: [Int]?, kind: VoicingKind, rootFret: Int? = nil) {
        self.root = root; self.type = type; self.frets = frets; self.fingers = fingers; self.kind = kind; self.rootFret = rootFret
    }
}

public struct VoicingNote: Hashable, Sendable {
    public var string: Int
    public var fret: Int
    public var midi: Int
}

public struct MoveableShape: Sendable {
    public let offsets: [Int?]   // nil = muted
    public let fingers: [Int]?
}

public enum Chords {
    public static let X = -1 // muted string

    public static let OPEN: [Voicing] = {
        let rows: [(String, ChordType, [Int], [Int])] = [
            ("C", .maj, [X, 3, 2, 0, 1, 0], [0, 3, 2, 0, 1, 0]),
            ("C", .dom7, [X, 3, 2, 3, 1, 0], [0, 3, 2, 4, 1, 0]),
            ("C", .maj7, [X, 3, 2, 0, 0, 0], [0, 3, 2, 0, 0, 0]),
            ("D", .maj, [X, X, 0, 2, 3, 2], [0, 0, 0, 1, 3, 2]),
            ("D", .min, [X, X, 0, 2, 3, 1], [0, 0, 0, 2, 3, 1]),
            ("D", .dom7, [X, X, 0, 2, 1, 2], [0, 0, 0, 2, 1, 3]),
            ("D", .min7, [X, X, 0, 2, 1, 1], [0, 0, 0, 2, 1, 1]),
            ("D", .maj7, [X, X, 0, 2, 2, 2], [0, 0, 0, 1, 1, 1]),
            ("D", .sus2, [X, X, 0, 2, 3, 0], [0, 0, 0, 1, 3, 0]),
            ("D", .sus4, [X, X, 0, 2, 3, 3], [0, 0, 0, 1, 3, 4]),
            ("D", .power, [X, X, 0, 2, 3, X], [0, 0, 0, 1, 3, 0]),
            ("E", .maj, [0, 2, 2, 1, 0, 0], [0, 2, 3, 1, 0, 0]),
            ("E", .min, [0, 2, 2, 0, 0, 0], [0, 2, 3, 0, 0, 0]),
            ("E", .dom7, [0, 2, 0, 1, 0, 0], [0, 2, 0, 1, 0, 0]),
            ("E", .min7, [0, 2, 0, 0, 0, 0], [0, 2, 0, 0, 0, 0]),
            ("E", .maj7, [0, 2, 1, 1, 0, 0], [0, 3, 1, 2, 0, 0]),
            ("E", .sus4, [0, 2, 2, 2, 0, 0], [0, 2, 3, 4, 0, 0]),
            ("E", .power, [0, 2, 2, X, X, X], [0, 1, 2, 0, 0, 0]),
            ("F", .maj, [X, X, 3, 2, 1, 1], [0, 0, 3, 2, 1, 1]),
            ("F", .maj7, [X, X, 3, 2, 1, 0], [0, 0, 3, 2, 1, 0]),
            ("G", .maj, [3, 2, 0, 0, 0, 3], [3, 2, 0, 0, 0, 4]),
            ("G", .dom7, [3, 2, 0, 0, 0, 1], [3, 2, 0, 0, 0, 1]),
            ("G", .maj7, [3, 2, 0, 0, 0, 2], [3, 2, 0, 0, 0, 1]),
            ("A", .maj, [X, 0, 2, 2, 2, 0], [0, 0, 1, 2, 3, 0]),
            ("A", .min, [X, 0, 2, 2, 1, 0], [0, 0, 2, 3, 1, 0]),
            ("A", .dom7, [X, 0, 2, 0, 2, 0], [0, 0, 2, 0, 3, 0]),
            ("A", .min7, [X, 0, 2, 0, 1, 0], [0, 0, 2, 0, 1, 0]),
            ("A", .maj7, [X, 0, 2, 1, 2, 0], [0, 0, 2, 1, 3, 0]),
            ("A", .sus2, [X, 0, 2, 2, 0, 0], [0, 0, 1, 2, 0, 0]),
            ("A", .sus4, [X, 0, 2, 2, 3, 0], [0, 0, 1, 2, 3, 0]),
            ("A", .power, [X, 0, 2, 2, X, X], [0, 0, 1, 2, 0, 0]),
            ("B", .dom7, [X, 2, 1, 2, 0, 2], [0, 2, 1, 3, 0, 4]),
        ]
        return rows.map { Voicing(root: Theory.parseNote($0.0), type: $0.1, frets: $0.2, fingers: $0.3, kind: .open) }
    }()

    public static let E_SHAPES: [ChordType: MoveableShape] = [
        .maj: MoveableShape(offsets: [0, 2, 2, 1, 0, 0], fingers: [1, 3, 4, 2, 1, 1]),
        .min: MoveableShape(offsets: [0, 2, 2, 0, 0, 0], fingers: [1, 3, 4, 1, 1, 1]),
        .dom7: MoveableShape(offsets: [0, 2, 0, 1, 0, 0], fingers: [1, 3, 1, 2, 1, 1]),
        .min7: MoveableShape(offsets: [0, 2, 0, 0, 0, 0], fingers: [1, 3, 1, 1, 1, 1]),
        .sus4: MoveableShape(offsets: [0, 2, 2, 2, 0, 0], fingers: [1, 2, 3, 4, 1, 1]),
        .maj7: MoveableShape(offsets: [0, nil, 1, 1, 0, nil], fingers: [1, 0, 3, 4, 2, 0]),
        .dim: MoveableShape(offsets: [0, 1, 2, 0, nil, nil], fingers: nil),
        .power: MoveableShape(offsets: [0, 2, 2, nil, nil, nil], fingers: [1, 3, 4, 0, 0, 0]),
    ]
    public static let A_SHAPES: [ChordType: MoveableShape] = [
        .maj: MoveableShape(offsets: [nil, 0, 2, 2, 2, 0], fingers: [0, 1, 2, 3, 4, 1]),
        .min: MoveableShape(offsets: [nil, 0, 2, 2, 1, 0], fingers: [0, 1, 3, 4, 2, 1]),
        .dom7: MoveableShape(offsets: [nil, 0, 2, 0, 2, 0], fingers: [0, 1, 3, 1, 4, 1]),
        .min7: MoveableShape(offsets: [nil, 0, 2, 0, 1, 0], fingers: [0, 1, 3, 1, 2, 1]),
        .sus2: MoveableShape(offsets: [nil, 0, 2, 2, 0, 0], fingers: [0, 1, 3, 4, 1, 1]),
        .sus4: MoveableShape(offsets: [nil, 0, 2, 2, 3, 0], fingers: [0, 1, 2, 3, 4, 1]),
        .maj7: MoveableShape(offsets: [nil, 0, 2, 1, 2, 0], fingers: [0, 1, 3, 2, 4, 1]),
        .dim: MoveableShape(offsets: [nil, 0, 1, 2, 1, nil], fingers: [0, 1, 2, 4, 3, 0]),
        .m7b5: MoveableShape(offsets: [nil, 0, 1, 0, 1, nil], fingers: [0, 1, 3, 2, 4, 0]),
        .dim7: MoveableShape(offsets: [nil, 0, 1, -1, 1, nil], fingers: [0, 2, 3, 1, 4, 0]),
        .aug: MoveableShape(offsets: [nil, 0, -1, -2, -2, nil], fingers: [0, 3, 2, 1, 1, 0]),
        .power: MoveableShape(offsets: [nil, 0, 2, 2, nil, nil], fingers: [0, 1, 3, 4, 0, 0]),
    ]

    static func fromShape(_ root: SpelledNote, _ type: ChordType, _ shape: MoveableShape, _ rootString: Int) -> Voicing {
        var r = Theory.mod(Theory.notePc(root) - Theory.TUNING[rootString], 12)
        let minOff = shape.offsets.compactMap { $0 }.min() ?? 0
        if r == 0 || r + minOff < 1 { r += 12 } // keep it a real barre shape (open versions live in OPEN)
        let frets = shape.offsets.map { $0 == nil ? X : r + $0! }
        let fingers = shape.fingers.map { fing in fing.enumerated().map { i, f in frets[i] <= 0 ? 0 : f } }
        return Voicing(root: root, type: type, frets: frets, fingers: fingers, kind: rootString == 6 ? .eShape : .aShape, rootFret: r)
    }

    public static func voicingsFor(_ root: SpelledNote, _ type: ChordType) -> [Voicing] {
        let pc = Theory.notePc(root)
        var out = OPEN.filter { Theory.notePc($0.root) == pc && $0.type == type }.map { v -> Voicing in
            var c = v; c.root = root; return c
        }
        var moveable: [Voicing] = []
        if let e = E_SHAPES[type] { moveable.append(fromShape(root, type, e, 6)) }
        if let a = A_SHAPES[type] { moveable.append(fromShape(root, type, a, 5)) }
        moveable.sort { ($0.rootFret ?? 0) < ($1.rootFret ?? 0) }
        out.append(contentsOf: moveable)
        return out
    }
    public static func bestVoicing(_ root: SpelledNote, _ type: ChordType) -> Voicing? { voicingsFor(root, type).first }

    /// Sounding notes, low to high.
    public static func voicingNotes(_ v: Voicing) -> [VoicingNote] {
        var out: [VoicingNote] = []
        for (i, f) in v.frets.enumerated() where f >= 0 {
            let string = 6 - i
            out.append(VoicingNote(string: string, fret: f, midi: Theory.midiAt(string, f)))
        }
        return out
    }

    /// nil when the voicing is correct: every sounding note is a chord tone, the root is in the bass,
    /// the defining tones (3rd or suspension, 7th) are present (the 5th may be left out), fingers match fretted strings.
    public static func validate(_ v: Voicing) -> String? {
        let tones = Theory.chordTones(v.root, v.type)
        let pcs = Set(tones.map { $0.pc })
        let notes = voicingNotes(v)
        if notes.isEmpty { return "no notes" }
        for n in notes where !pcs.contains(Theory.mod(n.midi, 12)) { return "non-chord tone on string \(n.string)" }
        if Theory.mod(notes[0].midi, 12) != Theory.notePc(v.root) { return "root not in bass" }
        let have = Set(notes.map { Theory.mod($0.midi, 12) })
        for t in tones where t.degree != 5 && !have.contains(t.pc) { return "missing \(t.label)" }
        if let fingers = v.fingers {
            for i in 0..<6 {
                if v.frets[i] > 0 && fingers[i] == 0 { return "missing finger on string \(6 - i)" }
                if v.frets[i] <= 0 && fingers[i] != 0 { return "finger on open/muted string \(6 - i)" }
            }
        }
        return nil
    }
}
