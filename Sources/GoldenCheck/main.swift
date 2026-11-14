// Parity tests: the Swift engine must reproduce the JavaScript engine's golden output result-for-result.
// Golden files were produced with `node web/tests/export_golden.js` (see docs/08_TEST_PARITY.md).
import Foundation
import MusicCore


// MARK: - tiny assertion harness (no XCTest / swift-testing needed with the command line tools)
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0
func fail(_ msg: String) { failures += 1; if failures <= 25 { print("FAIL: " + msg) } }
func check(_ cond: Bool, _ msg: String = "", file: String = #fileID, line: Int = #line) {
    checks += 1
    if !cond { fail("\(msg) [\(file):\(line)]") }
}
func checkEq<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #fileID, line: Int = #line) {
    checks += 1
    if a != b { fail("\(msg) [\(file):\(line)]\n   got:      \(a)\n   expected: \(b)") }
}
struct RequireError: Error { let msg: String }
func require<T>(_ v: T?, _ msg: String = "required value missing", file: String = #fileID, line: Int = #line) throws -> T {
    guard let v else { fail("\(msg) [\(file):\(line)]"); throw RequireError(msg: msg) }
    return v
}
func expectThrows(_ body: () throws -> Void, file: String = #fileID, line: Int = #line) {
    checks += 1
    do { try body(); fail("expected an error [\(file):\(line)]") } catch {}
}

// MARK: - golden file shapes

struct GNote: Codable, Equatable { var note: String; var degree: Int; var semis: Int; var label: String; var pc: Int? }
struct GKeySig: Codable, Equatable { var fifths: Int; var list: [String]; var alters: [Int]; var majorTonic: String }
struct GHarm: Codable, Equatable { var degree: Int; var root: String; var type: String; var roman: String; var symbol: String }
struct GStaffPos: Codable, Equatable { var string: Int; var fret: Int; var midi: Int; var note: String; var soundingOctave: Int; var writtenStaffPos: Int }
struct GTheory: Codable {
    var scales: [String: [GNote]]
    var stepPatterns: [String: [String]]
    var keySignatures: [String: GKeySig]
    var relatives: [String: String]
    var chordTones: [String: [GNote]]
    var chordFormulas: [String: [String]]
    var harmonize: [String: [GHarm]]
    var staffPositions: [GStaffPos]
}
struct GShape: Codable, Equatable { var name: String; var minFret: Int; var maxFret: Int; var notes: [String] }
struct GShapes: Codable { var shapes: [String: GShape]; var rootToRoot: [String: [String]]; var patterns: [String: [String: [Int]]] }
struct GOpen: Codable, Equatable { var root: String; var type: String; var frets: [Int]; var fingers: [Int] }
struct GVoicing: Codable, Equatable { var kind: String; var frets: [Int]; var fingers: [Int]?; var rootFret: Int?; var validation: String? }
struct GChords: Codable { var open: [GOpen]; var voicings: [String: [GVoicing]] }
struct GExercise: Codable, Equatable { var bars: Int; var fifths: Int; var events: String }
struct GExercises: Codable { var format: String; var scores: [String: GExercise] }
struct GSong: Codable, Equatable { var id: String; var title: String; var source: String; var bars: Int; var fifths: Int; var events: [String] }
struct GGlyph: Codable, Equatable { var head: String; var flags: Int; var dots: Int }
struct GHead: Codable, Equatable { var pos: Int; var accidentalShown: Int? }
struct GNEvent: Codable, Equatable { var glyph: GGlyph; var rest: Bool; var heads: [GHead] }
struct GBeam: Codable, Equatable { var events: [Int]; var tuplet: Int; var dir: String? }
struct GSystem: Codable, Equatable { var measures: [Int]; var scale: Double }
struct GLayout: Codable { var systems: [GSystem]; var eventX: [Double] }
struct GNotation: Codable { var events: [GNEvent]; var beamGroups: [GBeam]; var layoutAt1000px: GLayout }
struct GLevel: Codable, Equatable { var name: String; var hint: String; var maxFret: Int; var accidentals: Bool; var pool: [String] }
struct GProgChord: Codable, Equatable { var symbol: String; var roman: String; var frets: [Int] }
struct GProg: Codable { var name: String; var label: String; var family: String; var degrees: [Int]; var byKey: [String: [GProgChord]] }
struct GStrum: Codable, Equatable { var id: String; var name: String; var slots: String }
struct GGame: Codable { var questLevels: [String: GLevel]; var progressions: [String: GProg]; var strums: [GStrum] }

func loadGolden<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let url = try require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden"), "missing golden \(name)")
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

let nm = Theory.noteAscii
let N = Theory.parseNote
let ROOTS: [String] = {
    var seen: [String] = []
    for k in Theory.MAJOR_KEYS + Theory.MINOR_KEYS where !seen.contains(k) { seen.append(k) }
    return seen
}()

func gnote(_ n: ScaleNote, withPc: Bool) -> GNote {
    GNote(note: nm(n.spelled), degree: n.degree, semis: n.semis, label: n.label, pc: withPc ? n.pc : nil)
}
func encShape(_ n: ShapeNote) -> String { "\(n.string)/\(n.fret) \(nm(n.spelled)) \(n.label)" + (n.isRoot ? " R" : "") }
func evText(_ ev: ScoreEvent) -> String {
    let body = ev.rest ? "r" : ev.notes.map { "\($0.string)/\($0.fret)=\(nm($0.spelled))" }.joined(separator: "+")
    return body + ":\(ev.dur)" + (ev.tuplet != 0 ? "t" : "")
}

