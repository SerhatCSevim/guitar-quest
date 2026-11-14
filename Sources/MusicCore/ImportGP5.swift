// Guitar Pro 3 / 4 / 5 binary files (.gp3 .gp4 .gp5) — the format most tab sites still hand out.
// Layout follows the public reverse-engineered description used by TuxGuitar / PyGuitarPro.
import Foundation

struct ByteReader {
    let data: Data
    var pos = 0
    init(_ d: Data) { data = d }

    var remaining: Int { data.count - pos }
    mutating func skip(_ n: Int) throws { guard n >= 0, pos + n <= data.count else { throw ImportError.unsupported("Unexpected end of file.") }; pos += n }
    mutating func byte() throws -> Int { guard pos < data.count else { throw ImportError.unsupported("Unexpected end of file.") }; defer { pos += 1 }; return Int(data[data.startIndex + pos]) }
    mutating func sbyte() throws -> Int { let b = try byte(); return b > 127 ? b - 256 : b }
    mutating func bool() throws -> Bool { try byte() != 0 }
    mutating func short() throws -> Int { let a = try byte(), b = try byte(); let v = a | (b << 8); return v > 32767 ? v - 65536 : v }
    mutating func int() throws -> Int {
        let a = try byte(), b = try byte(), c = try byte(), d = try byte()
        let v = UInt32(a) | (UInt32(b) << 8) | (UInt32(c) << 16) | (UInt32(d) << 24)
        return Int(Int32(bitPattern: v))
    }
    mutating func double() throws -> Double {
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(try byte()) << (8 * UInt64(i)) }
        return Double(bitPattern: bits)
    }
    mutating func bytes(_ n: Int) throws -> Data {
        guard n >= 0, pos + n <= data.count else { throw ImportError.unsupported("Unexpected end of file.") }
        defer { pos += n }
        return data.subdata(in: (data.startIndex + pos)..<(data.startIndex + pos + n))
    }
    static func text(_ d: Data) -> String {
        String(data: d, encoding: .utf8) ?? String(data: d, encoding: .windowsCP1252) ?? String(data: d, encoding: .isoLatin1) ?? ""
    }
    /// 1 length byte, then `size` bytes of which `length` are the string (consumes 1 + size bytes).
    mutating func byteSizeString(_ size: Int) throws -> String {
        let len = try byte()
        let d = try bytes(size)
        return ByteReader.text(d.prefix(min(len, d.count)))
    }
    /// int length, then the string.
    mutating func intSizeString() throws -> String { let n = try int(); return ByteReader.text(try bytes(max(0, n))) }
    /// int (length + 1), byte length, then `int - 1` bytes of which `length` are the string.
    mutating func intByteSizeString() throws -> String {
        let n = try int() - 1
        let len = try byte()
        let d = try bytes(max(0, n))
        return ByteReader.text(d.prefix(min(max(0, len), d.count)))
    }
}

extension ScoreImporter {
    struct GPHeader {
        var numerator = 4, denominator = 4
        var repeatOpen = false
        var repeatCloseRaw = -1      // as stored in the file (−1 = no repeat close here)
        var repeatTimes = 0          // total times the repeated section is played (0 = no close here)
        var altEndings = 0           // bitmask of alternate endings this bar belongs to
        var keyRoot: Int? = nil
        var keyMinor: Bool? = nil
        var marker: String? = nil
        var tripletFeel = 0
    }
    struct GPTrack {
        var name = ""
        var strings: [Int] = []      // tuning per string, index 0 = string 1 (highest)
        var capo = 0
        var isPercussion = false
    }
    struct GPNote { var string: Int; var fret: Int; var tied: Bool; var dead: Bool; var marks: [String] }
    struct GPBeat { var dur: Int; var tuplet: Int; var rest: Bool; var empty: Bool; var notes: [GPNote]; var tempo: Int? }

