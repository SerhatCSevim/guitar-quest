// Chords & Harmony: chord library, chord building, chord families, jam-along strumming, theory games.
// Port of web/js/views/harmony.js (this file: shell, chord detail, library, build, families).
import SwiftUI
import AppKit
import MusicCore

enum HarmonyTab: String, CaseIterable {
    case library, build, families, jam, games
    var label: String {
        switch self {
        case .library: return "Chord library"
        case .build: return "Build a chord"
        case .families: return "Chord families"
        case .jam: return "Jam along"
        case .games: return "Theory games"
        }
    }
}

enum LibraryMode: String { case open, barre, power }

/// Mirrors the JS `state` object: every sub-tab keeps its choices while the screen is open.
struct HarmonyState: Equatable {
    var tab: HarmonyTab = .library
    var lib: LibraryMode = .open
    var barreRoot = "G"
    var sel: Voicing? = nil
    var buildRoot = "C"
    var buildType: ChordType = .maj
    var famFamily: Family = .major
    var famKey = "G"
    var famSevenths = false
    var famDetail: Voicing? = nil
    var famDetailTitle: String? = nil
    var jamProg = "I-IV-V-I"
    var jamFamily: Family = .major
    var jamKey = "G"
    var jamStrum = "folk"
    var jamBpm = 72
    var jamMetronome = true
    var jamSound = true
    var gameId = "steps"
    var gameLevel: TheoryLevel = .easy
}

struct HarmonyView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services
    @State private var state: HarmonyState

    init() {
        var s = HarmonyState()
        // debug aid for snapshots: GQ_HARMONY_TAB=build|families|jam|games
        if let t = ProcessInfo.processInfo.environment["GQ_HARMONY_TAB"], let tab = HarmonyTab(rawValue: t) { s.tab = tab }
        if let g = ProcessInfo.processInfo.environment["GQ_HARMONY_GAME"], !g.isEmpty { s.gameId = g }
        _state = State(initialValue: s)
    }

    var body: some View {
        let _ = model.settingsVersion // re-render when a setting changes (web: onSettings → renderTab)
        let _ = HarmonyDebugSnapshot.run(store: store, model: model, services: services)
        VStack(alignment: .leading, spacing: 0) {
            ViewHead(title: "Chords & Harmony",
                     lead: "Harmony = notes played together. See how chords are built from scales, which chords belong together, and strum along.")
            Segmented(options: HarmonyTab.allCases.map { SegOption($0, $0.label) }, selection: $state.tab, big: true)
                .padding(.bottom, 16)
            switch state.tab {
            case .library: HarmonyLibraryView(state: $state)
            case .build: HarmonyBuildView(state: $state)
            case .families: HarmonyFamiliesView(state: $state)
            case .jam: HarmonyJamView(state: $state)
            case .games: HarmonyGamesView(state: $state)
            }
        }
        .onAppear { consumePending() }
        .onChange(of: model.pendingHarmony) { _, _ in consumePending() }
    }

    private func consumePending() {
        guard let p = model.pendingHarmony else { return }
        model.pendingHarmony = nil
        if let tab = HarmonyTab(rawValue: p.tab) { state.tab = tab }
        if let prog = p.progId { state.jamProg = prog }
        if let fam = p.family { state.jamFamily = fam }
        if let key = p.key { state.jamKey = key }
    }
}

/// Debug aid: `GQ_HARMONY_SNAP=/path/out.png` (together with the app's GQ_SNAPSHOT_DIR run) renders this screen
/// standalone, at its full content height, and quits. The root ScrollView does not render inside ImageRenderer.
@MainActor enum HarmonyDebugSnapshot {
    static var done = false
    static func run(store: ProgressStore, model: AppModel, services: Services?) {
        guard !done, let path = ProcessInfo.processInfo.environment["GQ_HARMONY_SNAP"], !path.isEmpty, let services else { return }
        done = true
        let content = HarmonyView()
            .environment(store).environment(model).environment(\.services, services)
            .padding(22).frame(width: 1280).background(Theme.bg)
        let r = ImageRenderer(content: content)
        r.scale = 1
        r.proposedSize = ProposedViewSize(width: 1280, height: nil)
        if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("harmony snapshot: \(path) \(cg.width)x\(cg.height)")
        } else { print("harmony snapshot FAILED") }
        exit(0)
    }
}

