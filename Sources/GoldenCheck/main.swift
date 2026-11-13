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
]
for (name, run) in runs {
    let before = failures
    do { try run() } catch { fail("\(name) threw \(error)") }
    print((failures == before ? "  ok   " : "  FAIL ") + name)
}
print("\n\(checks) checks, \(failures) failed, \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
exit(failures == 0 ? 0 : 1)