    public static func importGP345(_ data: Data) throws -> ImportedPiece {
        var r = ByteReader(data)
        let version = try r.byteSizeString(30)
        guard version.hasPrefix("FICHIER GUITAR PRO v") else { throw ImportError.unsupported("Not a Guitar Pro 3/4/5 file (header \"\(version.prefix(24))\").") }
        let vText = String(version.dropFirst("FICHIER GUITAR PRO v".count))
        let vParts = vText.split(separator: ".").compactMap { Int($0.filter { $0.isNumber }) }
        let major = vParts.first ?? 0, minor = vParts.count > 1 ? vParts[1] : 0
        guard (3...5).contains(major) else { throw ImportError.unsupported("Guitar Pro \(vText) files are not supported (3, 4 and 5 are).") }
        let v5 = major == 5, v51 = v5 && minor > 0

        // ---- song info
        let title = try r.intByteSizeString()
        _ = try r.intByteSizeString()                  // subtitle
        let artist = try r.intByteSizeString()
        _ = try r.intByteSizeString()                  // album
        _ = try r.intByteSizeString()                  // words / author
        if v5 { _ = try r.intByteSizeString() }        // music
        _ = try r.intByteSizeString()                  // copyright
        _ = try r.intByteSizeString()                  // tab author
        _ = try r.intByteSizeString()                  // instructions
        let notices = try r.int()
        for _ in 0..<max(0, notices) { _ = try r.intByteSizeString() }
        if !v5 { _ = try r.bool() }                    // triplet feel (gp3/4)
        if major >= 4 {                                // lyrics
            _ = try r.int()
            for _ in 0..<5 { _ = try r.int(); _ = try r.intSizeString() }
        }
        if v5 {
            if v51 { _ = try r.int(); _ = try r.int(); try r.skip(11) }   // RSE master effect: volume, ???, 11-band EQ
            // page setup
            for _ in 0..<7 { _ = try r.int() }
            _ = try r.short()
            for _ in 0..<10 { _ = try r.intByteSizeString() }
            _ = try r.intByteSizeString()              // tempo name
        }
        var tempo = try r.int()
        if v51 { _ = try r.bool() }                    // hide tempo
        var songKey = 0                                // fifths (−7 … 7)
        if v5 { songKey = try r.sbyte(); _ = try r.int() }            // key (signed byte) + octave (int)
        else if major == 4 { songKey = try r.int(); _ = try r.sbyte() } // key (int) + octave (byte)
        else { songKey = try r.int() }                                // gp3: key (int)
        if songKey < -7 || songKey > 7 { songKey = 0 }
        // midi channels: 64 × (int instrument + 6 bytes + 2 blank)
        try r.skip(64 * 12)
        if v5 { try r.skip(19 * 2); _ = try r.int() }  // directions, master reverb
        let measureCount = try r.int()
        let trackCount = try r.int()
        let debug = ProcessInfo.processInfo.environment["GQ_GP_DEBUG"] != nil
        if debug { print("gp\(major).\(minor) \"\(title)\" tempo \(tempo) key \(songKey) measures \(measureCount) tracks \(trackCount) @\(r.pos)") }
        guard measureCount > 0, measureCount < 10000, trackCount > 0, trackCount < 64 else { throw ImportError.unsupported("Implausible track/measure count; the file may be damaged.") }

        // ---- measure headers
        var headers: [GPHeader] = []
        var ts = (4, 4)
        for i in 0..<measureCount {
            if v5 && i > 0 { try r.skip(1) }
            let flags = try r.byte()
            var h = GPHeader()
            if flags & 0x01 != 0 { ts.0 = try r.sbyte() }
            if flags & 0x02 != 0 { ts.1 = try r.sbyte() }
            h.numerator = ts.0; h.denominator = ts.1
            h.repeatOpen = flags & 0x04 != 0
            if flags & 0x08 != 0 { h.repeatCloseRaw = try r.sbyte() }
            if v5 {
                if flags & 0x20 != 0 { h.marker = try r.intByteSizeString(); try r.skip(4) }
                if flags & 0x40 != 0 { h.keyRoot = try r.sbyte(); h.keyMinor = try r.sbyte() != 0 }
                if flags & 0x10 != 0 { h.altEndings = try r.byte() }
            } else {
                if flags & 0x10 != 0 { h.altEndings = try r.byte() }
                if flags & 0x20 != 0 { h.marker = try r.intByteSizeString(); try r.skip(4) }
                if flags & 0x40 != 0 { h.keyRoot = try r.sbyte(); h.keyMinor = try r.sbyte() != 0 }
            }
            if v5 {
                if flags & 0x03 != 0 { try r.skip(4) }  // beam groups
                if flags & 0x10 == 0 { try r.skip(1) }
                h.tripletFeel = try r.byte()
            }
            headers.append(h)
        }
        // Repeat count → total number of times the section is played. GP5 stores the count + 1 compared to GP3/4
        // (PyGuitarPro subtracts 1 for GP5); GP3/4 store "number of repetitions", i.e. play count − 1.
        for i in headers.indices where headers[i].repeatCloseRaw >= 0 {
            let normalized = headers[i].repeatCloseRaw - (v5 ? 1 : 0)
            headers[i].repeatTimes = max(2, normalized + 1)
        }
        if debug { for (i, h) in headers.enumerated() where h.repeatOpen || h.repeatCloseRaw >= 0 || h.altEndings != 0 { print("  header \(i + 1): open \(h.repeatOpen) closeRaw \(h.repeatCloseRaw) times \(h.repeatTimes) alt \(h.altEndings)") } }

        // ---- tracks
        var tracks: [GPTrack] = []
        for i in 0..<trackCount {
            if v5 && (i == 0 || !v51) { try r.skip(1) }
            let flags1 = try r.byte()
            var t = GPTrack()
            t.isPercussion = flags1 & 0x01 != 0
            t.name = try r.byteSizeString(40)
            let stringCount = try r.int()
            var tuning: [Int] = []
            for k in 0..<7 { let v = try r.int(); if k < stringCount { tuning.append(v) } }
            t.strings = tuning
            _ = try r.int()                  // port
            _ = try r.int(); _ = try r.int() // channel, effect channel
            _ = try r.int()                  // fret count
            t.capo = try r.int()
            try r.skip(4)                    // colour
            if v5 {
                _ = try r.short()            // flags2
                _ = try r.byte()             // auto accentuation
                _ = try r.byte()             // bank
                // track RSE: humanize, 3 ints, 12 bytes, instrument (3 ints + short/skip or int)
                _ = try r.byte()
                try r.skip(12)
                try r.skip(12)
                _ = try r.int(); _ = try r.int(); _ = try r.int()
                if v51 { _ = try r.int() } else { _ = try r.short(); try r.skip(1) }
                if v51 { try r.skip(4); _ = try r.intByteSizeString(); _ = try r.intByteSizeString() }
            }
            tracks.append(t)
            if debug { print("  track \(i): \"\(t.name)\" strings \(t.strings) capo \(t.capo) @\(r.pos)") }
        }
        if v5 { try r.skip(v51 ? 1 : 2) }

        // ---- measures (per measure, per track)
        var beatsPerTrackMeasure: [[[GPBeat]]] = Array(repeating: [], count: trackCount)   // [track][measure] → beats of the chosen voice
        var tempoChanges: [(measure: Int, beatIndex: Int, bpm: Int)] = []
        for mi in 0..<measureCount {
            for ti in 0..<trackCount {
                let track = tracks[ti]
                var voicesBeats: [[GPBeat]] = []
                let voiceCount = v5 ? 2 : 1
                for _ in 0..<voiceCount {
                    let n = try r.int()
                    if debug && mi < 3 { print("  bar \(mi + 1) track \(ti): \(n) beats @\(r.pos)") }
                    guard n >= 0, n < 4096 else { throw ImportError.unsupported("Damaged beat list in bar \(mi + 1) (track \(ti + 1), offset \(r.pos)).") }
                    var beats: [GPBeat] = []
                    for bi in 0..<n {
                        do { beats.append(try readBeat(&r, major: major, v51: v51, track: track)) }
                        catch { throw ImportError.unsupported("\(error) (bar \(mi + 1), track \(ti + 1), beat \(bi + 1), offset \(r.pos))") }
                    }
                    voicesBeats.append(beats)
                }
                if v5 && r.remaining > 0 { _ = try r.byte() }   // line break (absent at the very end of some files)
                var chosen = voicesBeats[0]
                if chosen.allSatisfy({ $0.empty }), voicesBeats.count > 1 { chosen = voicesBeats[1] }
                beatsPerTrackMeasure[ti].append(chosen)
                if ti == 0 { for (bi, b) in chosen.enumerated() { if let t = b.tempo { tempoChanges.append((mi, bi, t)) } } }
            }
        }

        // ---- unroll repeats into a linear sequence of (original measure index) with alternate endings
        let order = unrollRepeats(headers)

        // key signature from the first header that carries one
        var fifths = songKey, isMinor = false
        if let h = headers.first(where: { $0.keyRoot != nil }) { fifths = h.keyRoot ?? 0; isMinor = h.keyMinor ?? false }
        if fifths < -7 || fifths > 7 { fifths = 0 }
        let keySig = keySignature(fifths: fifths, minor: isMinor)
        if tempo <= 0 { tempo = 120 }

        var out: [ImportedTrack] = []
        for (ti, track) in tracks.enumerated() where !track.isPercussion && track.strings.count == 6 {
            let standard = track.strings == [64, 59, 55, 50, 45, 40]
            var measures: [[ScoreEvent]] = []
            var lengths: [Int] = [], times: [[Int]?] = [], labels: [Int] = []
            var tempoMap: [TempoMark] = [TempoMark(tick: 0, bpm: Double(tempo))]
            var lastTS: [Int]? = nil
            var tick = 0
            var noteCount = 0
            var lastFret: [Int: Int] = [:]   // string → last fret (for tied notes)
            for src in order {
                let h = headers[src]
                let tsHere = [h.numerator, h.denominator]
                times.append(tsHere != lastTS ? tsHere : nil)
                lastTS = tsHere
                let len = h.numerator * 4 * TPB / max(1, h.denominator)
                lengths.append(len)
                labels.append(src + 1)
                var list: [ScoreEvent] = []
                var used = 0
                for (bi, b) in beatsPerTrackMeasure[ti][src].enumerated() {
                    if b.empty { continue }
                    if let t = b.tempo, ti == 0 || true { tempoMap.append(TempoMark(tick: tick + used, bpm: Double(t))) ; _ = bi }
                    var notes: [ScoreNote] = []
                    for n in b.notes {
                        guard n.string >= 1 && n.string <= 6 else { continue }
                        var fret = n.fret
                        if n.tied { fret = lastFret[n.string] ?? n.fret }
                        lastFret[n.string] = fret
                        let midi = track.strings[n.string - 1] + fret + track.capo
                        var marks = n.marks
                        if n.dead { marks.insert("x", at: 0) }
                        notes.append(ScoreNote(string: n.string, fret: fret, midi: standard ? Theory.midiAt(n.string, fret) : midi,
                                               spelled: spell(midi: midi, keySig: keySig), tied: n.tied, marks: marks))
                    }
                    if !b.rest { noteCount += notes.count }
                    list.append(ScoreEvent(dur: b.dur, tuplet: b.tuplet, rest: b.rest || notes.isEmpty, notes: b.rest ? [] : notes))
                    used += b.dur
                }
                measures.append(list)
                tick += len
            }
            if noteCount == 0 { continue }
            let meta = ScoreMeta(title: "", subtitle: track.name + (standard ? "" : " (non-standard tuning)"), keySig: keySig, tempo: tempo, source: .imported)
            var score = Exercises.finalizeMeasures(measures, lengths: lengths, times: times, tpb: TPB, meta: meta, tempoMap: tempoMap)
            score.measureLabels = labels
            out.append(ImportedTrack(name: track.name, score: score, noteCount: noteCount, hasTab: true))
        }
        if out.isEmpty { throw ImportError.empty }
        return ImportedPiece(title: title, artist: artist, tracks: out)
    }

