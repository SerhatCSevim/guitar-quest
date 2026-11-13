// Practice Studio: Guitar-Pro-style player with staff + tab, tempo, metronome, loop and speed trainer.
// Port of web/js/views/studio.js.
import SwiftUI
import AppKit
import MusicCore

struct StudioState {
    var source: ScoreSource = .scale
    var tonic = "A"
    var scaleId: ScaleID = .minorPent
    var shapeId = "box1"
    var pattern: MusicCore.Pattern = .updown
    var rhythm: Rhythm = .e
    var range: ExerciseRange = .full
    var songId = "mary"
    var bpm = 80
    var loop = true
    var metronome = true
    var countIn = true
    var sound = true
    var trainer = false
    var trainerStep = 5
    var trainerTarget = 120
    var view = "both"
    var names = true
}

struct StudioView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services

    @State private var st = StudioState()
    @State private var transport: Transport?
    @State private var score: Score?
    @State private var buildError: String?
    @State private var position = -1
    @State private var countdown = 0
    @State private var playing = false
    @State private var seeking = false
    @State private var consumedParams = false
    @State private var debugActive: Int? = nil

    init() {
        // initial score so the very first render (and snapshots) already shows the default exercise
        _score = State(initialValue: try? Exercises.buildScaleScore(ScaleScoreOptions(tonic: "A", scaleId: .minorPent, shapeId: "box1", pattern: .updown, rhythm: .e, range: .full, tempo: 80)))
        // debug aid for snapshots: GQ_STUDIO_DEBUG=<event index> highlights that event as if playing
        if let d = ProcessInfo.processInfo.environment["GQ_STUDIO_DEBUG"], let i = Int(d) { _debugActive = State(initialValue: i) }
        if ProcessInfo.processInfo.environment["GQ_STUDIO_DEBUG_SONG"] != nil {
            var st0 = StudioState(); st0.source = .song; st0.songId = "ode"
            _st = State(initialValue: st0)
            _score = State(initialValue: try? Exercises.buildSongScore(Songs.byId("ode")!))
        }
        StandaloneSnapshot.renderIfRequested("studio") { AnyView(StudioView()) }
    }

    private var settings: Settings { store.settings }

    var body: some View {
        let _ = model.settingsVersion
        let s = applyPendingParams()
        VStack(alignment: .leading, spacing: 0) {
            ViewHead(title: "Practice Studio",
                     lead: "Pick an exercise, press play and follow the moving cursor. Start slow, then let the speed trainer push the tempo up.")
            sourceCard(s)
            transportBar
            titleRow
            scoreCard
            Card(padding: Theme.fretboardCardPadding) {
                FretboardView(maxFret: fretboardMax, compact: true, marks: fretMarks) { string, fret in
                    services?.audio.pluck(Theory.midiAt(string, fret), duration: 1)
                }
            }
        }
        .onAppear { setup() }
        .onDisappear { teardown() }
        .onChange(of: model.settingsVersion) { _, _ in build() }
    }

    // MARK: - setup

    /// Consumes `model.pendingStudio` once (on first body) so the initial render already shows the requested scale.
    private func applyPendingParams() -> StudioState {
        if !consumedParams, let p = model.pendingStudio {
            var next = st
            next.source = .scale
            next.tonic = p.tonic
            next.scaleId = p.scaleId
            next.shapeId = p.shapeId
            next.range = Theory.scale(p.scaleId).pent ? .full : .root
            DispatchQueue.main.async {
                st = next
                consumedParams = true
                model.pendingStudio = nil
                build()
            }
            return next
        }
        return st
    }

    private func setup() {
        guard let services else { return }
        if transport == nil {
            let t = Transport(audio: services.audio)
            t.onPosition = { idx, cd, _, seek in
                position = idx; countdown = cd; seeking = seek
            }
            t.onState = { p in
                playing = p
                if p { services.clock.start("studio") } else { services.clock.stop("studio"); countdown = 0 }
            }
            t.onLoop = { bpm in
                st.bpm = bpm
                model.toast("Speed trainer: \(bpm) BPM")
            }
            transport = t
        }
        model.keyHandler = { press in
            if press.key == .space { togglePlay(); return .handled }
            if press.key == .escape { transport?.stop(); return .handled }
            return .ignored
        }
        if !consumedParams && model.pendingStudio == nil { consumedParams = true }
        build()
    }

    private func teardown() {
        transport?.stop()
        services?.clock.stop("studio")
        model.keyHandler = nil
    }

    // MARK: - score building

    private func fixState() {
        let sc = Theory.scale(st.scaleId)
        let keys = Theory.keyNames(sc.family)
        if !keys.contains(st.tonic) { st.tonic = keys[0] }
        let shapes = Theory.shapeOptions(st.scaleId).filter { $0.id != "neck" }
        if !shapes.contains(where: { $0.id == st.shapeId }) { st.shapeId = shapes[0].id }
    }

    private func build() {
        transport?.stop()
        fixState()
        do {
            if st.source == .scale {
                score = try Exercises.buildScaleScore(ScaleScoreOptions(tonic: st.tonic, scaleId: st.scaleId, shapeId: st.shapeId,
                                                                        pattern: st.pattern, rhythm: st.rhythm, range: st.range, tempo: st.bpm))
            } else {
                let song = Songs.byId(st.songId) ?? Songs.all[0]
                score = try Exercises.buildSongScore(song)
                st.bpm = min(st.bpm, song.tempo)
            }
            buildError = nil
        } catch {
            score = nil
            buildError = "Could not build this exercise: \(error)"
            return
        }
        if let score, let t = transport {
            let tl = Exercises.timeline(score).map { TransportItem(i: $0.i, beat: $0.beat, beats: $0.beats, rest: $0.rest, midis: $0.midis) }
            t.load(tl, totalBeats: Double(score.totalTicks) / Double(Exercises.TPB), beatsPerBar: 4)
            applyFlags()
        }
    }

    private func applyFlags() {
        guard let t = transport else { return }
        t.loop = st.loop
        t.metronome = st.metronome
        t.countIn = st.countIn
        t.sound = st.sound
        t.bpm = st.bpm
        t.trainer = TrainerSettings(on: st.trainer && st.loop, step: st.trainerStep, target: st.trainerTarget)
    }

    private func togglePlay() {
        guard score != nil, let t = transport else { return }
        if t.playing { t.pause() } else { applyFlags(); t.play() }
    }

    private func bump(_ d: Int) {
        st.bpm = max(30, min(220, st.bpm + d))
        transport?.setTempo(st.bpm)
    }

    // MARK: - derived

    private var activeIndex: Int? { debugActive ?? (position >= 0 ? position : nil) }

    private var nextIndex: Int? {
        guard let a = activeIndex, let evs = score?.events else { return nil }
        var k = a + 1
        while k < evs.count { if !evs[k].rest { return k }; k += 1 }
        return nil
    }

    private var fretboardMax: Int {
        let maxF = score?.events.compactMap { $0.notes.first?.fret }.max() ?? 0
        return max(15, maxF + 1)
    }

    private var fretMarks: [FretMark] {
        guard let score else { return [] }
        var marks: [FretMark] = []
        var seen = Set<String>()
        for ev in score.events {
            for n in ev.notes {
                let k = "\(n.string):\(n.fret)"
                if seen.contains(k) { continue }
                seen.insert(k)
                var m = FretMark.note(n.string, n.fret, settings: settings, spelled: n.spelled, kind: .ghost)
                m.opacity = 0.28
                marks.append(m)
            }
        }
        if let a = activeIndex, a < score.events.count {
            if let nx = nextIndex {
                for n in score.events[nx].notes {
                    var m = FretMark.note(n.string, n.fret, settings: settings, spelled: n.spelled, label: "", kind: .ring)
                    m.opacity = 0.95
                    marks.append(m)
                }
            }
            for n in score.events[a].notes {
                var m = FretMark.note(n.string, n.fret, settings: settings, spelled: n.spelled, kind: .root)
                m.pop = !seeking
                marks.append(m)
            }
        }
        return marks
    }

    private var notationOptions: NotationOptions {
        NotationOptions(showStaff: st.view != "tab", showTab: st.view != "staff", showNames: st.names,
                        colors: settings.colors, naming: settings.namingShort, minWidth: 520)
    }

    // MARK: - source card

    private func sourceCard(_ s: StudioState) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Field("Practise") {
                    Segmented(options: [SegOption(ScoreSource.scale, "Scale exercise"), SegOption(.song, "Song")],
                              selection: Binding(get: { st.source }, set: { st.source = $0; build() }))
                }
                if s.source == .scale {
                    let sc = Theory.scale(s.scaleId)
                    let keys = Theory.keyNames(sc.family)
                    let shapes = Theory.shapeOptions(s.scaleId).filter { $0.id != "neck" }
                    FlowLayout(hSpacing: 18, vSpacing: 12, alignment: .bottom) {
                        Field("Scale") {
                            selectMenu(ScaleID.allCases.map { ($0, Theory.scale($0).name) }, s.scaleId) { v in
                                let pc = Theory.notePc(Theory.parseNote(st.tonic))
                                st.scaleId = v
                                let ks = Theory.keyNames(Theory.scale(v).family)
                                st.tonic = ks.first { Theory.notePc(Theory.parseNote($0)) == pc } ?? ks[0]
                                st.range = Theory.scale(v).pent ? .full : .root
                                build()
                            }
                        }
                        Field("Key") {
                            selectMenu(keys.map { ($0, Theory.noteLabel(Theory.parseNote($0), settings.namingShort) + (sc.family == .minor ? " minor" : " major")) },
                                       keys.contains(s.tonic) ? s.tonic : keys[0]) { st.tonic = $0; build() }
                        }
                        Field("Shape") {
                            selectMenu(shapes.map { ($0.id, $0.name) }, shapes.contains { $0.id == s.shapeId } ? s.shapeId : shapes[0].id) { st.shapeId = $0; build() }
                        }
                        Field("Pattern") {
                            selectMenu(MusicCore.Pattern.allCases.map { ($0, $0.name) }, s.pattern) { st.pattern = $0; build() }
                        }
                        Field("Rhythm") {
                            selectMenu(Rhythm.allCases.map { ($0, $0.name) }, s.rhythm) { st.rhythm = $0; build() }
                        }
                        Field("Range") {
                            Segmented(options: [SegOption(ExerciseRange.root, "Root to root"), SegOption(.full, "Whole shape")],
                                      selection: Binding(get: { st.range }, set: { st.range = $0; build() }))
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(Songs.all) { song in
                            let on = song.id == s.songId
                            Button {
                                st.songId = song.id
                                build()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(song.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                                    SmallText(song.origin, muted: true)
                                    Tag(text: song.strings)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 11).padding(.horizontal, 13)
                                .background(on ? Color(hex: 0xFFFBF8) : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.accent : Theme.line, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    /// A select-like menu button (`.sel`).
    private func selectMenu<T: Hashable>(_ options: [(T, String)], _ value: T, _ onChange: @escaping (T) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.0) { o in
                Button(o.1) { onChange(o.0) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == value }?.1 ?? "").font(.system(size: 14)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(minWidth: 150)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - transport bar

    private var transportBar: some View {
        Card {
            FlowLayout(hSpacing: 18, vSpacing: 10, alignment: .center) {
                HStack(spacing: 6) {
                    TransportButton(icon: playing ? "pause.fill" : "play.fill", on: playing, play: true, help: "Play / pause (space)") { togglePlay() }
                    TransportButton(icon: "stop.fill", help: "Stop (Esc)") { transport?.stop() }
                    toggle(\.loop, "Loop", icon: "repeat", help: "Repeat from the start")
                }
                .fixedSize()
                HStack(spacing: 6) {
                    SmallText("Tempo", muted: true)
                    TransportButton(label: "−5", small: true, help: "Slower") { bump(-5) }
                    Slider(value: Binding(get: { Double(st.bpm) }, set: { st.bpm = Int($0.rounded()); transport?.setTempo(st.bpm) }), in: 30...220, step: 1)
                        .tint(Theme.accent).frame(width: 150)
                    TransportButton(label: "+5", small: true, help: "Faster") { bump(5) }
                    Text("\(st.bpm) BPM").font(.system(size: 15, weight: .black)).frame(minWidth: 74, alignment: .leading)
                }
                .fixedSize()
                HStack(spacing: 6) {
                    toggle(\.metronome, "Click", icon: "metronome", help: "Metronome")
                    toggle(\.countIn, "Count-in", icon: nil, help: "One bar of clicks before starting")
                    toggle(\.sound, "Guitar", icon: "speaker.wave.2.fill", help: "Hear the guitar part (turn off to play it yourself)")
                }
                .fixedSize()
                trainerBox
                HStack(spacing: 6) {
                    Segmented(options: [SegOption("both", "Staff + Tab"), SegOption("tab", "Tab"), SegOption("staff", "Staff")],
                              selection: Binding(get: { st.view }, set: { st.view = $0 }))
                    TransportButton(label: "Note names", on: st.names, isToggle: true, help: "Show note names under the tab") { st.names.toggle() }
                }
                .fixedSize()
            }
        }
        .padding(.bottom, 16)
    }

    private func toggle(_ key: WritableKeyPath<StudioState, Bool>, _ label: String, icon: String?, help: String) -> some View {
        TransportButton(icon: icon, label: label, on: st[keyPath: key], isToggle: true, help: help) {
            st[keyPath: key].toggle()
            applyFlags()
        }
    }

    private var trainerBox: some View {
        HStack(spacing: 6) {
            TransportButton(label: "Speed trainer", on: st.trainer, isToggle: true, help: "Raise the tempo after every loop") {
                st.trainer.toggle(); applyFlags()
            }
            Group {
                SmallText("each loop")
                Picker("", selection: Binding(get: { st.trainerStep }, set: { st.trainerStep = $0; applyFlags() })) {
                    ForEach([2, 5, 10], id: \.self) { Text("+\($0)").tag($0) }
                }
                .labelsHidden().frame(width: 70)
                SmallText("up to")
                TextField("", value: Binding(get: { st.trainerTarget }, set: { st.trainerTarget = max(40, min(220, $0)); applyFlags() }), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 64)
                SmallText("BPM")
            }
            .opacity(st.trainer ? 1 : 0.45)
        }
        .fixedSize()
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(Theme.soft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - score

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let score {
                Text(score.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(score.subtitle).foregroundStyle(Theme.muted)
            } else if let buildError {
                Text(buildError).foregroundStyle(Theme.bad)
            }
        }
        .padding(.horizontal, 2).padding(.top, 4).padding(.bottom, 10)
    }

    private var scoreCard: some View {
        Card(padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) {
            ZStack {
                if debugActive != nil {
                    // snapshot mode: ImageRenderer renders ScrollViews empty, so show the score inline
                    ScoreView(score: score, options: notationOptions, active: activeIndex, next: nextIndex)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            ScoreView(score: score, options: notationOptions, active: activeIndex, next: nextIndex,
                                      onSeek: { i in transport?.seek(i) }, scrollProxy: proxy)
                                .padding(.trailing, 4)
                        }
                        .frame(minHeight: 220, maxHeight: 460)
                    }
                }
                if countdown > 0 && playing {
                    Text(String(countdown))
                        .font(.system(size: 110, weight: .black))
                        .foregroundStyle(Theme.accent.opacity(0.85))
                        .shadow(color: .white.opacity(0.9), radius: 10, y: 4)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.bottom, 16)
    }
}


/// Debug aid: `GQ_STANDALONE_SNAP=<dir>` renders a screen on its own (outside RootView's ScrollView, which
/// ImageRenderer does not lay out) with a throw-away store, writes <dir>/<name>_standalone.png and quits.
@MainActor
enum StandaloneSnapshot {
    nonisolated(unsafe) static var running = false
    static func renderIfRequested(_ name: String, _ make: () -> AnyView) {
        guard !running, let dir = ProcessInfo.processInfo.environment["GQ_STANDALONE_SNAP"], !dir.isEmpty,
              ProcessInfo.processInfo.environment["GQ_SNAPSHOT_ONLY"] == name else { return }
        running = true
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gq-standalone-\(UUID().uuidString).json")
        let store = ProgressStore(fileURL: tmp)
        let model = AppModel()
        let services = Services(store: store, audio: AudioEngine(volume: 0), clock: PracticeClock(store: store), model: model)
        // no ScrollView: ImageRenderer renders scroll views empty
        let content = VStack { make().padding(22); Spacer(minLength: 0) }
            .frame(width: 1280, height: 1700, alignment: .top)
            .environment(store).environment(model).environment(\.services, services)
            .background(Theme.bg)
        let r = ImageRenderer(content: content)
        r.scale = 1
        r.proposedSize = ProposedViewSize(width: 1280, height: 1700)
        if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)_standalone.png"))
            print("standalone snapshot: \(name)_standalone.png")
        } else { print("standalone snapshot FAILED") }
        exit(0)
    }
}