// MARK: - theory.json

struct TheoryGoldenTests {
    func testTheoryGolden() throws {
        let g = try loadGolden("theory", as: GTheory.self)
        var checked = 0
        for sid in ScaleID.allCases {
            checkEq(Theory.stepPattern(sid), g.stepPatterns[sid.rawValue], "stepPattern \(sid)")
            for k in Theory.keyNames(Theory.scale(sid).family) {
                let key = "\(sid.rawValue):\(k)"
                checkEq(Theory.scaleNotes(N(k), sid).map { gnote($0, withPc: true) }, g.scales[key], "scale \(key)")
                checked += 1
            }
        }
        for fam in Family.allCases {
            for k in Theory.keyNames(fam) {
                let key = "\(fam.rawValue):\(k)"
                let ks = Theory.keySignature(N(k), fam)
                checkEq(GKeySig(fifths: ks.fifths, list: ks.list.map(nm), alters: ks.alters, majorTonic: nm(ks.majorTonic)), g.keySignatures[key], "keySig \(key)")
                let rel = fam == .major ? Theory.relativeMinorOf(N(k)) : Theory.relativeMajorOf(N(k))
                checkEq(nm(rel), g.relatives[key], "relative \(key)")
                for sev in [false, true] {
                    let hk = key + ":" + (sev ? "7" : "3")
                    let h = Theory.harmonize(N(k), fam, sev).map { GHarm(degree: $0.degree, root: nm($0.root), type: $0.type.rawValue, roman: $0.roman, symbol: Theory.chordSymbol($0.root, $0.type)) }
                    checkEq(h, g.harmonize[hk], "harmonize \(hk)")
                    checked += 1
                }
            }
        }
        for r in ROOTS {
            for t in ChordType.allCases {
                let key = "\(r):\(t.rawValue)"
                checkEq(Theory.chordTones(N(r), t).map { gnote($0, withPc: false) }, g.chordTones[key], "chordTones \(key)")
                checked += 1
            }
        }
        checkEq(g.chordTones.count, ROOTS.count * ChordType.allCases.count)
        for t in ChordType.allCases { checkEq(Theory.chordFormula(t), g.chordFormulas[t.rawValue], "formula \(t)") }
        var sp: [GStaffPos] = []
        for s in 1...6 { for f in 0...15 {
            let midi = Theory.midiAt(s, f)
            for pref in [AccidentalPref.sharp, .flat] {
                let spn = Theory.spellPc(midi % 12, pref)
                let oct = Theory.octaveOf(midi, spn)
                sp.append(GStaffPos(string: s, fret: f, midi: midi, note: nm(spn), soundingOctave: oct, writtenStaffPos: Theory.staffPos(spn.letter, oct + 1)))
            }
        } }
        checkEq(sp.count, g.staffPositions.count, "staffPositions count")
        for (a, b) in zip(sp, g.staffPositions) where a != b { checkEq(a, b, "staffPosition"); break }
        checkEq(checked, 60 + 48 + 168, "theory keys checked")
    }
}

// MARK: - shapes.json

struct ShapesGoldenTests {
    func testShapesGolden() throws {
        let g = try loadGolden("shapes", as: GShapes.self)
        var count = 0
        for sid in ScaleID.allCases {
            for k in Theory.keyNames(Theory.scale(sid).family) {
                for o in Theory.shapeOptions(sid) {
                    let key = "\(sid.rawValue):\(k):\(o.id)"
                    let sh = Theory.buildShape(N(k), sid, o.id, 15)
                    let mine = GShape(name: o.name, minFret: sh.minFret, maxFret: sh.maxFret, notes: sh.notes.map(encShape))
                    checkEq(mine, g.shapes[key], "shape \(key)")
                    if o.id != "neck" {
                        checkEq(Theory.rootToRoot(sh.notes).map(encShape), g.rootToRoot[key], "rootToRoot \(key)")
                    }
                    count += 1
                }
            }
        }
        checkEq(count, g.shapes.count)
        for p in Pattern.allCases {
            for n in 1...24 { checkEq(Theory.patternIndices(n, p), g.patterns[p.rawValue]?[String(n)], "pattern \(p) n=\(n)") }
        }
    }
}

// MARK: - chords.json

struct ChordsGoldenTests {
    func testChordsGolden() throws {
        let g = try loadGolden("chords", as: GChords.self)
        checkEq(Chords.OPEN.map { GOpen(root: nm($0.root), type: $0.type.rawValue, frets: $0.frets, fingers: $0.fingers!) }, g.open)
        var count = 0
        for r in ROOTS {
            for t in ChordType.allCases {
                let key = "\(r):\(t.rawValue)"
                let vs = Chords.voicingsFor(N(r), t).map { GVoicing(kind: $0.kind.rawValue, frets: $0.frets, fingers: $0.fingers, rootFret: $0.rootFret, validation: Chords.validate($0)) }
                checkEq(vs, g.voicings[key], "voicings \(key)")
                for v in vs { checkEq(v.validation, nil, "voicing \(key) validates") }
                count += 1
            }
        }
        checkEq(count, g.voicings.count)
    }
}

// MARK: - exercises.json (all 20 160 combinations) and songs.json