    /// Plays the measures in order, honouring |: :| repeat counts and alternate endings (1., 2. …).
    static func unrollRepeats(_ headers: [GPHeader]) -> [Int] {
        var order: [Int] = []
        var i = 0
        var repeatStart = 0
        var pass = 1
        var guardCount = 0
        while i < headers.count && guardCount < 100_000 {
            guardCount += 1
            let h = headers[i]
            if h.repeatOpen && i != repeatStart { repeatStart = i; pass = 1 }
            if h.altEndings != 0 && (h.altEndings & (1 << (pass - 1))) == 0 {
                // this ending is for another pass: skip to the next bar that is not an ending, or the one for this pass
                i += 1
                continue
            }
            order.append(i)
            if h.repeatTimes > 0 {
                if pass < h.repeatTimes {
                    pass += 1
                    i = repeatStart
                    continue
                } else {
                    pass = 1
                    repeatStart = i + 1
                }
            }
            i += 1
        }
        if order.isEmpty { order = Array(headers.indices) }
        return order
    }

    static func readBeat(_ r: inout ByteReader, major: Int, v51: Bool, track: GPTrack) throws -> GPBeat {
        let v5 = major == 5
        let flags = try r.byte()
        var status = 1
        if flags & 0x40 != 0 { status = try r.byte() }        // 0 empty, 1 normal, 2 rest
        let value = try r.sbyte()                               // -2 whole … 4 64th
        var dur = TPB * 4
        if value >= -2 { for _ in 0..<(value + 2) { dur /= 2 } }
        if flags & 0x01 != 0 { dur = dur * 3 / 2 }
        var tuplet = 0
        if flags & 0x20 != 0 {
            tuplet = try r.int()
            let normal = ScoreEvent.defaultNormal(for: tuplet)
            if tuplet > 1 && normal > 0 { dur = dur * normal / tuplet }
        }
        if flags & 0x02 != 0 { try readChord(&r, major: major) }
        if flags & 0x04 != 0 { _ = try r.intByteSizeString() }   // beat text
        var beatMarks: [String] = []
        if flags & 0x08 != 0 { beatMarks = try readBeatEffects(&r, major: major) }
        var tempo: Int? = nil
        if flags & 0x10 != 0 { tempo = try readMixTableChange(&r, major: major, v51: v51) }
        // notes
        let stringFlags = try r.byte()
        var notes: [GPNote] = []
        for s in 1...7 where stringFlags & (1 << (7 - s)) != 0 {
            var n = try readNote(&r, major: major, string: s)
            n.marks.append(contentsOf: beatMarks)
            if s <= track.strings.count { notes.append(n) }
        }
        if v5 {
            let flags2 = try r.short()
            if flags2 & 0x0800 != 0 { _ = try r.byte() }
        }
        return GPBeat(dur: dur, tuplet: tuplet, rest: status == 2, empty: status == 0, notes: notes, tempo: tempo)
    }

