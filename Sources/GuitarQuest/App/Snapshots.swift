// Hidden self-check: `GQ_SNAPSHOT_DIR=/some/dir .build/debug/GuitarQuest` renders every screen (and a components
// sheet) to PNG files and quits. Used to verify the UI without screen recording.
import SwiftUI
import AppKit
import MusicCore

@MainActor
enum Snapshots {
    static func runIfRequested(_ services: Services) {
        guard let dir = ProcessInfo.processInfo.environment["GQ_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let only = ProcessInfo.processInfo.environment["GQ_SNAPSHOT_ONLY"]
        // ImageRenderer lays out a ScrollView's content as empty, so screens are rendered directly (ScreenPage), not inside RootView.
        var pages: [(String, AnyView)] = [("components", AnyView(ComponentsSheet()))]
        for s in Screen.allCases { pages.append((s.rawValue, AnyView(ScreenPage(screen: s)))) }
        for (name, view) in pages where only == nil || only == name {
            services.model.screen = Screen(rawValue: name) ?? .explore
            let fixedHeight: CGFloat? = nil
            let content = view
                .environment(services.store)
                .environment(services.model)
                .environment(\.services, services)
                .frame(width: 1280, height: fixedHeight)
                .background(Theme.bg)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: 1280, height: fixedHeight)
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: url.appendingPathComponent("\(name).png"))
                    print("snapshot: \(name).png \(cg.width)x\(cg.height)")
                }
            } else {
                print("snapshot FAILED: \(name)")
            }
        }
        exit(0)
    }
}

/// One screen as the user sees it below the top bar, at its full content height.
struct ScreenPage: View {
    let screen: Screen
    var body: some View {
        Group {
            switch screen {
            case .explore: ExploreView()
            case .quest: QuestView()
            case .scales: ScalesView()
            case .studio: StudioView()
            case .harmony: HarmonyView()
            case .progress: ProgressView_()
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 60)
        .frame(width: 1280)
        .background(Theme.bg)
    }
}

/// Fretboard, notation and chord diagram side by side — the building blocks every screen uses.
struct ComponentsSheet: View {
    @Environment(ProgressStore.self) private var store

    var body: some View {
        let s = store.settings
        let shape = Theory.buildShape(Theory.parseNote("A"), .minorPent, "box1")
        var marks: [FretMark] = shape.notes.map { n in
            FretMark.note(n.string, n.fret, settings: s, spelled: n.spelled, kind: n.isRoot ? .root : .note)
        }
        let _ = marks.append(FretMark(string: 2, fret: 10, label: "?", color: Theme.ink, kind: .target))
        let _ = marks.append(FretMark.note(1, 12, settings: s, kind: .ring))
        let song = try! Exercises.buildSongScore(Songs.all[1])
        let blues = try! Exercises.buildScaleScore(ScaleScoreOptions(tonic: "A", scaleId: .blues, shapeId: "box1", pattern: .groups3, rhythm: .t, range: .full))
        let sixteenth = try! Exercises.buildScaleScore(ScaleScoreOptions(tonic: "Eb", scaleId: .major, shapeId: "3nps3", pattern: .groups4, rhythm: .s, range: .full))
        let single = Exercises.singleEvent(notes: [ScoreNote(string: 3, fret: 2, spelled: SpelledNote(5, 0))])
        VStack(alignment: .leading, spacing: 16) {
            Card(padding: Theme.fretboardCardPadding) { FretboardView(maxFret: 15, marks: marks, highlightString: 3) }
            Card(padding: Theme.fretboardCardPadding) { FretboardView(maxFret: 12, compact: true, marks: marks) }
            HStack(alignment: .top, spacing: 16) {
                Card { ScoreView(score: single, options: NotationOptions(showNames: true, minWidth: 220)) }.frame(width: 320)
                Card { ScoreView(score: song, options: NotationOptions(showNames: true, minWidth: 520), active: 9, next: 10) }
            }
            Card { ScoreView(score: blues, options: NotationOptions(minWidth: 520), active: 2, next: 3) }
            Card { ScoreView(score: sixteenth, options: NotationOptions(showStaff: false, showTab: true, showNames: true, minWidth: 520)) }
            Card {
                HStack(alignment: .top, spacing: 12) {
                    ChordDiagramView(voicing: Chords.bestVoicing(Theory.parseNote("C"), .maj)!, title: "C", width: 112)
                    ChordDiagramView(voicing: Chords.bestVoicing(Theory.parseNote("B"), .min)!, title: "Bm", width: 112)
                    ChordDiagramView(voicing: Chords.bestVoicing(Theory.parseNote("F"), .maj)!, title: "F", width: 112)
                    ChordDiagramView(voicing: Chords.voicingsFor(Theory.parseNote("G"), .maj7).last!, title: "Gmaj7", width: 170)
                    ChordDiagramView(voicing: Chords.bestVoicing(Theory.parseNote("D"), .dom7)!, width: 92)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { NoteBadge(spelled: SpelledNote(0, 0), settings: s); NoteBadge(pc: 1, settings: s); NoteBadge(spelled: SpelledNote(2, 0), settings: s, small: true) }
                        BigNote(label: "A", hex: Theme.letterHex(5))
                        HStack { PadButton(label: "C", hex: Theme.letterHex(0)) {}; PadButton(label: "C♯/D♭", hex: Theme.accHex, sharp: true, state: .good) {} }
                        HStack { GQButton("Play", style: .primary) {}; GQButton("Next level") {}; GQButton("All levels", style: .ghost) {}; Chip(text: "string 4, fret 7") {} }
                        Segmented(options: [SegOption("a", "Hidden"), SegOption("b", "Natural notes"), SegOption("c", "All notes")], selection: .constant("a"))
                        Stars(count: 2)
                    }
                }
            }
        }
        .padding(22)
    }
}

