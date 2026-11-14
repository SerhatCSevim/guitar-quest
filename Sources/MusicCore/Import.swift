// Score importers for the Song Player: MusicXML (partwise) and Guitar Pro 7/8 `score.gpif` XML.
// Both produce one Score per track at 48 ticks per quarter note (so 32nd notes, 16th triplets and dotted values fit).
import Foundation

public struct ImportedTrack: Sendable {
    public let name: String
    public let score: Score
    public let noteCount: Int
    public let hasTab: Bool          // string/fret came from the file (not guessed)
}

public struct ImportedPiece: Sendable {
    public let title: String
    public let artist: String
    public let tracks: [ImportedTrack]
}

public enum ImportError: Error, CustomStringConvertible {
    case notXML
    case unsupported(String)
    case empty

    public var description: String {
        switch self {
        case .notXML: return "The file is not readable XML."
        case .unsupported(let s): return s
        case .empty: return "No notes were found in the file."
        }
    }
}

/// Minimal XML tree (Foundation's XMLParser, no external dependencies).
public final class XNode {
    public let name: String
    public let attrs: [String: String]
    public var children: [XNode] = []
    public var text: String = ""
    init(name: String, attrs: [String: String]) { self.name = name; self.attrs = attrs }

    public func first(_ n: String) -> XNode? { children.first { $0.name == n } }
    public func all(_ n: String) -> [XNode] { children.filter { $0.name == n } }
    public func int(_ n: String) -> Int? { first(n).flatMap { Int($0.text.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    public func double(_ n: String) -> Double? { first(n).flatMap { Double($0.text.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    public func str(_ n: String) -> String? { first(n).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } }
    public var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Depth-first search for the first element with this name.
    public func find(_ n: String) -> XNode? {
        if name == n { return self }
        for c in children { if let f = c.find(n) { return f } }
        return nil
    }
}

final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: XNode?
    private var stack: [XNode] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let n = XNode(name: name, attrs: attributes)
        if let top = stack.last { top.children.append(n) } else { root = n }
        stack.append(n)
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { stack.last?.text += s }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
    // MusicXML files carry a DOCTYPE pointing at musicxml.org; never fetch it
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { Data() }
}

public enum ScoreImporter {
    public static let TPB = 48

    public static func parseXML(_ data: Data) throws -> XNode {
        let p = XMLParser(data: data)
        p.shouldResolveExternalEntities = false
        let b = XMLTreeBuilder()
        p.delegate = b
        guard p.parse(), let root = b.root else { throw ImportError.notXML }
        return root
    }

    // MARK: - shared helpers

    static let FIFTHS_MAJOR: [Int: String] = [-7: "Cb", -6: "Gb", -5: "Db", -4: "Ab", -3: "Eb", -2: "Bb", -1: "F", 0: "C", 1: "G", 2: "D", 3: "A", 4: "E", 5: "B", 6: "F#", 7: "C#"]

    static func keySignature(fifths: Int, minor: Bool) -> KeySignature {
        let name = FIFTHS_MAJOR[max(-7, min(7, fifths))] ?? "C"
        let major = Theory.parseNote(name)
        return minor ? Theory.keySignature(Theory.relativeMinorOf(major), .minor) : Theory.keySignature(major, .major)
    }

    /// Spell a MIDI pitch inside a key: use the key's own accidentals, else sharps for sharp keys / flats for flat keys.
    static func spell(midi: Int, keySig: KeySignature) -> SpelledNote {
        let pc = Theory.mod(midi, 12)
        for l in 0..<7 {
            let a = keySig.alters[l]
            if Theory.mod(Theory.LETTER_PC[l] + a, 12) == pc, a != 0 { return SpelledNote(l, a) }
        }
        return Theory.spellPc(pc, keySig.fifths < 0 ? .flat : .sharp)
    }

    /// A playable position for a sounding pitch with standard tuning when the file gives none.
    static func position(for midi: Int) -> Position? { Theory.lowestPosition(midi) }

    // MARK: - MusicXML

    struct MXNote { var onset: Int; var ev: ScoreEvent }

    public static func importMusicXML(_ data: Data) throws -> ImportedPiece {
        let root = try parseXML(data)
        if root.name == "score-timewise" { throw ImportError.unsupported("Timewise MusicXML is not supported; export a partwise file.") }
        guard root.name == "score-partwise" else { throw ImportError.unsupported("Not a MusicXML file (root element \(root.name)).") }
        let title = root.first("work")?.str("work-title") ?? root.str("movement-title") ?? ""
        let artist = root.first("identification")?.all("creator").first(where: { $0.attrs["type"] == "composer" || $0.attrs["type"] == "artist" })?.trimmed ?? ""
        var partNames: [String: String] = [:]
        for sp in root.first("part-list")?.all("score-part") ?? [] { partNames[sp.attrs["id"] ?? ""] = sp.str("part-name") ?? "" }

        var tracks: [ImportedTrack] = []
        for part in root.all("part") {
            let name = partNames[part.attrs["id"] ?? ""] ?? (part.attrs["id"] ?? "Part")
            if let t = importPart(part, name: name) { tracks.append(t) }
        }
        if tracks.isEmpty { throw ImportError.empty }
        // tab-bearing guitar tracks first, then by note count
        tracks.sort { ($0.hasTab ? 1 : 0, $0.noteCount) > ($1.hasTab ? 1 : 0, $1.noteCount) }
        return ImportedPiece(title: title, artist: artist, tracks: tracks)
    }

    static func importPart(_ part: XNode, name: String) -> ImportedTrack? {
        var divisions = 1
        var time = [4, 4]
        var fifths = 0, minor = false
        var tuning: [Int: Int] = [:]     // staff line (1 = lowest) → midi
        var octaveChange: [String: Int] = [:]   // staff → clef-octave-change (guitar is written an octave above sounding: -1)
        var measuresByVoice: [String: [[MXNote]]] = [:]   // "staff:voice" → per measure notes
        var lengths: [Int] = []
        var times: [[Int]?] = []
        var tempoMap: [TempoMark] = []
        var firstTempo: Double? = nil
        var measureStart = 0
        var tabVoices = Set<String>()
        var lastEventKey: [String: (m: Int, idx: Int)] = [:]
        var cursorBeforeChord: [String: Int] = [:]

        let measures = part.all("measure")
        for (mi, measure) in measures.enumerated() {
            var cursor = 0           // position inside the measure, in divisions
            var tsHere: [Int]? = mi == 0 ? time : nil
            for el in measure.children {
                switch el.name {
                case "attributes":
                    if let d = el.int("divisions") { divisions = max(1, d) }
                    if let t = el.first("time"), let b = t.int("beats"), let bt = t.int("beat-type") { time = [b, bt]; tsHere = time }
                    if let k = el.first("key") { fifths = k.int("fifths") ?? fifths; minor = (k.str("mode") ?? "") == "minor" }
                    for c in el.all("clef") {
                        let staff = c.attrs["number"] ?? "1"
                        octaveChange[staff] = c.int("clef-octave-change") ?? 0
                        if (c.str("sign") ?? "") == "TAB" { octaveChange[staff] = octaveChange[staff] ?? 0 }
                    }
                    for sd in el.all("staff-details") {
                        for st in sd.all("staff-tuning") {
                            if let line = Int(st.attrs["line"] ?? ""), let step = st.str("tuning-step"), let oct = st.int("tuning-octave") {
                                let sp = Theory.parseNoteOrNil(step) ?? SpelledNote(0, 0)
                                tuning[line] = (oct + 1) * 12 + Theory.LETTER_PC[sp.letter] + (st.int("tuning-alter") ?? 0)
                            }
                        }
                    }
                case "direction", "sound":
                    var bpm: Double? = nil
                    if el.name == "sound" { bpm = Double(el.attrs["tempo"] ?? "") }
                    else {
                        if let s = el.first("sound"), let t = Double(s.attrs["tempo"] ?? "") { bpm = t }
                        else if let m = el.first("direction-type")?.first("metronome"), let pm = m.double("per-minute") {
                            // metronome marks are per beat-unit; convert to quarter notes
                            let unit = m.str("beat-unit") ?? "quarter"
                            let factor: Double = ["whole": 4, "half": 2, "quarter": 1, "eighth": 0.5, "16th": 0.25][unit] ?? 1
                            let dotted = m.first("beat-unit-dot") != nil ? 1.5 : 1.0
                            bpm = pm * factor * dotted
                        }
                    }
                    if let bpm, bpm > 0 {
                        let tick = measureStart + cursor * TPB / divisions
                        tempoMap.append(TempoMark(tick: tick, bpm: bpm))
                        if firstTempo == nil { firstTempo = bpm }
                    }
                case "backup":
                    cursor -= el.int("duration") ?? 0
                case "forward":
                    cursor += el.int("duration") ?? 0
                case "note":
                    if el.first("grace") != nil { continue }   // grace notes are ornaments; skip
                    let durDiv = el.int("duration") ?? 0
                    let isChord = el.first("chord") != nil
                    let staff = el.str("staff") ?? "1"
                    let voice = el.str("voice") ?? "1"
                    let key = staff + ":" + voice
                    let onset = isChord ? (cursorBeforeChord[key] ?? cursor) : cursor
                    if !isChord { cursorBeforeChord[key] = cursor; cursor += durDiv }
                    if el.first("rest") != nil {
                        let ev = ScoreEvent(dur: ticks(durDiv, divisions), rest: true, notes: [])
                        append(&measuresByVoice, key, mi, MXNote(onset: ticks(onset, divisions), ev: ev), measures.count)
                        continue
                    }
                    guard let pitch = el.first("pitch"), let step = pitch.str("step"), let oct = pitch.int("octave") else { continue }
                    let alter = pitch.int("alter") ?? 0
                    let sp = Theory.parseNoteOrNil(step) ?? SpelledNote(0, 0)
                    let spelled = SpelledNote(sp.letter, alter)
                    // written pitch → sounding pitch (treble clef with clef-octave-change -1 is the guitar convention)
                    let midi = (oct + 1) * 12 + Theory.LETTER_PC[sp.letter] + alter + 12 * (octaveChange[staff] ?? octaveChange["1"] ?? 0)
                    let tech = el.first("notations")?.first("technical")
                    var string = tech?.int("string")
                    let fret = tech?.int("fret")
                    var pos: Position? = nil
                    if let s = string, let f = fret {
                        // MusicXML string 1 = highest; if a tuning says otherwise (lines from the bottom) we keep 1 = top
                        if s >= 1 && s <= 6 { pos = Position(string: s, fret: f); tabVoices.insert(key) } else { string = nil }
                    }
                    if pos == nil, let p = position(for: midi) { pos = p }
                    guard let p = pos else { continue }
                    var marks: [String] = []
                    if let n = el.first("notations") {
                        if n.first("slide") != nil || n.first("glissando") != nil { marks.append("/") }
                        if let t = n.first("technical") {
                            if t.first("hammer-on") != nil { marks.append("h") }
                            if t.first("pull-off") != nil { marks.append("p") }
                            if t.first("bend") != nil { marks.append("b") }
                            if t.first("tap") != nil { marks.append("t") }
                            if t.first("harmonic") != nil { marks.append("harm") }
                            if let o = t.first("other-technical"), o.trimmed.lowercased().contains("palm") || o.trimmed == "P.M." { marks.append("PM") }
                        }
                        if let orn = n.first("ornaments"), orn.first("tremolo") != nil { marks.append("trem") }
                        if n.first("articulations")?.first("staccato") != nil { marks.append("stacc") }
                    }
                    if let play = el.first("play"), (play.str("mute") ?? "") == "palm" { marks.append("PM") }
                    var tied = false
                    for t in el.all("tie") where t.attrs["type"] == "stop" { tied = true }
                    if let n = el.first("notations") { for t in n.all("tied") where t.attrs["type"] == "stop" { tied = true } }
                    let note = ScoreNote(string: p.string, fret: p.fret, midi: Theory.midiAt(p.string, p.fret) == midi ? midi : Theory.midiAt(p.string, p.fret), spelled: spelled, tied: tied, marks: marks)
                    let actual = el.first("time-modification")?.int("actual-notes") ?? 0
                    let normal = el.first("time-modification")?.int("normal-notes")
                    if isChord, let last = lastEventKey[key], last.m == mi, var list = measuresByVoice[key]?[mi], last.idx < list.count {
                        list[last.idx].ev.notes.append(note)
                        measuresByVoice[key]![mi] = list
                    } else {
                        let ev = ScoreEvent(dur: ticks(durDiv, divisions), tuplet: actual > 1 ? actual : 0, tupletNormal: normal, notes: [note])
                        append(&measuresByVoice, key, mi, MXNote(onset: ticks(onset, divisions), ev: ev), measures.count)
                        lastEventKey[key] = (mi, (measuresByVoice[key]?[mi].count ?? 1) - 1)
                    }
                default: break
                }
            }
            let len = time[0] * 4 * TPB / max(1, time[1])
            lengths.append(len)
            times.append(tsHere)
            measureStart += len
        }
        guard !measuresByVoice.isEmpty else { return nil }
        // choose the voice: prefer voices with tab data, then the one with most notes
        func count(_ k: String) -> Int { measuresByVoice[k]!.reduce(0) { $0 + $1.filter { !$0.ev.rest }.count } }
        let best = measuresByVoice.keys.sorted { a, b in
            let ta = tabVoices.contains(a) ? 1 : 0, tb = tabVoices.contains(b) ? 1 : 0
            return ta != tb ? ta > tb : count(a) > count(b)
        }.first!
        let noteCount = count(best)
        if noteCount == 0 { return nil }
        let keySig = keySignature(fifths: fifths, minor: minor)
        let seq = sequence(measuresByVoice[best]!, lengths: lengths)
        let tempo = firstTempo ?? 120
        let meta = ScoreMeta(title: "", subtitle: name, keySig: keySig, tempo: Int(tempo.rounded()), source: .imported)
        let score = Exercises.finalizeMeasures(seq, lengths: lengths, times: times, tpb: TPB, meta: meta, tempoMap: tempoMap)
        _ = tuning
        return ImportedTrack(name: name, score: score, noteCount: noteCount, hasTab: tabVoices.contains(best))
    }

    static func ticks(_ divs: Int, _ divisions: Int) -> Int { Int((Double(divs) * Double(TPB) / Double(divisions)).rounded()) }

    static func append(_ dict: inout [String: [[MXNote]]], _ key: String, _ m: Int, _ n: MXNote, _ count: Int) {
        if dict[key] == nil { dict[key] = Array(repeating: [], count: count) }
        dict[key]![m].append(n)
    }

    /// Turns onset-sorted notes of one measure into a gapless sequence (rests fill gaps, overlaps are clipped).
    static func sequence(_ perMeasure: [[MXNote]], lengths: [Int]) -> [[ScoreEvent]] {
        var out: [[ScoreEvent]] = []
        for (m, notes) in perMeasure.enumerated() {
            let len = m < lengths.count ? lengths[m] : 4 * TPB
            var list: [ScoreEvent] = []
            var pos = 0
            for n in notes.sorted(by: { $0.onset < $1.onset }) {
                var ev = n.ev
                if n.onset > pos { list.append(ScoreEvent(dur: n.onset - pos, rest: true, notes: [])); pos = n.onset }
                if n.onset < pos {
                    // overlapping voice material: shorten what came before, or drop a zero-length leftover
                    if let last = list.indices.last, list[last].dur > pos - n.onset { list[last].dur -= pos - n.onset; pos = n.onset }
                    else { continue }
                }
                if ev.dur <= 0 { continue }
                if pos + ev.dur > len { ev.dur = len - pos; ev.tuplet = 0; ev.tupletNormal = 0 }
                if ev.dur <= 0 { continue }
                list.append(ev); pos += ev.dur
            }
            out.append(list)
        }
        return out
    }

    // MARK: - Guitar Pro 7/8 (score.gpif)

    public static func importGPIF(_ data: Data) throws -> ImportedPiece {
        let root = try parseXML(data)
        guard root.name == "GPIF" else { throw ImportError.unsupported("Not a Guitar Pro 7/8 score (root element \(root.name)).") }
        let title = root.first("Score")?.str("Title") ?? ""
        let artist = root.first("Score")?.str("Artist") ?? ""
        // lookup tables by id
        func table(_ container: String, _ item: String) -> [String: XNode] {
            var d: [String: XNode] = [:]
            for n in root.first(container)?.all(item) ?? [] { d[n.attrs["id"] ?? ""] = n }
            return d
        }
        let bars = table("Bars", "Bar"), voices = table("Voices", "Voice"), beats = table("Beats", "Beat")
        let notes = table("Notes", "Note"), rhythms = table("Rhythms", "Rhythm")
        let trackNodes = root.first("Tracks")?.all("Track") ?? []
        let masterBars = root.first("MasterBars")?.all("MasterBar") ?? []
        guard !trackNodes.isEmpty, !masterBars.isEmpty else { throw ImportError.empty }

        // tempo automations (MasterTrack → Automations → Automation Type=Tempo)
        var tempoAuto: [(bar: Int, pos: Double, bpm: Double)] = []
        for a in root.first("MasterTrack")?.first("Automations")?.all("Automation") ?? [] where (a.str("Type") ?? "") == "Tempo" {
            let parts = (a.str("Value") ?? "").split(separator: " ").compactMap { Double($0) }
            guard let v = parts.first, let bar = a.int("Bar") else { continue }
            let unit = parts.count > 1 ? Int(parts[1]) : 2
            let factor: Double = [1: 0.5, 2: 1, 3: 1.5, 4: 2, 5: 3][unit] ?? 1
            tempoAuto.append((bar, a.double("Position") ?? 0, v * factor))
        }

        // time signatures and key per master bar; bar lengths
        var lengths: [Int] = [], times: [[Int]?] = []
        var lastTS = [4, 4]
        var measureStarts: [Int] = []
        var start = 0
        var fifths = 0, minor = false
        for (mi, mb) in masterBars.enumerated() {
            var ts: [Int]? = nil
            if let t = mb.str("Time") { let p = t.split(separator: "/").compactMap { Int($0) }; if p.count == 2 { ts = p } }
            if mi == 0 && ts == nil { ts = [4, 4] }
            if let ts { lastTS = ts }
            times.append(ts)
            let len = lastTS[0] * 4 * TPB / max(1, lastTS[1])
            lengths.append(len)
            measureStarts.append(start)
            start += len
            if mi == 0, let k = mb.first("Key") { fifths = k.int("AccidentalCount") ?? 0; minor = (k.str("Mode") ?? "") == "Minor" }
        }
        // repeats and alternate endings (unrolled so the score runs linearly like the recording)
        var gpHeaders: [GPHeader] = []
        for mb in masterBars {
            var h = GPHeader()
            if let rep = mb.first("Repeat") {
                h.repeatOpen = rep.attrs["start"] == "true"
                if rep.attrs["end"] == "true" { h.repeatTimes = max(2, Int(rep.attrs["count"] ?? "2") ?? 2) }
            }
            if let alt = mb.str("AlternateEndings") {
                for n in alt.split(separator: " ").compactMap({ Int($0) }) where n >= 1 && n <= 8 { h.altEndings |= 1 << (n - 1) }
            }
            gpHeaders.append(h)
        }
        let order = unrollRepeats(gpHeaders)
        var tempoMap: [TempoMark] = tempoAuto.map { TempoMark(tick: ($0.bar < measureStarts.count ? measureStarts[$0.bar] : 0) + Int($0.pos * Double($0.bar < lengths.count ? lengths[$0.bar] : 192)), bpm: $0.bpm) }
        if tempoMap.isEmpty, let t = root.first("MasterTrack")?.first("Automations")?.all("Automation").first?.double("Value") { tempoMap = [TempoMark(tick: 0, bpm: t)] }
        let keySig = keySignature(fifths: fifths, minor: minor)

        // written bar → unrolled positions
        var unrolledStarts: [Int] = []
        var unrolledLengths: [Int] = [], unrolledTimes: [[Int]?] = []
        do {
            var t = 0
            var lastTS: [Int]? = nil
            for src in order {
                unrolledStarts.append(t)
                let ts = times[src] ?? lastTS ?? [4, 4]
                if times[src] != nil { lastTS = times[src] }
                unrolledTimes.append(unrolledTimes.isEmpty || ts != (unrolledTimes.compactMap { $0 }.last ?? [4, 4]) ? ts : nil)
                unrolledLengths.append(lengths[src])
                t += lengths[src]
            }
        }
        var firstOccurrence: [Int: Int] = [:]
        for (k, src) in order.enumerated() where firstOccurrence[src] == nil { firstOccurrence[src] = k }
        tempoMap = tempoMap.map { m in
            let written = measureStarts.lastIndex(where: { $0 <= m.tick }) ?? 0
            let offset = m.tick - measureStarts[written]
            let k = firstOccurrence[written] ?? 0
            return TempoMark(tick: unrolledStarts[k] + offset, bpm: m.bpm)
        }

        var tracks: [ImportedTrack] = []
        for (ti, track) in trackNodes.enumerated() {
            let name = track.str("Name") ?? "Track \(ti + 1)"
            // tuning: Pitches low→high (gpif string 0 = lowest). Default standard.
            var tuning = [40, 45, 50, 55, 59, 64]
            if let prop = findProperty(track, "Tuning"), let pitches = prop.str("Pitches") {
                let p = pitches.split(separator: " ").compactMap { Int($0) }
                if p.count >= 4 { tuning = p }
            }
            let capo = findProperty(track, "CapoFret")?.int("Fret") ?? 0
            if tuning.count != 6 { continue }   // bass / 7-string tracks are skipped (the app is a 6-string guitar app)
            let standard = tuning == [40, 45, 50, 55, 59, 64]
            var perMeasure: [[ScoreEvent]] = []
            var noteCount = 0
            for src in order {
                let mb = masterBars[src]
                let barIds = (mb.str("Bars") ?? "").split(separator: " ").map(String.init)
                var list: [ScoreEvent] = []
                if ti < barIds.count, let bar = bars[barIds[ti]] {
                    let voiceIds = (bar.str("Voices") ?? "").split(separator: " ").map(String.init)
                    // first non-empty voice
                    if let vid = voiceIds.first(where: { $0 != "-1" && voices[$0] != nil }), let voice = voices[vid] {
                        for bid in (voice.str("Beats") ?? "").split(separator: " ").map(String.init) {
                            guard let beat = beats[bid] else { continue }
                            let rhythm = rhythms[beat.first("Rhythm")?.attrs["ref"] ?? ""]
                            var dur = gpifTicks(rhythm?.str("NoteValue") ?? "Quarter")
                            var actual = 0, normal = 0
                            if let dot = rhythm?.first("AugmentationDot"), let c = Int(dot.attrs["count"] ?? "1") { dur = c >= 2 ? dur * 7 / 4 : dur * 3 / 2 }
                            if let tup = rhythm?.first("PrimaryTuplet"), let n = Int(tup.attrs["num"] ?? ""), let d = Int(tup.attrs["den"] ?? ""), n > 0 {
                                dur = dur * d / n; actual = n; normal = d
                            }
                            let noteIds = (beat.str("Notes") ?? "").split(separator: " ").map(String.init)
                            if noteIds.isEmpty || beat.first("Rest") != nil {
                                list.append(ScoreEvent(dur: dur, tuplet: actual, tupletNormal: normal, rest: true, notes: []))
                                continue
                            }
                            let palmBeat = beat.all("Properties").flatMap { $0.all("Property") }.contains { $0.attrs["name"] == "PalmMuted" }
                            var evNotes: [ScoreNote] = []
                            for nid in noteIds {
                                guard let n = notes[nid] else { continue }
                                let props = n.first("Properties")?.all("Property") ?? []
                                func prop(_ name: String) -> XNode? { props.first { $0.attrs["name"] == name } }
                                guard let gs = prop("String")?.int("String"), let fret = prop("Fret")?.int("Fret"), gs >= 0, gs < 6 else { continue }
                                let string = 6 - gs
                                // Guitar Pro stores the sounding MIDI number and the concert-pitch spelling; fall back to tuning + fret
                                let midi = prop("Midi")?.int("Number") ?? (tuning[gs] + fret + capo)
                                var marks: [String] = []
                                if palmBeat || prop("PalmMuted") != nil { marks.append("PM") }
                                if prop("HopoOrigin") != nil { marks.append("h") }
                                if prop("Slide") != nil { marks.append("/") }
                                if prop("Bended") != nil { marks.append("b") }
                                if prop("Muted") != nil { marks.append("x") }
                                if prop("Tapped") != nil { marks.append("t") }
                                if prop("HarmonicType") != nil { marks.append("harm") }
                                if n.first("Vibrato") != nil { marks.append("~") }
                                let tied = n.first("Tie")?.attrs["destination"] == "true"
                                // the app's fretboard is standard tuning: keep string/fret (what the hand does) and spell the sounding pitch
                                var spelled = spell(midi: midi, keySig: keySig)
                                if let cp = prop("ConcertPitch")?.first("Pitch"), let step = cp.str("Step"), let sp = Theory.parseNoteOrNil(step) {
                                    let acc = cp.str("Accidental") ?? ""
                                    let alter = ["#": 1, "x": 2, "b": -1, "bb": -2, "": 0][acc] ?? 0
                                    if Theory.notePc(SpelledNote(sp.letter, alter)) == Theory.mod(midi, 12) { spelled = SpelledNote(sp.letter, alter) }
                                }
                                evNotes.append(ScoreNote(string: string, fret: fret, midi: standard ? Theory.midiAt(string, fret) : midi, spelled: spelled, tied: tied, marks: marks))
                            }
                            if evNotes.isEmpty { list.append(ScoreEvent(dur: dur, tuplet: actual, tupletNormal: normal, rest: true, notes: [])) }
                            else { noteCount += evNotes.count; list.append(ScoreEvent(dur: dur, tuplet: actual, tupletNormal: normal, notes: evNotes)) }
                        }
                    }
                }
                perMeasure.append(list)
            }
            if noteCount == 0 { continue }
            let tempo = tempoMap.first?.bpm ?? 120
            let meta = ScoreMeta(title: "", subtitle: name + (standard ? "" : " (non-standard tuning)"), keySig: keySig, tempo: Int(tempo.rounded()), source: .imported)
            var score = Exercises.finalizeMeasures(perMeasure, lengths: unrolledLengths, times: unrolledTimes, tpb: TPB, meta: meta, tempoMap: tempoMap)
            score.measureLabels = order.map { $0 + 1 }
            tracks.append(ImportedTrack(name: name, score: score, noteCount: noteCount, hasTab: true))
        }
        if tracks.isEmpty { throw ImportError.empty }
        return ImportedPiece(title: title, artist: artist, tracks: tracks)
    }

    /// `<Property name="X">` anywhere below `node` (Guitar Pro keeps track/staff settings in nested Properties blocks).
    static func findProperty(_ node: XNode, _ name: String) -> XNode? {
        if node.name == "Property", node.attrs["name"] == name { return node }
        for c in node.children { if let f = findProperty(c, name) { return f } }
        return nil
    }

    static func gpifTicks(_ value: String) -> Int {
        switch value {
        case "Whole": return 4 * TPB
        case "Half": return 2 * TPB
        case "Quarter": return TPB
        case "Eighth": return TPB / 2
        case "16th": return TPB / 4
        case "32nd": return TPB / 8
        case "64th": return TPB / 16
        case "128th": return max(1, TPB / 32)
        default: return TPB
        }
    }
}
