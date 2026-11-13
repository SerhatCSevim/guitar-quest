// Chords & Harmony → Jam along: strum a progression with a count-in, loop, click and the guitar part.
// Port of renderJam in web/js/views/harmony.js.
import SwiftUI
import MusicCore

struct HarmonyJamView: View {
    @Binding var state: HarmonyState
    @Environment(ProgressStore.self) private var store
    @Environment(\.services) private var services
    @State private var transport: Transport? = nil
    @State private var items: [TransportItem] = []

    static let counts = ["1", "&", "2", "&", "3", "&", "4", "&"]

    private var prog: Progression { GameData.PROGS.first { $0.id == state.jamProg } ?? GameData.PROGS[0] }

    var body: some View {
        let s = store.settings
        let p = prog
        let keys = GameData.jamKeys(p.family)
        let key = keys.contains(state.jamKey) ? state.jamKey : keys[0]
        let chords = GameData.progChords(p, key)
        let voicings = chords.map { Chords.bestVoicing($0.root, $0.type)! }
        let strum = GameData.STRUMS.first { $0.id == state.jamStrum } ?? GameData.STRUMS[2]
        let playing = transport?.playing ?? false
        let pos = transport?.position ?? -1
        let cur: TransportItem? = pos >= 0 && pos < items.count ? items[pos] : nil
        let bar = cur?.bar ?? 0
        let nextBar = (bar + 1) % chords.count
        let slots = Array(strum.slots)
        let keyName = Theory.noteLabel(Theory.parseNote(key), s.namingShort) + (p.family == .minor ? " minor" : " major")

        VStack(alignment: .leading, spacing: 16) {
            Card {
                Toolbar {
                    Field("Progression") {
                        Picker("", selection: $state.jamProg) {
                            ForEach(GameData.PROGS) { pr in Text(pr.name + "  (" + pr.label + ")").tag(pr.id) }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 300)
                    }
                    Field("Key") {
                        KeyChips(keys: keys, value: key, suffix: p.family == .minor ? "m" : "", naming: s.namingShort) { state.jamKey = $0; stopJam() }
                    }
                    Field("Strum pattern") {
                        Picker("", selection: $state.jamStrum) {
                            ForEach(GameData.STRUMS) { st in Text(st.name).tag(st.id) }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 260)
                    }
                }
            }
            Card {
                Toolbar(spacing: 18) {
                    TransportButton(icon: playing ? "stop.fill" : "play.fill", on: playing, play: true, help: "Play / stop") {
                        if playing { stopJam() } else { start(chords: chords, voicings: voicings, strum: strum) }
                    }
                    HStack(spacing: 6) {
                        SmallText("Tempo", muted: true)
                        Slider(value: Binding(get: { Double(state.jamBpm) }, set: { v in state.jamBpm = Int(v); transport?.setTempo(state.jamBpm) }), in: 40...160, step: 1)
                            .frame(width: 150).tint(Theme.accent)
                        Text("\(state.jamBpm) BPM").font(.system(size: 15, weight: .black)).frame(minWidth: 74, alignment: .leading)
                    }
                    HStack(spacing: 6) {
                        TransportButton(icon: "metronome", label: "Click", on: state.jamMetronome, isToggle: true) {
                            state.jamMetronome.toggle(); transport?.metronome = state.jamMetronome
                        }
                        TransportButton(icon: "speaker.wave.2.fill", label: "Guitar", on: state.jamSound, isToggle: true) {
                            state.jamSound.toggle(); transport?.sound = state.jamSound
                        }
                    }
                    SmallText("Turn the guitar off and strum the chords yourself!", muted: true)
                }
            }
            Card {
                HStack(alignment: .center, spacing: 24) {
                    HStack(alignment: .bottom, spacing: 18) {
                        VStack(alignment: .leading, spacing: 2) {
                            jamLabel("Now")
                            ChordDiagramView(voicing: voicings[bar], title: HarmonyAudio.sym(chords[bar].root, chords[bar].type, s), width: 190)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            jamLabel("Next")
                            ChordDiagramView(voicing: voicings[nextBar], title: HarmonyAudio.sym(chords[nextBar].root, chords[nextBar].type, s), width: 120)
                        }
                        .opacity(0.7)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        H3("Strum: " + strum.name)
                        HStack(spacing: 6) {
                            ForEach(slots.indices, id: \.self) { k in
                                let c = slots[k]
                                let on = cur != nil && cur!.slot == k
                                VStack(spacing: 0) {
                                    Text(c == "D" ? "↓" : c == "U" ? "↑" : "·").font(.system(size: 30, weight: .black))
                                        .foregroundStyle(on ? .white : (c == "-" ? Color(hex: 0xC4BCAE) : Theme.ink))
                                    Text(Self.counts[k]).font(.system(size: 12, weight: .heavy)).foregroundStyle(on ? .white : Theme.muted)
                                }
                                .frame(width: 52).padding(.vertical, 6)
                                .background(on ? Theme.accent : Theme.soft)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        SmallText("↓ = strum down (towards the floor) · ↑ = strum up · keep your hand moving even on the dots!", muted: true)
                    }
                    .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
                }
            }
            Card {
                H3(p.name + " in " + keyName)
                FlowLayout(hSpacing: 6, vSpacing: 6) {
                    ForEach(chords.indices, id: \.self) { b in
                        let on = cur != nil && cur!.bar == b
                        VStack(spacing: 0) {
                            Text(HarmonyAudio.sym(chords[b].root, chords[b].type, s)).font(.system(size: 18, weight: .black)).foregroundStyle(Theme.ink)
                            Text(chords[b].roman).font(.custom("Georgia", size: 14).weight(.bold)).foregroundStyle(Theme.muted)
                        }
                        .frame(minWidth: 86).padding(10)
                        .background(on ? Color(hex: 0xFFF3EC) : Theme.soft)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.accent : .clear, lineWidth: 2))
                    }
                }
            }
        }
        .onChange(of: state.jamProg) { _, _ in state.jamFamily = prog.family; stopJam() }
        .onChange(of: state.jamStrum) { _, _ in stopJam() }
        .onAppear { state.jamFamily = p.family }
        .onDisappear { stopJam() }
    }