struct ExercisesGoldenTests {
    func testAllExerciseCombinations() throws {
        let g = try loadGolden("exercises", as: GExercises.self)
        var count = 0, failures = 0
        for sid in ScaleID.allCases {
            for k in Theory.keyNames(Theory.scale(sid).family) {
                for o in Theory.shapeOptions(sid) where o.id != "neck" {
                    for p in Pattern.allCases { for r in Rhythm.allCases { for range in ExerciseRange.allCases {
                        let key = [sid.rawValue, k, o.id, p.rawValue, r.rawValue, range.rawValue].joined(separator: ":")
                        let sc = try Exercises.buildScaleScore(ScaleScoreOptions(tonic: k, scaleId: sid, shapeId: o.id, pattern: p, rhythm: r, range: range))
                        let mine = GExercise(bars: sc.measures.count, fifths: sc.keySig.fifths, events: sc.events.map(evText).joined(separator: " "))
                        if mine != g.scores[key] {
                            failures += 1
                            if failures < 10 { fail("exercise \(key)\n got: \(mine)\n exp: \(String(describing: g.scores[key]))") }
                        }
                        count += 1
                    } } }
                }
            }
        }
        checkEq(failures, 0, "\(failures) of \(count) exercises differ")
        checkEq(count, 20160)
        checkEq(count, g.scores.count)
    }

    func testSongsGolden() throws {
        let g = try loadGolden("songs", as: [GSong].self)
        checkEq(Songs.all.count, g.count)
        for (song, gs) in zip(Songs.all, g) {
            let sc = try Exercises.buildSongScore(song)
            checkEq(GSong(id: song.id, title: song.title, source: song.notes, bars: sc.measures.count, fifths: sc.keySig.fifths, events: sc.events.map(evText)), gs, "song \(song.id)")
        }
    }

    func testTimeline() throws {
        let sc = try Exercises.buildSongScore(Songs.all[0])
        let tl = Exercises.timeline(sc)
        checkEq(tl.count, sc.events.count)
        checkEq(tl[0].beat, 0)
        checkEq(tl[0].beats, 1)
        checkEq(tl.last!.beats, 4)
        checkEq(tl.last!.beat + tl.last!.beats, Double(sc.totalTicks) / 12)
    }
}

// MARK: - notation.json

struct NotationGoldenTests {
    func testNotationGolden() throws {
        let g = try loadGolden("notation", as: [String: GNotation].self)
        var sample: [(String, Score)] = try Songs.all.map { ($0.id, try Exercises.buildSongScore($0)) }
        sample += [
            ("Eb-major-3nps3-groups4-s", try Exercises.buildScaleScore(ScaleScoreOptions(tonic: "Eb", scaleId: .major, shapeId: "3nps3", pattern: .groups4, rhythm: .s, range: .full))),
            ("A-blues-box1-groups3-t", try Exercises.buildScaleScore(ScaleScoreOptions(tonic: "A", scaleId: .blues, shapeId: "box1", pattern: .groups3, rhythm: .t, range: .full))),
            ("F#-minor-r6-thirds-e", try Exercises.buildScaleScore(ScaleScoreOptions(tonic: "F#", scaleId: .minor, shapeId: "r6", pattern: .thirds, rhythm: .e, range: .root))),
            ("A-minorPent-box1-updown-e", try Exercises.buildScaleScore(ScaleScoreOptions(tonic: "A", scaleId: .minorPent, shapeId: "box1", pattern: .updown, rhythm: .e, range: .full))),
        ]
        checkEq(sample.count, g.count)
        for (id, sc) in sample {
            let exp = try require(g[id], "missing notation sample \(id)")
            let L = Notation.layout(sc, LayoutOptions(width: 1000, showStaff: true, showTab: true, showNames: false, colors: false, naming: .letters))
            let events = L.prep.map { p in
                GNEvent(glyph: GGlyph(head: p.nv.head.rawValue, flags: p.nv.flags, dots: p.nv.dots), rest: p.ev.rest,
                        heads: p.heads.map { GHead(pos: $0.pos, accidentalShown: $0.acc) })
            }
            checkEq(events, exp.events, "notation events \(id)")
            let beams = L.beams.all.map { GBeam(events: $0.items, tuplet: $0.tuplet, dir: $0.dir?.rawValue) }
            checkEq(beams, exp.beamGroups, "beam groups \(id)")
            checkEq(L.systems.map { $0.measures }, exp.layoutAt1000px.systems.map { $0.measures }, "systems \(id)")
            for (s, gs) in zip(L.systems, exp.layoutAt1000px.systems) {
                check(abs(s.scale - gs.scale) <= 0.0002, "system scale \(id)")
            }
            checkEq(L.prep.count, exp.layoutAt1000px.eventX.count)
            for (p, x) in zip(L.prep, exp.layoutAt1000px.eventX) {
                check(abs(p.x - x) <= 0.11, "event x \(id)")
            }
        }
    }
}

// MARK: - game.json

struct GameGoldenTests {
    func testGameGolden() throws {
        let g = try loadGolden("game", as: GGame.self)
        checkEq(GameData.LEVELS.count, g.questLevels.count)
        for lv in GameData.LEVELS {
            let mine = GLevel(name: lv.name, hint: lv.hint, maxFret: lv.maxFret, accidentals: lv.acc, pool: lv.pool.map { "\($0.string)/\($0.fret)" })
            checkEq(mine, g.questLevels[lv.id], "level \(lv.id)")
        }
        checkEq(GameData.PROGS.count, g.progressions.count)
        for p in GameData.PROGS {
            let exp = try require(g.progressions[p.id])
            checkEq(p.name, exp.name); checkEq(p.label, exp.label)
            checkEq(p.family.rawValue, exp.family); checkEq(p.degrees, exp.degrees)
            for k in GameData.jamKeys(p.family) {
                let mine = GameData.progChords(p, k).map { c in
                    GProgChord(symbol: Theory.chordSymbol(c.root, c.type), roman: c.roman, frets: Chords.bestVoicing(c.root, c.type)!.frets)
                }
                checkEq(mine, exp.byKey[k], "prog \(p.id) in \(k)")
            }
            checkEq(Set(exp.byKey.keys), Set(GameData.jamKeys(p.family)))
        }
        checkEq(GameData.STRUMS.map { GStrum(id: $0.id, name: $0.name, slots: $0.slots) }, g.strums)
    }
}