// MARK: - audio self-check

/// `GQ_AUDIO_CHECK=1 .build/debug/GuitarQuest`: renders a pluck, a strum, a click and a chime offline through the DSP
/// chain and prints level statistics, then starts the real engine, plays one note and quits. No sound card needed
/// for the first part; the second part fails loudly if AVAudioEngine cannot start.
@MainActor
enum AudioCheck {
    static func runIfRequested(_ services: Services) {
        guard ProcessInfo.processInfo.environment["GQ_AUDIO_CHECK"] == "1" else { return }
        let sr = 48000.0
        var st = RenderState()
        st.dsp = DSPState(sr: sr)
        func voice(_ id: Int, midi: Int, start: Double, gain: Float = 0.75, duration: Double? = nil) -> Voice {
            // offline Karplus-Strong (same algorithm as AudioEngine.stringBuffer)
            let f = Theory.freqOf(midi)
            let N = max(2, Int(floor(sr / f - 0.5)))
            let len = Int(sr * 1.8)
            var out = [Float](repeating: 0, count: len), line = [Float](repeating: 0, count: N)
            var prev: Float = 0, mean: Float = 0
            for i in 0..<N { let r = Float.random(in: -1..<1); prev += 0.55 * (r - prev); line[i] = prev; mean += prev }
            mean /= Float(N); for i in 0..<N { line[i] -= mean }
            let g = Float(pow(0.001, 1 / (f * max(1.0, 3.4 - Double(midi - 40) * 0.055))))
            var idx = 0
            for n in 0..<len { let cur = line[idx], nxt = line[idx + 1 == N ? 0 : idx + 1]; out[n] = cur; line[idx] = g * 0.5 * (cur + nxt); idx = idx + 1 == N ? 0 : idx + 1 }
            var v = Voice(id: id, kind: .sample(StringBuffer(samples: out, rate: f * (Double(N) + 0.5) / sr)), start: Int64(start * sr))
            v.gain = gain
            v.rate = f * (Double(N) + 0.5) / sr
            if let d = duration { v.holdEnd = Int64((start + d) * sr); v.fadeMul = Float(pow(0.0008 / Double(gain), 1.0 / (0.12 * sr))); v.stopAt = Int64((start + d + 0.15) * sr) }
            return v
        }
        st.voices.append(voice(1, midi: 57, start: 0.0, duration: 0.5))
        for (i, m) in [40, 47, 52, 56, 59, 64].enumerated() { st.voices.append(voice(10 + i, midi: m, start: 1.0 + Double(i) * 0.022, gain: 0.7, duration: 1.0)) }
        var click = Voice(id: 30, kind: .osc(.square, 1760), start: Int64(2.2 * sr)); click.bus = .click
        click.env = [EnvPoint(sample: Int64(2.2 * sr), gain: 0.0001), EnvPoint(sample: Int64(2.202 * sr), gain: 0.5), EnvPoint(sample: Int64(2.245 * sr), gain: 0.0001)]
        click.stopAt = Int64(2.26 * sr)
        st.voices.append(click)
        var chime = Voice(id: 31, kind: .osc(.triangle, Float(Theory.freqOf(84))), start: Int64(2.5 * sr)); chime.bus = .master
        chime.env = [EnvPoint(sample: Int64(2.5 * sr), gain: 0.0001), EnvPoint(sample: Int64(2.51 * sr), gain: 0.16), EnvPoint(sample: Int64(2.85 * sr), gain: 0.0001)]
        chime.stopAt = Int64(2.9 * sr)
        st.voices.append(chime)

        let block = 512
        let total = Int(3.2 * sr)
        var buf = [Float](repeating: 0, count: block)
        var peaks: [String: Float] = [:]
        var nan = 0
        var rendered = 0
        let t0 = Date()
        while rendered < total {
            buf.withUnsafeMutableBufferPointer { p in st.render(p.baseAddress!, block, volume: 0.8) }
            let sec = Double(rendered) / sr
            let label = sec < 1 ? "pluck A3 (0-1 s)" : sec < 2.2 ? "strum E major (1-2.2 s)" : sec < 2.5 ? "click (2.2-2.5 s)" : "chime (2.5-3.2 s)"
            for x in buf { if x.isNaN { nan += 1 } else { peaks[label] = max(peaks[label] ?? 0, abs(x)) } }
            rendered += block
        }
        let elapsed = Date().timeIntervalSince(t0)
        print(String(format: "offline render: %.2f s of audio in %.3f s (%.0f× realtime), NaN samples: %d, voices left: %d", Double(total) / sr, elapsed, Double(total) / sr / elapsed, nan, st.voices.count))
        for (k, v) in peaks.sorted(by: { $0.key < $1.key }) { print(String(format: "  peak %@: %.3f", k, v)) }
        // real engine
        let audio = services.audio
        let ok = audio.ensure()
        print("AVAudioEngine start: \(ok ? "ok" : "FAILED"), sample rate \(audio.sampleRate)")
        if ok {
            audio.pluck(57, when: 0, duration: 0.6)
            audio.click(when: audio.now + 0.7, accent: true)
            let t = audio.now
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                print(String(format: "audio clock advanced %.2f s in 1.2 s wall time", audio.now - t))
                exit(nan == 0 && ok ? 0 : 1)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(2))
        }
        exit(nan == 0 && ok ? 0 : 1)
    }
}