    static func readChord(_ r: inout ByteReader, major: Int) throws {
        if major == 5 {
            try r.skip(17); _ = try r.byteSizeString(21); try r.skip(4); _ = try r.int()
            for _ in 0..<7 { _ = try r.int() }
            try r.skip(32)
            return
        }
        let newFormat = try r.bool()
        if newFormat {
            if major == 4 {
                try r.skip(1 + 3 + 3 + 4 + 4 + 1)      // sharp, blanks, root/type/extension, bass, tonality, add
                _ = try r.byteSizeString(22)
                try r.skip(3)                          // fifth, ninth, eleventh
                _ = try r.int()                        // first fret
                for _ in 0..<7 { _ = try r.int() }
                try r.skip(1 + 5 + 5 + 5 + 7 + 1 + 7 + 1) // barres, omissions, blank, fingering, show
            } else {
                // gp3 "new" chord: sharp, 3 blank, root/type/extension/bass/tonality ints, add, name, fifth/ninth/eleventh ints,
                // first fret, 6 frets, barre count + 2×3 ints, 7 omissions, 1 blank
                try r.skip(25); _ = try r.byteSizeString(22); try r.skip(12); _ = try r.int()
                for _ in 0..<6 { _ = try r.int() }
                try r.skip(4 + 8 + 8 + 8 + 7 + 1)
            }
        } else {
            _ = try r.intByteSizeString()
            let first = try r.int()
            if first != 0 { for _ in 0..<6 { _ = try r.int() } }
        }
    }