// MARK: - hand-written checks (docs/08 §2.4) — they explain *why* the data is right

struct HandWrittenTests {
    func names(_ list: [ScaleNote]) -> String { list.map { nm($0.spelled) }.joined(separator: " ") }
    func names(_ list: [SpelledNote]) -> String { list.map(nm).joined(separator: " ") }
    func frets(_ shape: Shape) -> String {
        var by: [Int: [Int]] = [:]
        for n in shape.notes { by[n.string, default: []].append(n.fret) }
        return [6, 5, 4, 3, 2, 1].map { (by[$0] ?? []).sorted().map(String.init).joined(separator: ",") }.joined(separator: " | ")
    }

    func testScales() {
        checkEq(names(Theory.scaleNotes(N("D"), .major)), "D E F# G A B C#")
        checkEq(names(Theory.scaleNotes(N("F#"), .major)), "F# G# A# B C# D# E#")
        checkEq(names(Theory.scaleNotes(N("Db"), .major)), "Db Eb F Gb Ab Bb C")
        checkEq(names(Theory.scaleNotes(N("G#"), .minor)), "G# A# B C# D# E F#")
        checkEq(names(Theory.scaleNotes(N("A"), .blues)), "A C D Eb E G")
        checkEq(Theory.stepPattern(.major), ["W", "W", "H", "W", "W", "W", "H"])
        checkEq(Theory.scaleNotes(N("A"), .minor).map { $0.label }, ["1", "2", "♭3", "4", "5", "♭6", "♭7"])
    }

    func testKeySignatures() {
        checkEq(names(Theory.keySignature(N("E"), .major).list), "F# C# G# D#")
        checkEq(names(Theory.keySignature(N("Ab"), .major).list), "Bb Eb Ab Db")
        checkEq(Theory.keySignature(N("Eb"), .minor).fifths, -6)
        checkEq(Theory.keySignature(N("F#"), .major).fifths, 6)
        checkEq(nm(Theory.relativeMinorOf(N("Eb"))), "C")
        checkEq(nm(Theory.relativeMajorOf(N("F#"))), "A")
    }

    func testChords() {
        let hC = Theory.harmonize(N("C"), .major, false)
        checkEq(hC.map { Theory.chordSymbol($0.root, $0.type) }.joined(separator: " "), "C Dm Em F G Am Bdim")
        checkEq(hC.map { $0.roman }.joined(separator: " "), "I ii iii IV V vi vii°")
        checkEq(Theory.harmonize(N("C"), .major, true).map { Theory.chordSymbol($0.root, $0.type) }.joined(separator: " "), "Cmaj7 Dm7 Em7 Fmaj7 G7 Am7 Bm7♭5")
        checkEq(Theory.harmonize(N("A"), .minor, false).map { $0.roman }.joined(separator: " "), "i ii° III iv v VI VII")
        checkEq(names(Theory.chordTones(N("E"), .dim7)), "E G Bb Db")
        checkEq(Theory.chordFormula(.dim7), ["1", "♭3", "♭5", "♭♭7"])
    }

    func testOctaveAndStaff() {
        checkEq(Theory.octaveOf(40, N("E")), 2)
        checkEq(Theory.octaveOf(60, N("B#")), 3)
        checkEq(Theory.octaveOf(59, N("Cb")), 4)
        checkEq(Theory.staffPos(2, Theory.octaveOf(40, N("E")) + 1), -7)
        checkEq(Theory.staffPos(3, 5), 8)
        checkEq(Theory.lowestPosition(59), Position(string: 2, fret: 0))
        checkEq(Theory.lowestPosition(57), Position(string: 3, fret: 2))
    }

    func testShapes() {
        checkEq(frets(Theory.buildShape(N("A"), .minorPent, "box1")), "5,8 | 5,7 | 5,7 | 5,7 | 5,8 | 5,8")
        checkEq(frets(Theory.buildShape(N("A"), .minorPent, "box2")), "8,10 | 7,10 | 7,10 | 7,9 | 8,10 | 8,10")
        checkEq(frets(Theory.buildShape(N("A"), .minorPent, "box3")), "10,12 | 10,12 | 10,12 | 9,12 | 10,13 | 10,12")
        checkEq(frets(Theory.buildShape(N("A"), .minorPent, "box4")), "12,15 | 12,15 | 12,14 | 12,14 | 13,15 | 12,15")
        checkEq(frets(Theory.buildShape(N("A"), .minorPent, "box5")), "3,5 | 3,5 | 2,5 | 2,5 | 3,5 | 3,5")
        checkEq(frets(Theory.buildShape(N("E"), .minorPent, "box1")), "0,3 | 0,2 | 0,2 | 0,2 | 0,3 | 0,3")
        checkEq(frets(Theory.buildShape(N("A"), .blues, "box1")), "5,8 | 5,6,7 | 5,7 | 5,7,8 | 5,8 | 5,8")
        checkEq(frets(Theory.buildShape(N("C"), .major, "open")), "0,1,3 | 0,2,3 | 0,2,3 | 0,2 | 0,1,3 | 0,1,3")
        checkEq(Theory.rootToRoot(Theory.buildShape(N("C"), .major, "r5").notes).map { nm($0.spelled) }.joined(separator: " "), "C D E F G A B C")
        checkEq(Theory.patternIndices(4, .updown), [0, 1, 2, 3, 2, 1, 0])
        checkEq(Theory.patternIndices(4, .groups3), [0, 1, 2, 1, 2, 3, 3, 2, 1, 2, 1, 0])
        checkEq(Theory.patternIndices(5, .thirds), [0, 2, 1, 3, 2, 4, 4, 2, 3, 1, 2, 0])
    }