    private func jamLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .heavy)).kerning(0.7).foregroundStyle(Theme.muted)
    }

    private func buildItems(chords: [HarmonizedChord], voicings: [Voicing], strum: StrumPattern) -> [TransportItem] {
        var out: [TransportItem] = []
        let slotList = Array(strum.slots).enumerated().filter { $0.element != "-" }.map { (c: $0.element, k: $0.offset) }
        for b in chords.indices {
            let midis = Chords.voicingNotes(voicings[b]).map { $0.midi }
            for (si, s) in slotList.enumerated() {
                let nextK = si + 1 < slotList.count ? slotList[si + 1].k : 8
                out.append(TransportItem(i: out.count, beat: Double(b * 4) + Double(s.k) * 0.5, beats: Double(nextK - s.k) * 0.5, rest: false,
                                         midis: midis, strum: true, dir: s.c == "D" ? .down : .up, velocity: s.k == 0 ? 0.75 : 0.55, bar: b, slot: s.k))
            }
        }
        return out
    }

    private func start(chords: [HarmonizedChord], voicings: [Voicing], strum: StrumPattern) {
        guard let services else { return }
        stopJam()
        let t = Transport(audio: services.audio)
        items = buildItems(chords: chords, voicings: voicings, strum: strum)
        t.load(items, totalBeats: Double(chords.count * 4), beatsPerBar: 4)
        t.bpm = state.jamBpm
        t.loop = true
        t.metronome = state.jamMetronome
        t.countIn = true
        t.sound = state.jamSound
        t.onState = { playing in
            if playing { services.clock.start("jam") } else { services.clock.stop("jam") }
        }
        transport = t
        t.play()
    }

    private func stopJam() {
        transport?.stop()
        transport = nil
    }
}