    static func readBeatEffects(_ r: inout ByteReader, major: Int) throws -> [String] {
        var marks: [String] = []
        let flags1 = try r.sbyte()
        let flags2 = major >= 4 ? try r.sbyte() : 0
        if major == 3 {
            if flags1 & 0x01 != 0 { marks.append("~") }
            if flags1 & 0x10 != 0 { marks.append("fade") }
            if flags1 & 0x20 != 0 { _ = try r.byte(); _ = try r.int() }   // slap/pop/tap, then tremolo-bar value
            if flags1 & 0x40 != 0 { _ = try r.sbyte(); _ = try r.sbyte() }
            return marks
        }
        if flags1 & 0x02 != 0 { marks.append("~") }
        if flags1 & 0x10 != 0 { marks.append("fade") }
        if flags1 & 0x20 != 0 { _ = try r.sbyte() }           // slap / pop / tap
        if flags2 & 0x04 != 0 { try readBend(&r) }            // tremolo bar
        if flags1 & 0x40 != 0 { _ = try r.sbyte(); _ = try r.sbyte() }   // strokes
        if flags2 & 0x02 != 0 { _ = try r.sbyte() }           // pick stroke
        return marks
    }

    static func readBend(_ r: inout ByteReader) throws {
        _ = try r.sbyte(); _ = try r.int()
        let points = try r.int()
        guard points >= 0, points < 1000 else { throw ImportError.unsupported("Damaged bend data.") }
        for _ in 0..<points { _ = try r.int(); _ = try r.int(); _ = try r.bool() }
    }