    func testVoicings() {
        func str(_ v: Voicing) -> String { v.frets.map { $0 < 0 ? "x" : String($0) }.joined() }
        checkEq(str(Chords.bestVoicing(N("B"), .min)!), "x24432")
        checkEq(str(Chords.bestVoicing(N("B"), .dim)!), "x2343x")
        checkEq(str(Chords.bestVoicing(N("C"), .aug)!), "x3211x") // docs/08 says x3221x, but the JS test (chords_tests.js) and the golden file say x3211x (C E G♯ C)
        checkEq(str(Chords.bestVoicing(N("C"), .dim7)!), "x3424x")
        for fam in Family.allCases { for k in Theory.keyNames(fam) { for sev in [false, true] {
            for c in Theory.harmonize(N(k), fam, sev) { check(Chords.bestVoicing(c.root, c.type) != nil, "\(k) \(c.roman)") }
        } } }
    }

    func testSongsAndScores() throws {
        let mary = try Exercises.buildSongScore(Songs.all[0])
        checkEq(mary.events.prefix(3).map { "\($0.notes[0].string)/\($0.notes[0].fret)" }, ["1/0", "2/3", "2/1"])
        let blues = try Exercises.buildScaleScore(ScaleScoreOptions(tonic: "A", scaleId: .blues, shapeId: "box1", pattern: .up, rhythm: .e, range: .full))
        let L = Notation.layout(blues, LayoutOptions(width: 900))
        check(L.prep.contains { $0.heads.contains { $0.acc == -1 && nm($0.spelled) == "Eb" } }, "A blues prints a ♭ on E♭")
        let dmaj = try Exercises.buildScaleScore(ScaleScoreOptions(tonic: "D", scaleId: .major, shapeId: "open", pattern: .up, rhythm: .e, range: .root))
        check(!(Notation.layout(dmaj, LayoutOptions(width: 900)).prep.contains { $0.hasAcc }), "D major prints no accidentals")
        expectThrows { _ = try Exercises.buildScaleScore(ScaleScoreOptions(tonic: "A", scaleId: .minorPent, shapeId: "neck", pattern: .up, rhythm: .e, range: .full)) }
    }

    func testModHelper() {
        checkEq(Theory.mod(-1, 12), 11)
        checkEq(Theory.mod(-13, 12), 11)
        checkEq(jsRound(-0.5), 0)
        checkEq(jsRound(2.5), 3)
    }
}


// MARK: - importers and sync (Song Player)

struct ImportTests {
    func sample(_ name: String, _ ext: String) throws -> Data {
        let url = try require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Samples"), "missing sample \(name)")
        return try Data(contentsOf: url)
    }

    func testMusicXMLMary() throws {
        let piece = try ScoreImporter.importMusicXML(try sample("mary", "musicxml"))
        checkEq(piece.title, "Mary Had a Little Lamb")
        checkEq(piece.tracks.count, 1)
        let t = piece.tracks[0]
        check(t.hasTab, "string/fret read from the file")
        let sc = t.score
        checkEq(sc.tpb, 48)
        checkEq(sc.measures.count, 8)
        checkEq(sc.tempo, 90)
        checkEq(sc.tempoMap.map { $0.bpm }, [90, 60])
        checkEq(sc.tempoMap[1].tick, 7 * 192, "second tempo mark at bar 8")
        // same notes and (×4) durations as the built-in song, whose positions come from lowestPosition()
        let ref = try Exercises.buildSongScore(Songs.all[0])
        let mine = sc.events.map { evText($0) }
        let want = ref.events.map { ev -> String in
            var e = ev; e.dur *= 4
            return evText(e)
        }
        checkEq(mine, want, "Mary via MusicXML == built-in Mary (ticks ×4)")
        // notation layout must accept the 48-tpb score
        let L = Notation.layout(sc, LayoutOptions(width: 900))
        checkEq(L.prep[0].nv, Glyph(head: .black, flags: 0, dots: 0))
        checkEq(L.prep[6].nv, Glyph(head: .half, flags: 0, dots: 0))
        checkEq(L.prep.last!.nv, Glyph(head: .whole, flags: 0, dots: 0))
    }