// MARK: - shared helpers

@MainActor enum HarmonyAudio {
    static func strum(_ v: Voicing, _ dir: StrumDirection = .down, _ services: Services?) {
        guard let audio = services?.audio else { return }
        let notes = Chords.voicingNotes(v).map { $0.midi }
        audio.strum(notes, when: audio.now + 0.02, dir: dir, spread: dir == .up ? 0.012 : 0.022, velocity: 0.7, duration: 2.2)
    }
    static func arpeggio(_ v: Voicing, _ services: Services?) {
        guard let audio = services?.audio else { return }
        let t = audio.now + 0.05
        for (i, n) in Chords.voicingNotes(v).enumerated() { audio.pluck(n.midi, when: t + Double(i) * 0.28, duration: 1.6) }
    }
    /// Spelling of a sounding pitch class inside a chord (chord tone if it is one, else sharp spelling).
    static func spelledFor(_ v: Voicing, _ pc: Int) -> SpelledNote {
        if let t = Theory.chordTones(v.root, v.type).first(where: { $0.pc == pc }) { return SpelledNote(t.letter, t.alter) }
        return Theory.spellPc(pc)
    }
    static func sym(_ root: SpelledNote, _ type: ChordType, _ settings: Settings) -> String {
        Theory.chordSymbol(root, type, settings.namingShort)
    }
}

/// Two columns with weights (CSS grid 1.25fr 1fr).
struct WeightedHStack: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1000
        let widths = colWidths(width, subviews.count)
        var h: CGFloat = 0
        for (i, s) in subviews.enumerated() { h = max(h, s.sizeThatFits(ProposedViewSize(width: widths[i], height: nil)).height) }
        return CGSize(width: width, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = colWidths(bounds.width, subviews.count)
        var x = bounds.minX
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: widths[i], height: nil))
            x += widths[i] + spacing
        }
    }
    private func colWidths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        guard n > 0 else { return [] }
        let avail = total - spacing * CGFloat(max(0, n - 1))
        let sum = (0..<n).reduce(CGFloat(0)) { $0 + weights[$1 % weights.count] }
        return (0..<n).map { avail * (weights[$0 % weights.count] / sum) }
    }
}

/// A chord diagram inside a white bordered button (`.diag-btn`): hear and see the chord.
struct DiagramButton: View {
    let voicing: Voicing
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            ChordDiagramView(voicing: voicing, title: title, width: 112)
                .padding(4)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(hover ? Theme.accent : Theme.line, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Hear and see \(title)")
    }
}

/// Chord detail card: big diagram, tones, formula, play buttons, explanation, staff + tab of the exact voicing.
struct ChordDetailCard: View {
    let voicing: Voicing
    var extraTitle: String? = nil
    @Environment(ProgressStore.self) private var store
    @Environment(\.services) private var services

