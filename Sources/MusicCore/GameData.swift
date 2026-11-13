// Guitar Quest - game data: Note Quest levels, jam progressions and strum patterns, theory-game keys.
// Ported from web/js/views/quest.js and views/harmony.js (the pure parts).
import Foundation

public struct QuestLevel: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let hint: String
    public let maxFret: Int
    public let acc: Bool
    public let test: @Sendable (Int, Int) -> Bool

    /// Every (string, fret ≤ 15) position of this level, in string-then-fret order.
    public var pool: [Position] {
        var out: [Position] = []
        for s in 1...6 { for f in 0...15 where test(s, f) { out.append(Position(string: s, fret: f)) } }
        return out
    }
}

public struct QuestGame: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let desc: String
}

public struct Progression: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let label: String
    public let family: Family
    public let degrees: [Int]
    public var sevenths: Bool = false
    public var dom7: Bool = false
    public var majorV: Bool = false
}

public struct StrumPattern: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let slots: String   // 8 eighth-note slots: D = down, U = up, - = keep moving
}

public enum TheoryLevel: String, Codable, Sendable, CaseIterable { case easy, medium, hard }

public enum GameData {
    static func natural(_ s: Int, _ f: Int) -> Bool { Theory.isNaturalPc(Theory.mod(Theory.midiAt(s, f), 12)) }

    public static let LEVELS: [QuestLevel] = [
        QuestLevel(id: "s12", name: "Strings 1 & 2", hint: "E F G on string 1 · B C D on string 2", maxFret: 3, acc: false,
                   test: { s, f in (s == 1 || s == 2) && [0, 1, 3].contains(f) }),
        QuestLevel(id: "s34", name: "Strings 3 & 4", hint: "G A on string 3 · D E F on string 4", maxFret: 3, acc: false,
                   test: { s, f in (s == 3 && [0, 2].contains(f)) || (s == 4 && [0, 2, 3].contains(f)) }),
        QuestLevel(id: "s56", name: "Strings 5 & 6", hint: "A B C on string 5 · E F G on string 6", maxFret: 3, acc: false,
                   test: { s, f in (s == 5 && [0, 2, 3].contains(f)) || (s == 6 && [0, 1, 3].contains(f)) }),
        QuestLevel(id: "first", name: "First position", hint: "Every natural note, frets 0-3, all strings", maxFret: 3, acc: false,
                   test: { s, f in f <= 3 && natural(s, f) }),
        QuestLevel(id: "sharps", name: "Sharps and flats", hint: "Every note, frets 0-4", maxFret: 4, acc: true,
                   test: { _, f in f <= 4 }),
        QuestLevel(id: "bass", name: "Bass strings up the neck", hint: "Strings 6 and 5, natural notes, frets 0-12", maxFret: 12, acc: false,
                   test: { s, f in s >= 5 && f <= 12 && natural(s, f) }),
        QuestLevel(id: "neck", name: "Whole neck", hint: "Natural notes on all strings, frets 0-12", maxFret: 12, acc: false,
                   test: { s, f in f <= 12 && natural(s, f) }),
        QuestLevel(id: "master", name: "Fretboard master", hint: "Every note, frets 0-12", maxFret: 12, acc: true,
                   test: { _, f in f <= 12 }),
    ]

    public static let GAMES: [QuestGame] = [
        QuestGame(id: "tab", name: "Tab → Note", desc: "A number on a tab line: which note is it?"),
        QuestGame(id: "staff", name: "Staff → Fretboard", desc: "A note on the staff: tap where it is on the guitar."),
        QuestGame(id: "hunt", name: "Note Hunt", desc: "Find a note on the highlighted string."),
    ]

    public static let PROGS: [Progression] = [
        Progression(id: "I-IV-V-I", name: "Three-chord song", label: "I - IV - V - I", family: .major, degrees: [1, 4, 5, 1]),
        Progression(id: "I-V-vi-IV", name: "Pop song", label: "I - V - vi - IV", family: .major, degrees: [1, 5, 6, 4]),
        Progression(id: "I-vi-IV-V", name: "1950s song", label: "I - vi - IV - V", family: .major, degrees: [1, 6, 4, 5]),
        Progression(id: "ii-V-I", name: "Jazz ii - V - I", label: "ii7 - V7 - Imaj7", family: .major, degrees: [2, 5, 1, 1], sevenths: true),
        Progression(id: "blues", name: "12-bar blues", label: "I7 - IV7 - V7 (12 bars)", family: .major, degrees: [1, 1, 1, 1, 4, 4, 1, 1, 5, 4, 1, 5], dom7: true),
        Progression(id: "i-iv-V-i", name: "Minor song", label: "i - iv - V - i", family: .minor, degrees: [1, 4, 5, 1], majorV: true),
        Progression(id: "i-VI-III-VII", name: "Epic minor", label: "i - VI - III - VII", family: .minor, degrees: [1, 6, 3, 7]),
    ]

    public static let STRUMS: [StrumPattern] = [
        StrumPattern(id: "whole", name: "One strum per bar", slots: "D-------"),
        StrumPattern(id: "quarters", name: "Four down-strums", slots: "D-D-D-D-"),
        StrumPattern(id: "folk", name: "Down, down-up, up-down-up", slots: "D-DU-UDU"),
        StrumPattern(id: "eighths", name: "Down-up all the way", slots: "DUDUDUDU"),
        StrumPattern(id: "rock", name: "Rock: down, down, down-up-down-up", slots: "D-D-DUDU"),
    ]

    /// Keys offered in the Jam view per family.
    public static func jamKeys(_ family: Family) -> [String] { family == .minor ? ["A", "E", "D", "B"] : ["C", "G", "D", "A", "E", "F"] }
    /// Keys offered in the Chord families view per family.
    public static func familyKeys(_ family: Family) -> [String] { family == .minor ? ["A", "E", "B", "D", "G", "C", "F#"] : ["C", "G", "D", "A", "E", "F", "Bb"] }

    public static func progChords(_ p: Progression, _ key: String) -> [HarmonizedChord] {
        let tonic = Theory.parseNote(key)
        let fam = Theory.harmonize(tonic, p.family, p.sevenths)
        return p.degrees.map { d in
            var ch = fam[d - 1]
            if p.dom7 { ch.type = .dom7 }
            if p.majorV && d == 5 { ch.type = .maj; ch.roman = "V" }
            if p.dom7 { ch.roman = Theory.romanFor(d - 1, .dom7) }
            return ch
        }
    }

    public static let THEORY_LEVEL_KEYS: [TheoryLevel: [String]] = [
        .easy: ["C", "G", "F", "D"],
        .medium: ["C", "G", "D", "A", "E", "F", "Bb", "Eb"],
        .hard: Theory.MAJOR_KEYS,
    ]
}