    func testGPIFSample() throws {
        let piece = try ScoreImporter.importGPIF(try sample("sample", "gpif"))
        checkEq(piece.title, "GPIF sample")
        checkEq(piece.tracks.count, 1)
        let sc = piece.tracks[0].score
        checkEq(sc.measures.count, 2)
        checkEq(sc.measureLengths, [192, 144], "4/4 then 3/4")
        checkEq(sc.timeSignature(at: 1), [3, 4])
        checkEq(sc.keySig.fifths, 1)
        checkEq(sc.tempo, 120)
        let ev = sc.events
        // bar 1: quarter (A on string 1 fret 5), three triplet eighths, a palm-muted half-note chord (6/0 + 5/2)
        checkEq(ev[0].dur, 48); checkEq(ev[0].notes[0].string, 1); checkEq(ev[0].notes[0].fret, 5); checkEq(nm(ev[0].notes[0].spelled), "A")
        checkEq(ev[1].dur, 16); checkEq(ev[1].tuplet, 3); checkEq(ev[1].writtenDur, 24); checkEq(ev[1].notes[0].marks, ["h"])
        checkEq(ev[3].notes[0].string, 2)
        checkEq(ev[4].dur, 96); checkEq(ev[4].notes.count, 2); checkEq(ev[4].notes[0].string, 6); checkEq(ev[4].notes[1].string, 5)
        check(ev[4].notes[0].marks.contains("PM"))
        checkEq(ev[4].tick, 48 + 3 * 16)
        // bar 2: dotted quarter (tied) + quarter rest, then padding rest to 3/4
        checkEq(ev[5].dur, 72); check(ev[5].notes[0].tied); checkEq(ev[5].tick, 192)
        checkEq(ev[6].rest, true); checkEq(ev[6].dur, 48)
        checkEq(ev[7].rest, true); checkEq(ev[7].dur, 24, "padding rest")
        checkEq(sc.totalTicks, 192 + 144)
        let L = Notation.layout(sc, LayoutOptions(width: 900))
        checkEq(L.prep[1].nv, Glyph(head: .black, flags: 1, dots: 0))
        checkEq(L.prep[5].nv, Glyph(head: .black, flags: 0, dots: 1))
        checkEq(L.systems[0].bars[1].timeSig, [3, 4], "time change printed at bar 2")
        checkEq(L.beams.groups.count, 1, "the three triplet eighths beam together")
    }

    func testTempoTimelineAndSync() throws {
        // 2 bars at 120 then 2 bars at 60 (4/4, tpb 48): 4 s + 8 s
        let tl = TempoTimeline(tpb: 48, tempo: 120, tempoMap: [TempoMark(tick: 0, bpm: 120), TempoMark(tick: 384, bpm: 60)], totalTicks: 768)
        check(abs(tl.seconds(atTick: 384) - 4) < 1e-9)
        check(abs(tl.seconds(atTick: 768) - 12) < 1e-9)
        check(abs(tl.tick(atSeconds: 6) - 480) < 1e-9)
        check(abs(tl.totalSeconds - 12) < 1e-9)
        // no anchors: media second 0 = tick 0
        let s0 = SyncMap(timeline: tl, anchors: [])
        check(abs(s0.tick(atMediaTime: 4) - 384) < 1e-9)
        // one anchor: the music starts 10 s into the video
        let s1 = SyncMap(timeline: tl, anchors: [SyncAnchor(mediaTime: 10, tick: 0)])
        check(abs(s1.tick(atMediaTime: 14) - 384) < 1e-9)
        check(abs(s1.mediaTime(atTick: 384) - 14) < 1e-9)
        check(s1.tick(atMediaTime: 0) < 0, "before the music starts the tick is negative")
        // two anchors: the recording is slower than written between them (bar 3 reached at 20 s instead of 14 s)
        let s2 = SyncMap(timeline: tl, anchors: [SyncAnchor(mediaTime: 10, tick: 0), SyncAnchor(mediaTime: 20, tick: 384)])
        check(abs(s2.tick(atMediaTime: 15) - 192) < 1e-9, "halfway between anchors = halfway in nominal time")
        check(abs(s2.mediaTime(atTick: 192) - 15) < 1e-9)
        check(abs(s2.tick(atMediaTime: 24) - 576) < 1e-9, "after the last anchor the written tempo continues")
        for m in stride(from: 0.0, through: 40, by: 2.5) { check(abs(s2.mediaTime(atTick: s2.tick(atMediaTime: m)) - m) < 1e-6, "round trip at \(m)") }
        // anchors that run backwards are dropped
        let s3 = SyncMap(timeline: tl, anchors: [SyncAnchor(mediaTime: 10, tick: 100), SyncAnchor(mediaTime: 12, tick: 50)])
        checkEq(s3.anchors.count, 1)
        // scaled timeline: at base tempo 120 the slow half takes twice the beats
        let sc = Exercises.finalizeMeasures([[ScoreEvent(dur: 192, notes: [])], [ScoreEvent(dur: 192, notes: [])], [ScoreEvent(dur: 192, notes: [])], [ScoreEvent(dur: 192, notes: [])]],
                                            lengths: [192, 192, 192, 192], times: [[4, 4], nil, nil, nil], tpb: 48,
                                            meta: ScoreMeta(keySig: Theory.keySignature(SpelledNote(0, 0), .major), tempo: 120), tempoMap: tl.marks)
        let items = Exercises.timeline(sc, baseTempo: 120)
        check(abs(items[2].beat - 8) < 1e-9); check(abs(items[2].beats - 8) < 1e-9); check(abs(items[0].beats - 4) < 1e-9)
    }
}

// MARK: - Guitar Pro binary / gpif cross-checks on alphaTab fixtures (Samples/alphatab, MPL-2.0)