    static func readMixTableChange(_ r: inout ByteReader, major: Int, v51: Bool) throws -> Int? {
        _ = try r.sbyte()                                  // instrument
        if major == 5 {
            _ = try r.int(); _ = try r.int(); _ = try r.int()
            if v51 { _ = try r.int() } else { _ = try r.short(); try r.skip(1); try r.skip(1) }
        }
        let volume = try r.sbyte(), balance = try r.sbyte(), chorus = try r.sbyte()
        let reverb = try r.sbyte(), phaser = try r.sbyte(), tremolo = try r.sbyte()
        if major == 5 { _ = try r.intByteSizeString() }    // tempo name
        let tempo = try r.int()
        for v in [volume, balance, chorus, reverb, phaser, tremolo] where v >= 0 { _ = try r.sbyte() }
        if tempo >= 0 { _ = try r.sbyte(); if v51 { _ = try r.bool() } }
        if major >= 4 { _ = try r.sbyte() }                // apply-to-all-tracks flags
        if major == 5 {
            _ = try r.sbyte()                              // wah
            if v51 { _ = try r.intByteSizeString(); _ = try r.intByteSizeString() }
        }
        return tempo > 0 ? tempo : nil
    }

    static func readNote(_ r: inout ByteReader, major: Int, string: Int) throws -> GPNote {
        let flags = try r.byte()
        var tied = false, dead = false
        var fret = 0
        var marks: [String] = []
        if flags & 0x20 != 0 {
            let type = try r.byte()
            tied = type == 2; dead = type == 3
        }
        if major < 5 && flags & 0x01 != 0 { _ = try r.sbyte(); _ = try r.sbyte() }   // note duration + tuplet (gp3/4)
        if flags & 0x10 != 0 { _ = try r.sbyte() }                                   // velocity
        if flags & 0x20 != 0 { fret = try r.sbyte() }
        if flags & 0x80 != 0 { _ = try r.sbyte(); _ = try r.sbyte() }                // fingering
        if major == 5 {
            if flags & 0x01 != 0 { _ = try r.double() }                              // duration percent
            _ = try r.byte()                                                         // flags2 (swap accidentals)
        }
        if flags & 0x08 != 0 {
            if major == 3 {
                let f = try r.byte()
                if f & 0x01 != 0 { try readBend(&r); marks.append("b") }
                if f & 0x02 != 0 { marks.append("h") }
                if f & 0x04 != 0 { marks.append("/") }
                if f & 0x08 != 0 { marks.append("let ring") }
                if f & 0x10 != 0 { try r.skip(4) }                                   // grace note
            } else {
                let f1 = try r.sbyte(), f2 = try r.sbyte()
                if f1 & 0x01 != 0 { try readBend(&r); marks.append("b") }
                if f1 & 0x02 != 0 { marks.append("h") }
                if f1 & 0x08 != 0 { marks.append("let ring") }
                if f1 & 0x10 != 0 { try r.skip(major == 5 ? 5 : 4) }                 // grace note
                if f2 & 0x01 != 0 { marks.append("stacc") }
                if f2 & 0x02 != 0 { marks.append("PM") }
                if f2 & 0x04 != 0 { _ = try r.sbyte(); marks.append("trem") }
                if f2 & 0x08 != 0 { _ = try r.sbyte(); marks.append("/") }
                if f2 & 0x10 != 0 {
                    let h = try r.sbyte()
                    if major == 5 {
                        if h == 2 { try r.skip(3) } else if h == 3 { try r.skip(1) }
                    }
                    marks.append("harm")
                }
                if f2 & 0x20 != 0 { _ = try r.sbyte(); _ = try r.sbyte(); marks.append("tr") }
                if f2 & 0x40 != 0 { marks.append("~") }
            }
        }
        return GPNote(string: string, fret: max(0, fret), tied: tied, dead: dead, marks: marks)
    }
}