    var body: some View {
        let v = voicing
        let s = store.settings
        let tones = Theory.chordTones(v.root, v.type)
        let name = HarmonyAudio.sym(v.root, v.type, s)
        let typeName = Theory.chordType(v.type).name.lowercased()
        Card {
            HStack(alignment: .top, spacing: 18) {
                ChordDiagramView(voicing: v, title: name, width: 170)
                VStack(alignment: .leading, spacing: 6) {
                    (Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                        + Text(" · " + typeName + (extraTitle.map { " · " + $0 } ?? "")).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.muted))
                    HStack(spacing: 10) {
                        ForEach(tones.indices, id: \.self) { i in
                            let t = tones[i]
                            VStack(spacing: 2) {
                                NoteBadge(spelled: SpelledNote(t.letter, t.alter), settings: s)
                                Text(t.degree == 1 ? "root" : t.label).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    SmallText("Formula: " + Theory.chordFormula(v.type).joined(separator: " - ") + " (steps of the " + Theory.noteLabel(v.root, s.namingShort) + " major scale)")
                    FlowLayout(hSpacing: 8, vSpacing: 8) {
                        GQButton("Strum", icon: "guitars", style: .primary) { HarmonyAudio.strum(v, .down, services) }
                        GQButton("Up-strum") { HarmonyAudio.strum(v, .up, services) }
                        GQButton("One string at a time") { HarmonyAudio.arpeggio(v, services) }
                    }
                    .padding(.vertical, 4)
                    SmallText(v.kind == .open ? "Open chord: uses open strings."
                              : "\(v.kind.rawValue): the root is on the \(v.kind == .eShape ? "6th" : "5th") string at fret \(v.rootFret ?? 0). Slide the whole shape to play other chords of this type.", muted: true)
                    SmallText(v.fingers != nil
                              ? "Numbers = fingers (1 index, 2 middle, 3 ring, 4 little). A bar across means one finger presses several strings. The red dot is the root."
                              : "The red dot is the root.", muted: true)
                }
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
            }
            // staff + tab of exactly what you play
            let notes = Chords.voicingNotes(v).map { n in
                ScoreNote(string: n.string, fret: n.fret, midi: n.midi, spelled: HarmonyAudio.spelledFor(v, Theory.mod(n.midi, 12)))
            }
            ScoreView(score: Exercises.singleEvent(notes: notes),
                      options: NotationOptions(showStaff: true, showTab: true, showNames: true, colors: s.colors, naming: s.namingShort, minWidth: 260))
                .padding(.top, 8)
        }
    }
}

// MARK: - chord library

struct HarmonyLibraryView: View {
    @Binding var state: HarmonyState
    @Environment(ProgressStore.self) private var store
    @Environment(\.services) private var services

    private var groups: [(String, [Voicing])] {
        var out: [(String, [Voicing])] = []
        switch state.lib {
        case .open:
            let order: [(ChordType, String)] = [(.maj, "Major chords - happy, bright"), (.min, "Minor chords - sad, dark"), (.dom7, "Seventh chords - want to move on"),
                                                (.min7, "Minor seventh"), (.maj7, "Major seventh - dreamy"), (.sus2, "Suspended 2nd"), (.sus4, "Suspended 4th")]
            for (type, title) in order {
                let vs = Chords.OPEN.filter { $0.type == type }
                if !vs.isEmpty { out.append((title, vs)) }
            }
            // the most common beginner minor chords that have no open shape in the table get their barre version
            if out.count > 1, let bm = Chords.bestVoicing(Theory.parseNote("B"), .min) { out[1].1.append(bm) }
        case .barre:
            let r = Theory.parseNote(state.barreRoot)
            for type in [ChordType.maj, .min, .dom7, .min7, .sus4, .maj7] {
                var vs: [Voicing] = []
                if Chords.E_SHAPES[type] != nil, let v = Chords.voicingsFor(r, type).first(where: { $0.kind == .eShape }) { vs.append(v) }
                if Chords.A_SHAPES[type] != nil, let v = Chords.voicingsFor(r, type).first(where: { $0.kind == .aShape }) { vs.append(v) }
                out.append((Theory.chordType(type).name + " - 6th-string root and 5th-string root", vs))
            }
        case .power:
            out.append(("Open power chords", Chords.OPEN.filter { $0.type == .power }))
            out.append(("Moveable power chords (any root)", ["F", "G", "A", "B", "C", "D"].compactMap { k in
                Chords.voicingsFor(Theory.parseNote(k), .power).first { $0.kind != .open }
            }))
        }
        return out
    }

    var body: some View {
        let s = store.settings
        let gs = groups
        let selected = state.sel ?? gs.first?.1.first
        VStack(alignment: .leading, spacing: 16) {
            Card {
                Toolbar {
                    Field("Show") {
                        Segmented(options: [SegOption(LibraryMode.open, "Open chords"), SegOption(.barre, "Barre chords"), SegOption(.power, "Power chords")],
                                  selection: $state.lib, onChange: { _ in state.sel = nil })
                    }
                    if state.lib == .barre {
                        Field("Root note") {
                            KeyChips(keys: Theory.MAJOR_KEYS, value: state.barreRoot, naming: s.namingShort) { k in state.barreRoot = k; state.sel = nil }
                        }
                    }
                }
            }
            WeightedHStack(weights: [1.25, 1]) {
                VStack(alignment: .leading, spacing: 0) {
                    if state.lib == .barre {
                        TipText("Barre chords are moveable: the same finger shape works for every root. Find the root note on the 6th or 5th string, put the shape there - done!")
                            .padding(.bottom, 4)
                    }
                    if state.lib == .power {
                        TipText("A power chord is only the root and the 5th (1 - 5). It is neither major nor minor, which is why rock guitarists love it.")
                            .padding(.bottom, 4)
                    }
                    ForEach(gs.indices, id: \.self) { gi in
                        let (title, vs) = gs[gi]
                        Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink).padding(.top, 14).padding(.bottom, 8)
                        FlowLayout(hSpacing: 8, vSpacing: 8) {
                            ForEach(vs.indices, id: \.self) { vi in
                                let v = vs[vi]
                                DiagramButton(voicing: v, title: HarmonyAudio.sym(v.root, v.type, s)) {
                                    HarmonyAudio.strum(v, .down, services)
                                    state.sel = v
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading) {
                    if let v = selected { ChordDetailCard(voicing: v) }
                }
            }
        }
    }
}

// MARK: - build a chord

struct HarmonyBuildView: View {
    @Binding var state: HarmonyState
    @Environment(ProgressStore.self) private var store
    @Environment(\.services) private var services

    static let buildTypes: [ChordType] = [.maj, .min, .dim, .aug, .sus2, .sus4, .dom7, .maj7, .min7]
    static let why: [ChordType: String] = [
        .maj: "Major chords use steps 1, 3 and 5 of the major scale.",
        .min: "Minor chords lower the 3rd by one fret: 1, ♭3, 5. That one note makes the chord sound sad.",
        .dim: "Diminished lowers both the 3rd and the 5th: 1, ♭3, ♭5. Tense and spooky.",
        .aug: "Augmented raises the 5th: 1, 3, ♯5. It sounds like a question.",
        .sus2: "Suspended chords have no 3rd. sus2 uses the 2nd instead: open and floating.",
        .sus4: "sus4 swaps the 3rd for the 4th. It likes to \"resolve\" back to the major chord.",
        .dom7: "A 7 chord adds the ♭7 to a major chord. It wants to move to the next chord.",
        .maj7: "maj7 adds the 7th (one fret below the root). Soft and dreamy.",
        .min7: "m7 is a minor chord plus the ♭7. Smooth and mellow.",
    ]

    var body: some View {
        let s = store.settings
        let r = Theory.parseNote(state.buildRoot)
        let scale = Theory.scaleNotes(r, .major)
        let tones = Theory.chordTones(r, state.buildType)
        let typeDef = Theory.chordType(state.buildType)
        VStack(alignment: .leading, spacing: 16) {
            Card {
                Toolbar {
                    Field("Root") { KeyChips(keys: Theory.MAJOR_KEYS, value: state.buildRoot, naming: s.namingShort) { state.buildRoot = $0 } }
                    Field("Chord type") {
                        Segmented(options: Self.buildTypes.map { SegOption($0, Theory.chordType($0).name.replacingOccurrences(of: "Suspended ", with: "sus ").replacingOccurrences(of: "Dominant ", with: "")) },
                                  selection: $state.buildType)
                    }
                }
            }
            Card {
                H3("Step 1: write out the " + Theory.noteLabel(r, s.namingShort) + " major scale")
                FlowLayout(hSpacing: 8, vSpacing: 8) {
                    ForEach(scale.indices, id: \.self) { i in
                        let n = scale[i]
                        let deg = i + 1
                        let tone = tones.first { $0.degree == deg || (deg == 2 && $0.degree == 9) }
                        BuildCell(number: deg, note: SpelledNote(n.letter, n.alter), tone: tone, settings: s)
                    }
                }
                .padding(.bottom, 14)
                H3("Step 2: take the steps of the formula")
                HStack(spacing: 6) {
                    Text(typeDef.name + " = " + Theory.chordFormula(state.buildType).joined(separator: " - ")).font(.system(size: 15, weight: .bold))
                    Text("  →  ").font(.system(size: 15))
                    ForEach(tones.indices, id: \.self) { i in NoteBadge(spelled: SpelledNote(tones[i].letter, tones[i].alter), settings: s) }
                }
                .padding(.bottom, 6)
                TipText(Self.why[state.buildType] ?? "")
            }
            HStack(alignment: .top, spacing: 16) {
                if let v = Chords.bestVoicing(r, state.buildType) { ChordDetailCard(voicing: v) }
                Card {
                    H3("Step 3: chord tones all over the neck")
                    SmallText("Any of these notes belongs to " + HarmonyAudio.sym(r, state.buildType, s) + ". R = root.", muted: true).padding(.bottom, 6)
                    FretboardView(maxFret: 12, compact: true, marks: fretMarks(tones, s)) { st, f in
                        services?.audio.pluck(Theory.midiAt(st, f), duration: 1)
                    }
                }
            }
        }
    }

    private func fretMarks(_ tones: [ScaleNote], _ s: Settings) -> [FretMark] {
        var marks: [FretMark] = []
        for st in 1...6 { for f in 0...12 {
            let pc = Theory.mod(Theory.midiAt(st, f), 12)
            if let t = tones.first(where: { $0.pc == pc }) {
                marks.append(FretMark.note(st, f, settings: s, spelled: SpelledNote(t.letter, t.alter), label: t.degree == 1 ? "R" : t.label, kind: t.degree == 1 ? .root : .note))
            }
        } }
        return marks
    }
}

struct BuildCell: View {
    let number: Int
    let note: SpelledNote
    let tone: ScaleNote?
    let settings: Settings
    var body: some View {
        let on = tone != nil
        let altered = tone.map { $0.letter != note.letter || $0.alter != note.alter } ?? false
        VStack(spacing: 4) {
            Text(String(number)).font(.system(size: 15, weight: .black)).foregroundStyle(Theme.muted)
            NoteBadge(spelled: note, settings: settings)
            if altered, let t = tone {
                Text(t.alter < note.alter ? "LOWER 1 FRET" : "RAISE 1 FRET").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accentDark)
                NoteBadge(spelled: SpelledNote(t.letter, t.alter), settings: settings)
                Text(t.label).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(8)
        .frame(minWidth: 54)
        .background(on ? Color(hex: 0xFFF3EC) : Theme.soft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.accent : .clear, lineWidth: 2))
        .opacity(on ? 1 : 0.45)
    }
}

// MARK: - chord families

struct HarmonyFamiliesView: View {
    @Binding var state: HarmonyState
    @Environment(ProgressStore.self) private var store
    @Environment(\.services) private var services

    var body: some View {
        let s = store.settings
        let keys = GameData.familyKeys(state.famFamily)
        let key = keys.contains(state.famKey) ? state.famKey : keys[0]
        let tonic = Theory.parseNote(key)
        let chords = Theory.harmonize(tonic, state.famFamily, state.famSevenths)
        let keyName = Theory.noteLabel(tonic, s.namingShort) + (state.famFamily == .minor ? " minor" : " major")
        let intro = state.famFamily == .major
            ? "Build a chord on every note of the " + Theory.noteLabel(tonic, s.namingShort) + " major scale (always skipping one note: 1-3-5, 2-4-6, 3-5-7 …). The pattern is the same in every major key: I, IV and V are major, ii, iii and vi are minor, vii° is diminished."
            : "In a minor key the pattern moves: i, iv and v are minor, III, VI and VII are major, ii° is diminished. Many songs borrow a major V chord to make the ending stronger."
        let detail: (Voicing, String)? = {
            if let v = state.famDetail, let t = state.famDetailTitle { return (v, t) }
            if let first = chords.first, let v = Chords.bestVoicing(first.root, first.type) { return (v, first.roman) }
            return nil
        }()
        let progs = GameData.PROGS.filter { $0.family == state.famFamily }
        VStack(alignment: .leading, spacing: 16) {
            Card {
                Toolbar {
                    Field("Key type") {
                        Segmented(options: [SegOption(Family.major, "Major keys"), SegOption(.minor, "Minor keys")], selection: $state.famFamily,
                                  onChange: { _ in resetDetail() })
                    }
                    Field("Key") {
                        KeyChips(keys: keys, value: key, suffix: state.famFamily == .minor ? "m" : "", naming: s.namingShort) { state.famKey = $0; resetDetail() }
                    }
                    Field("Chords") {
                        Segmented(options: [SegOption(false, "3-note chords"), SegOption(true, "7th chords")], selection: $state.famSevenths, onChange: { _ in resetDetail() })
                    }
                }
            }
            TipText(intro).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 980, alignment: .leading)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), alignment: .leading, spacing: 10) {
                ForEach(chords.indices, id: \.self) { i in
                    let ch = chords[i]
                    if let v = Chords.bestVoicing(ch.root, ch.type) {
                        FamilyCard(chord: ch, voicing: v, settings: s) {
                            HarmonyAudio.strum(v, .down, services)
                            state.famDetail = v
                            state.famDetailTitle = ch.roman + " in " + keyName
                        }
                    }
                }
            }
            Card {
                H3("Famous chord progressions in this key")
                ForEach(progs) { p in
                    ProgressionLine(prog: p, key: key, settings: s) {
                        state.jamProg = p.id; state.jamFamily = p.family; state.jamKey = key
                        state.tab = .jam
                    }
                }
            }
            if let (v, title) = detail { ChordDetailCard(voicing: v, extraTitle: title) }
        }
    }

    private func resetDetail() { state.famDetail = nil; state.famDetailTitle = nil }
}

struct ProgressionLine: View {
    let prog: Progression
    let key: String
    let settings: Settings
    let onJam: () -> Void
    var body: some View {
        let names = GameData.progChords(prog, key).map { HarmonyAudio.sym($0.root, $0.type, settings) }
        var uniq: [String] = []
        for (i, n) in names.enumerated() where i == 0 || n != names[i - 1] { uniq.append(n) }
        return HStack(spacing: 14) {
            Text(prog.label).font(.custom("Georgia", size: 15).weight(.bold)).frame(minWidth: 200, alignment: .leading)
            Text(uniq.joined(separator: " → ")).font(.system(size: 15, weight: .heavy)).frame(maxWidth: .infinity, alignment: .leading)
            GQButton("Jam →", small: true, action: onJam)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.soft).frame(height: 1) }
    }
}

struct FamilyCard: View {
    let chord: HarmonizedChord
    let voicing: Voicing
    let settings: Settings
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let quality: String = [.maj, .dom7, .maj7].contains(chord.type) ? "major" : ([.min, .min7].contains(chord.type) ? "minor" : "dim")
        let romanColor: Color = quality == "major" ? Theme.accent : (quality == "minor" ? Theme.teal : Color(hex: 0x7A4FB5))
        Button(action: action) {
            VStack(spacing: 2) {
                Text(chord.roman).font(.custom("Georgia", size: 24).weight(.bold)).foregroundStyle(romanColor)
                Text(HarmonyAudio.sym(chord.root, chord.type, settings)).font(.system(size: 18, weight: .black)).foregroundStyle(Theme.ink)
                Text((quality == "dim" ? "diminished" : quality).uppercased()).font(.system(size: 11.5, weight: .bold)).kerning(0.5).foregroundStyle(Theme.muted)
                ChordDiagramView(voicing: voicing, width: 92).padding(.top, 4)
            }
            .padding(.vertical, 10).padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(hover ? Theme.line : .clear, lineWidth: 2))
            .shadow(color: Theme.shadow, radius: 9, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