struct GuitarProTests {
    func fixture(_ name: String) throws -> URL {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return try require(Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Samples/alphatab"), "missing fixture \(name)")
    }
    func unzip(_ url: URL, _ member: String) throws -> Data {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-p", url.path, member]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try p.run(); let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return d
    }
    func load(_ name: String) throws -> ImportedPiece {
        let url = try fixture(name)
        switch url.pathExtension {
        case "gp": return try ScoreImporter.importGPIF(try unzip(url, "Content/score.gpif"))
        case "mxl":
            let c = String(data: try unzip(url, "META-INF/container.xml"), encoding: .utf8) ?? ""
            let r = try require(c.range(of: "full-path=\""), "container"); let e = try require(c[r.upperBound...].firstIndex(of: "\""), "container")
            return try ScoreImporter.importMusicXML(try unzip(url, String(c[r.upperBound..<e])))
        case "musicxml": return try ScoreImporter.importMusicXML(try Data(contentsOf: url))
        default: return try ScoreImporter.importGP345(try Data(contentsOf: url))
        }
    }
    /// Notes only (bar counts may differ when a file has trailing empty bars).
    func summary(_ t: ImportedTrack) -> String {
        let sc = t.score
        return "\(t.noteCount) notes, " + sc.events.filter { !$0.rest }.map { ev in ev.notes.map { "\($0.string)/\($0.fret)" }.joined(separator: "+") + ":\(ev.dur)" }.joined(separator: " ")
    }

    func testSameScoreAcrossFormats() throws {
        // the same test pieces saved by Guitar Pro 3, 4, 5 and 7 must import identically (strings/frets/durations)
        for base in ["notes", "hammer"] {
            let a = try load(base + ".gp3"), b = try load(base + ".gp4"), c = try load(base + ".gp5"), d = try load(base + ".gp")
            let sa = summary(a.tracks[0]), sb = summary(b.tracks[0]), sc = summary(c.tracks[0]), sd = summary(d.tracks[0])
            checkEq(sa, sb, "\(base): gp3 == gp4"); checkEq(sb, sc, "\(base): gp4 == gp5"); checkEq(sc, sd, "\(base): gp5 == gp7")
        }
        for base in ["chords", "slides", "strings", "repeat-close", "repeat-close-alternate-endings"] {
            let c = try load(base + ".gp5"), d = try load(base + ".gp")
            checkEq(summary(c.tracks[0]), summary(d.tracks[0]), "\(base): gp5 == gp7")
        }
        let n = try load("notes.gp5").tracks[0]
        checkEq(n.noteCount, 28); checkEq(n.score.events.count, 35, "an over-full bar keeps all its beats")
        let rc = try load("repeat-close.gp5").tracks[0].score
        checkEq(rc.measures.count, 5, "|: 2 bars :| x2 + 1 → 5 bars"); checkEq(rc.measureLabels, [1, 2, 1, 2, 3])
        let alt = try load("repeat-close-alternate-endings.gp5").tracks[0].score
        checkEq(alt.measures.count, 12, "alternate endings unrolled like Guitar Pro 7 does")
    }

    func testSerenadeGP5vsGP7() throws {
        let a = try load("serenade.gp5"), b = try load("serenade.gp")
        checkEq(a.title, "Serenade to a Dream"); checkEq(a.tracks.map { $0.name }, b.tracks.map { $0.name })
        for (x, y) in zip(a.tracks, b.tracks) {
            checkEq(x.score.measures.count, y.score.measures.count, "serenade \(x.name) bars")
            checkEq(x.noteCount, y.noteCount, "serenade \(x.name) notes")
            checkEq(x.score.measureLengths, y.score.measureLengths, "serenade \(x.name) bar lengths (6/8, 3/8)")
            // note-for-note: same string/fret sequence
            let nx = x.score.events.flatMap { $0.notes.map { "\($0.string)/\($0.fret)" } }
            let ny = y.score.events.flatMap { $0.notes.map { "\($0.string)/\($0.fret)" } }
            checkEq(nx.count, ny.count, "serenade \(x.name) note positions count")
            if nx.count == ny.count { checkEq(nx, ny, "serenade \(x.name) note positions") }
        }
        // (the GP5.0 file carries no key signature; the GP7 re-save added B♭ major — not comparable)
        checkEq(Int(a.tracks[0].score.tempoMap.first?.bpm ?? 0), 94)
        _ = Notation.layout(a.tracks[0].score, LayoutOptions(width: 1000))
    }

    func testTupletsAndTempo() throws {
        let t3 = try load("tuplets.gp3").tracks[0].score, t7 = try load("tuplets.gp").tracks[0].score
        checkEq(t3.events.map { "\($0.dur):\($0.tuplet)" }, t7.events.map { "\($0.dur):\($0.tuplet)" }, "tuplets gp3 == gp7")
        checkEq(t3.events[0].dur, 32); checkEq(t3.events[0].tuplet, 3); checkEq(t3.events[0].writtenDur, 48)
        let tempo = try load("vt-beat-tempo-change.gp").tracks[0].score
        checkEq(tempo.tempoMap.map { Int($0.bpm) }, [120, 60, 100, 120, 121, 120, 121, 120, 121])
        checkEq(tempo.tempoMap[1].tick, 96, "tempo change halfway through bar 1")
        expectThrows { _ = try load("time-signatures.gp5") }   // rests only → "no notes" (not a crash)
        let eff5 = try load("effects.gp5").tracks[0], eff3 = try load("effects.gp3").tracks[0], eff4 = try load("effects.gp4").tracks[0]
        checkEq(eff5.noteCount, 117); checkEq(eff3.noteCount, 117); checkEq(eff4.noteCount, 117)
        let marks = Set(eff5.score.events.flatMap { $0.notes.flatMap { $0.marks } })
        for m in ["PM", "h", "b", "/", "harm", "x", "~"] { check(marks.contains(m), "effects.gp5 has mark \(m)") }
        let tie = try load("tie-destination.musicxml").tracks[0].score
        checkEq(tie.events.count, 4); checkEq(tie.events[0].notes[0].fret, 9)
        let mxl = try load("compressed.mxl")
        checkEq(mxl.title, "Title"); checkEq(mxl.tracks[0].noteCount, 4)
    }
}

// MARK: - optional import smoke run: GQ_IMPORT_DIR=/folder swift run GoldenCheck
// Parses every .gp / .gp5 / .musicxml / .xml / .mxl file in the folder and prints a summary (no pass/fail; eyeball it).
func importSmoke(_ dir: String) {
    let fm = FileManager.default
    let files = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted()
    func unzip(_ path: String, _ member: String) -> Data? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-p", path, member]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return p.terminationStatus == 0 ? d : nil
    }
    for f in files {
        let path = dir + "/" + f
        let ext = (f as NSString).pathExtension.lowercased()
        do {
            let piece: ImportedPiece
            switch ext {
            case "gp": guard let d = unzip(path, "Content/score.gpif") else { print("  ?? \(f): no score.gpif"); continue }; piece = try ScoreImporter.importGPIF(d)
            case "gp5", "gp4", "gp3": piece = try ScoreImporter.importGP345(try Data(contentsOf: URL(fileURLWithPath: path)))
            case "musicxml", "xml": piece = try ScoreImporter.importMusicXML(try Data(contentsOf: URL(fileURLWithPath: path)))
            case "mxl":
                guard let d = unzip(path, "META-INF/container.xml"), let c = String(data: d, encoding: .utf8),
                      let r = c.range(of: "full-path=\""), let e = c[r.upperBound...].firstIndex(of: "\""), let x = unzip(path, String(c[r.upperBound..<e])) else { print("  ?? \(f): bad mxl"); continue }
                piece = try ScoreImporter.importMusicXML(x)
            default: continue
            }
            print("  \(f): \"\(piece.title)\" \(piece.tracks.count) track(s)")
            for t in piece.tracks.prefix(3) {
                let sc = t.score
                let ts = sc.measures.indices.map { sc.timeSignature(at: $0) }.map { "\($0[0])/\($0[1])" }
                var tsSummary: [String] = []
                for x in ts where tsSummary.last != x { tsSummary.append(x) }
                let tempos = sc.tempoMap.map { "\(Int($0.bpm))@\($0.tick)" }.joined(separator: " ")
                print("     - \(t.name): \(sc.measures.count) bars, \(sc.events.count) events, \(t.noteCount) notes, key \(sc.keySig.fifths), time \(tsSummary.joined(separator: " ")), tempo \(tempos.isEmpty ? String(sc.tempo) : tempos)")
                print("       \(sc.events.prefix(10).map { evText($0) }.joined(separator: " "))")
                let marks = Set(sc.events.flatMap { $0.notes.flatMap { $0.marks } })
                if !marks.isEmpty { print("       marks: \(marks.sorted().joined(separator: " "))") }
                _ = Notation.layout(sc, LayoutOptions(width: 1000))
            }
        } catch { print("  !! \(f): \(error)") }
    }
}
if let dir = ProcessInfo.processInfo.environment["GQ_IMPORT_DIR"] { importSmoke(dir); exit(0) }

