// Scales: major, minor, pentatonic and blues shapes on the neck. Port of js/views/scales.js.
import SwiftUI
import MusicCore

struct ScalesView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services

    private enum Labels: String { case names, degrees, none }

    @State private var scaleId: ScaleID = .minorPent
    @State private var key = "A"
    @State private var shape = "box1"
    @State private var labels: Labels = .names
    @State private var transport: Transport? = nil
    @State private var playOrder: [Int] = []
    @State private var activeIdx: Int? = nil
    @State private var playing = false
    @State private var shapeMenuOpen = false

    private static let scaleTabs: [SegOption<ScaleID>] = [
        SegOption(.major, "Major"), SegOption(.minor, "Minor"),
        SegOption(.majorPent, "Major pentatonic"), SegOption(.minorPent, "Minor pentatonic"), SegOption(.blues, "Blues"),
    ]

    private var settings: Settings { store.settings }
    private var nm: Naming { settings.namingShort }
    private var sc: ScaleDef { Theory.scale(scaleId) }
    private var tonic: SpelledNote { Theory.parseNote(key) }
    private var currentShape: MusicCore.Shape { Theory.buildShape(tonic, scaleId, shape, 15) }

    var body: some View {
        let _ = model.settingsVersion
        let shp = currentShape
        let maxFret = max(15, shp.maxFret + 1)
        VStack(alignment: .leading, spacing: 16) {
            ViewHead(title: "Scales",
                     lead: "Choose a scale and a key. Bright dots are the shape to learn, faint dots show the same scale everywhere else on the neck.")
                .padding(.bottom, -16)
            controls
            Card(padding: Theme.fretboardCardPadding) {
                FretboardView(maxFret: maxFret, marks: boardMarks(shp, maxFret: maxFret)) { s, f in
                    services?.audio.pluck(Theory.midiAt(s, f), when: 0, duration: 1.2)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                notesCard.frame(maxWidth: .infinity)
                factsCard.frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if transport == nil, let audio = services?.audio {
                let t = Transport(audio: audio)
                t.metronome = false; t.countIn = false
                t.onPosition = { i, _, _, _ in activeIdx = i >= 0 && i < playOrder.count ? playOrder[i] : nil }
                t.onState = { p in playing = p; if !p { activeIdx = nil } }
                transport = t
            }
        }
        .onDisappear { transport?.stop() }
    }

    // MARK: state

    /// Keep the same sound when switching between e.g. Db major and C# minor; fall back to a valid shape.
    private func fixState() {
        let keys = Theory.keyNames(sc.family)
        if !keys.contains(key) {
            let pc = Theory.notePc(Theory.parseNote(key))
            key = keys.first { Theory.notePc(Theory.parseNote($0)) == pc } ?? keys[0]
        }
        let shapes = Theory.shapeOptions(scaleId).map { $0.id }
        if !shapes.contains(shape) { shape = sc.pent ? "box1" : "open" }
    }

    private func changed() {
        fixState()
        transport?.stop()
    }

    // MARK: controls

    private var controls: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
            Toolbar {
                Field("Scale") {
                    Segmented(options: Self.scaleTabs, selection: $scaleId) { _ in changed() }
                }
                Field("Key") {
                    HStack(spacing: 4) {
                        ForEach(Theory.keyNames(sc.family), id: \.self) { k in
                            KeyButton(text: Theory.noteLabel(Theory.parseNote(k), nm) + (sc.family == .minor ? "m" : ""), on: k == key) {
                                key = k; changed()
                            }
                        }
                    }
                }
                Field("Shape") {
                    Button { shapeMenuOpen.toggle() } label: {
                        HStack {
                            Text(Theory.shapeOptions(scaleId).first { $0.id == shape }?.name ?? shape).font(.system(size: 14)).foregroundStyle(Theme.ink)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .frame(minWidth: 150)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .popover(isPresented: $shapeMenuOpen, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Theory.shapeOptions(scaleId), id: \.id) { o in
                                Button {
                                    shape = o.id; changed(); shapeMenuOpen = false
                                } label: {
                                    HStack {
                                        Text(o.name).font(.system(size: 14, weight: o.id == shape ? .bold : .regular))
                                        Spacer()
                                        if o.id == shape { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                                    }
                                    .foregroundStyle(Theme.ink)
                                    .padding(.vertical, 6).padding(.horizontal, 10)
                                    .frame(minWidth: 220, alignment: .leading)
                                    .background(o.id == shape ? Theme.soft : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Field("Dots show") {
                    Segmented(options: [SegOption(Labels.names, "Note names"), SegOption(.degrees, "Scale steps"), SegOption(.none, "Nothing")], selection: $labels)
                }
                Spacer()
                GQButton(playing ? "Stop" : "Hear it", icon: playing ? "stop.fill" : "play.fill", style: .primary) { togglePlay() }
                GQButton("Practise in the Studio →", disabled: shape == "neck") {
                    model.goStudio(StudioParams(tonic: key, scaleId: scaleId, shapeId: shape))
                }
                .help(shape == "neck" ? "Pick a shape first" : "")
            }
            .padding(.top, 14)
            }
        }
    }

    // MARK: board

    private func markFor(_ n: ShapeNote) -> FretMark {
        let hex: UInt32 = settings.colors ? Theme.spelledHex(n.spelled) : Theme.plainNoteHex
        var label = ""
        if labels == .names { label = Theory.noteLabel(n.spelled, nm) }
        else if labels == .degrees { label = n.label }
        return FretMark(string: n.string, fret: n.fret, label: label, color: Color(hex: hex), textColor: Theme.inkOn(hex), kind: n.isRoot ? .root : .note)
    }

    private func boardMarks(_ shp: MusicCore.Shape, maxFret: Int) -> [FretMark] {
        var marks: [FretMark] = []
        if shape != "neck" {
            let inShape = Set(shp.notes.map { "\($0.string):\($0.fret)" })
            for n in Theory.buildShape(tonic, scaleId, "neck", maxFret).notes where !inShape.contains("\(n.string):\(n.fret)") {
                var m = markFor(n); m.kind = .ghost; m.label = ""; m.opacity = 0.28
                marks.append(m)
            }
        }
        for (i, n) in shp.notes.enumerated() {
            var m = markFor(n)
            if i == activeIdx { m.playing = true }
            marks.append(m)
        }
        return marks
    }

    // MARK: info cards

    private var notesCard: some View {
        let notes = Theory.scaleNotes(tonic, scaleId)
        let steps = Theory.stepPattern(scaleId)
        let shapeForScore = shape == "neck" ? (sc.pent ? "box1" : "open") : shape
        let score = try? Exercises.buildScaleScore(ScaleScoreOptions(tonic: key, scaleId: scaleId, shapeId: shapeForScore, pattern: .up, rhythm: .e, range: .root))
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                H3(Theory.noteLabel(tonic, nm) + " " + sc.name.lowercased() + " - the notes")
                FlowLayout(hSpacing: 4, vSpacing: 4, alignment: .top) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { i, n in
                        HStack(alignment: .top, spacing: 4) {
                            noteColumn(n.spelled, n.label)
                            stepPill(steps[i])
                        }
                    }
                    noteColumn(notes[0].spelled, "8")
                }
                .padding(.vertical, 4)
                SmallText("W = whole step (2 frets) · H = half step (1 fret)" + (sc.pent ? " · W+H = 3 frets" : ""), muted: true)
                if let score {
                    ScoreView(score: score, options: NotationOptions(showStaff: true, showTab: true, showNames: false, colors: settings.colors, naming: nm, minWidth: 360))
                        .padding(.top, 10)
                }
            }
        }
    }

    private func noteColumn(_ n: SpelledNote, _ label: String) -> some View {
        VStack(spacing: 3) {
            NoteBadge(spelled: n, settings: settings)
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
        }
    }

    private func stepPill(_ step: String) -> some View {
        let half = step == "H", wide = step == "W+H"
        return Text(step).font(.system(size: 11, weight: .heavy))
            .foregroundStyle(half ? Theme.accentDark : wide ? Theme.teal : Theme.segText)
            .padding(.vertical, 2).padding(.horizontal, 6)
            .background(half ? Theme.accentSoft : wide ? Theme.tealSoft : Theme.soft)
            .clipShape(Capsule())
            .padding(.top, 6)
    }

    private var factsCard: some View {
        let ks = Theory.keySignature(tonic, sc.family)
        let ksText: String = ks.fifths == 0 ? "no sharps or flats"
            : "\(abs(ks.fifths))" + (ks.fifths > 0 ? " sharp" : " flat") + (abs(ks.fifths) > 1 ? "s" : "") + ": " + ks.list.map { Theory.noteLabel($0, nm) }.joined(separator: " ")
        var facts: [String] = []
        let t = Theory.noteLabel(tonic, nm)
        if sc.family == .major {
            facts.append("Key signature of \(t) major: \(ksText).")
            facts.append("Its relative minor is \(Theory.noteLabel(Theory.relativeMinorOf(tonic), nm)) minor - same notes, different home note (step 6).")
        } else {
            facts.append("Key signature of \(t) minor: \(ksText).")
            facts.append("Its relative major is \(Theory.noteLabel(Theory.relativeMajorOf(tonic), nm)) major - same notes, different home note.")
        }
        switch scaleId {
        case .major: facts.append("Every major scale follows the same step pattern: W W H W W W H.")
        case .minor: facts.append("The natural minor pattern is W H W W H W W. It sounds darker because of the ♭3, ♭6 and ♭7.")
        case .majorPent: facts.append("Major pentatonic = the major scale without steps 4 and 7 (1 2 3 5 6). No half steps, so it is hard to hit a \"wrong\" note!")
        case .minorPent: facts.append("Minor pentatonic = 1 ♭3 4 5 ♭7. It is the most used scale for rock and blues solos.")
        case .blues: facts.append("The blues scale is the minor pentatonic plus one extra \"blue note\", the ♭5.")
        }
        if sc.pent { facts.append("The 5 shapes link together up the neck like puzzle pieces. Shape 1 starts on the minor root on the 6th string. Major and minor pentatonic share the same shapes - only the home note moves.") }
        if shape.hasPrefix("3nps") { facts.append("3-notes-per-string forms stretch across the neck. They are great for speed but need a wider hand - go slowly!") }
        if shape == "open" { facts.append("Open position uses open strings and the first frets - the best place to start.") }
        if shape == "r6" || shape == "r5" { facts.append("Root on the \(shape == "r6" ? "6th" : "5th") string: move this shape up or down the neck to play the scale in any key.") }
        return Card {
            VStack(alignment: .leading, spacing: 4) {
                H3("Good to know")
                ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: 15))
                        Text(f).font(.system(size: 15))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: hear it

    private func togglePlay() {
        guard let transport else { return }
        if transport.playing { transport.stop(); return }
        if shape == "neck" { model.toast("Pick a shape to hear it."); return }
        let notes = currentShape.notes
        let idx = Theory.patternIndices(notes.count, .updown)
        let items = idx.enumerated().map { i, k in
            TransportItem(i: i, beat: Double(i) * 0.5, beats: i == idx.count - 1 ? 1.5 : 0.5, rest: false, midis: [notes[k].midi])
        }
        playOrder = idx
        transport.load(items, totalBeats: Double(items.count) * 0.5 + 1)
        transport.bpm = 110
        transport.play(from: 0, skipCountIn: true)
    }
}