// MARK: - entry point
let t0 = Date()
let runs: [(String, () throws -> Void)] = [
    ("theory", { try TheoryGoldenTests().testTheoryGolden() }),
    ("shapes", { try ShapesGoldenTests().testShapesGolden() }),
    ("chords", { try ChordsGoldenTests().testChordsGolden() }),
    ("exercises (20 160)", { try ExercisesGoldenTests().testAllExerciseCombinations() }),
    ("songs", { try ExercisesGoldenTests().testSongsGolden() }),
    ("timeline", { try ExercisesGoldenTests().testTimeline() }),
    ("notation", { try NotationGoldenTests().testNotationGolden() }),
    ("game", { try GameGoldenTests().testGameGolden() }),
    ("hand-written: scales", { HandWrittenTests().testScales() }),
    ("hand-written: key signatures", { HandWrittenTests().testKeySignatures() }),
    ("hand-written: chords", { HandWrittenTests().testChords() }),
    ("hand-written: octave/staff", { HandWrittenTests().testOctaveAndStaff() }),
    ("hand-written: shapes", { HandWrittenTests().testShapes() }),
    ("hand-written: voicings", { HandWrittenTests().testVoicings() }),
    ("hand-written: songs/scores", { try HandWrittenTests().testSongsAndScores() }),
    ("hand-written: mod", { HandWrittenTests().testModHelper() }),
    ("import: MusicXML (Mary)", { try ImportTests().testMusicXMLMary() }),
    ("import: Guitar Pro gpif sample", { try ImportTests().testGPIFSample() }),
    ("sync: tempo timeline + anchors", { try ImportTests().testTempoTimelineAndSync() }),
    ("Guitar Pro: same score in gp3/gp4/gp5/gp7", { try GuitarProTests().testSameScoreAcrossFormats() }),
    ("Guitar Pro: serenade gp5 vs gp7", { try GuitarProTests().testSerenadeGP5vsGP7() }),
    ("Guitar Pro: tuplets, tempo map, effects, mxl", { try GuitarProTests().testTupletsAndTempo() }),
]
for (name, run) in runs {
    let before = failures
    do { try run() } catch { fail("\(name) threw \(error)") }
    print((failures == before ? "  ok   " : "  FAIL ") + name)
}
print("\n\(checks) checks, \(failures) failed, \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
exit(failures == 0 ? 0 : 1)
