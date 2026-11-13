// Fretboard Explorer: tap a fret, see the note name, the tab and the staff together. Port of js/views/explore.js.
import SwiftUI
import MusicCore

struct ExploreView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services

    private enum ShowMode: String { case none, naturals, all }

    @State private var show: ShowMode = .none
    @State private var find: Int? = nil
    @State private var sel = Position(string: 3, fret: 2)
    /// While "Walk up a string" runs, these marks replace the computed ones (like the web version).
    @State private var walkMarks: [FretMark]? = nil
    @State private var walkString: Int? = nil
    @State private var walkTasks: [Task<Void, Never>] = []

    private var settings: Settings { store.settings }
    private var nm: Naming { settings.namingShort }

    var body: some View {
        let _ = model.settingsVersion // re-render when a setting changes
        VStack(alignment: .leading, spacing: 16) {
            ViewHead(title: "Fretboard Explorer",
                     lead: "Tap any fret. You will hear the note and see its name, its tab number and how it looks on the staff.")
                .padding(.bottom, -16)
            toolbar
            Card(padding: Theme.fretboardCardPadding) {
                FretboardView(maxFret: 15, marks: walkMarks ?? marks, highlightString: walkMarks != nil ? walkString : sel.string) { s, f in
                    select(s, f, play: true)
                }
            }
            infoCards
            alphabetCard
        }
        .onDisappear { stopWalk() }
    }

    // MARK: toolbar

    private var toolbar: some View {
        Card {
            Toolbar {
                Field("Show note names") {
                    Segmented(options: [SegOption(ShowMode.none, "Hidden"), SegOption(.naturals, "Natural notes"), SegOption(.all, "All notes")], selection: $show)
                }
                Field("Find every…") {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { l in
                            let pc = Theory.LETTER_PC[l]
                            let hex = Theme.letterHex(l)
                            let on = find == pc
                            Button { find = on ? nil : pc } label: {
                                Text(Theory.noteLabel(SpelledNote(l, 0), nm))
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(on ? Theme.inkOn(hex) : Theme.ink)
                                    .frame(width: 38, height: 36)
                                    .background(on ? Color(hex: hex) : Color(hex: hex).opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.ink : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Field("Walk up a string") {
                    HStack(spacing: 6) {
                        ForEach([6, 5, 4, 3, 2, 1], id: \.self) { s in
                            Chip(text: "\(s) \(Theory.OPEN_NAMES[s])") { walk(s) }
                                .help("Play string \(s) from open to fret 12")
                        }
                    }
                }
            }
        }
    }

    // MARK: marks

    private var marks: [FretMark] {
        var out: [FretMark] = []
        let selMidi = Theory.midiAt(sel.string, sel.fret)
        for s in 1...6 {
            for f in 0...15 {
                let midi = Theory.midiAt(s, f), pc = Theory.mod(midi, 12)
                if s == sel.string && f == sel.fret { continue }
                if let find {
                    if pc == find { var m = FretMark.note(s, f, settings: settings); m.pop = true; out.append(m) }
                    continue
                }
                if midi == selMidi { var m = FretMark.note(s, f, settings: settings); m.kind = .ring; out.append(m); continue }
                if show == .all || (show == .naturals && Theory.isNaturalPc(pc)) {
                    var m = FretMark.note(s, f, settings: settings); m.opacity = 0.8; out.append(m)
                }
            }
        }
        var m = FretMark.note(sel.string, sel.fret, settings: settings, kind: .root)
        m.pop = true
        out.append(m)
        return out
    }

    private func select(_ string: Int, _ fret: Int, play: Bool) {
        stopWalk()
        sel = Position(string: string, fret: fret)
        if play { services?.audio.pluck(Theory.midiAt(string, fret), when: 0, duration: 1.6) }
    }

    // MARK: info cards

    private var selMidi: Int { Theory.midiAt(sel.string, sel.fret) }
    private var selPc: Int { Theory.mod(selMidi, 12) }

    private var infoCards: some View {
        ProportionalHStack(ratios: [1, 1.25, 1], spacing: 16) {
            noteCard
            scoreCard
            ladderCard
        }
    }

    private var noteCard: some View {
        let pc = selPc
        let hex = Theme.pcHex(pc)
        let label = Theory.pcLabel(pc, nm, Theory.isNaturalPc(pc) ? settings.accidentals : .both)
        let others = Theory.positionsOfMidi(selMidi, 15).filter { !($0.string == sel.string && $0.fret == sel.fret) }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                BigNote(label: label, hex: hex)
                VStack(alignment: .leading, spacing: 3) {
                    (Text("String \(sel.string)").bold() + Text(" (\(Theory.OPEN_NAMES[sel.string]) string) · ") + Text(sel.fret == 0 ? "open" : "fret \(sel.fret)").bold())
                        .font(.system(size: 15))
                    HStack(spacing: 4) {
                        Text("Tab number:").foregroundStyle(Theme.muted)
                        Text(String(sel.fret)).font(.system(size: 15, weight: .heavy))
                            .frame(minWidth: 22).padding(.horizontal, 6).background(Theme.soft).clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("on line \(sel.string) from the top").foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 15))
                    if settings.naming != .letters {
                        Text("Letter name: " + Theory.pcLabel(pc, .letters, .both)).font(.system(size: 15)).foregroundStyle(Theme.muted)
                    }
                    if !Theory.isNaturalPc(pc) {
                        Text("A black-key note: it has two names.").font(.system(size: 15)).foregroundStyle(Theme.muted)
                    }
                }
                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SmallText("The very same note (same sound) is also here:")
                        FlowLayout(hSpacing: 6, vSpacing: 6) {
                            ForEach(others, id: \.self) { p in
                                Chip(text: "string \(p.string), fret \(p.fret)") { select(p.string, p.fret, play: true) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var scoreCard: some View {
        let spelled = Theory.spellPc(selPc, settings.spellPref)
        let score = Exercises.singleEvent(notes: [ScoreNote(string: sel.string, fret: sel.fret, midi: selMidi, spelled: spelled)])
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                H3("Tab and staff")
                ScoreView(score: score, options: NotationOptions(showStaff: true, showTab: true, showNames: true, colors: settings.colors, naming: nm, minWidth: 220))
                    .frame(minHeight: 60)
                SmallText("Guitar music is written one octave higher than it sounds, so it fits on the treble staff.", muted: true)
            }
        }
    }

    private var ladderCard: some View {
        let open = Theory.TUNING[sel.string]
        var frets: [Int] = []
        let intro: String
        if sel.fret <= 7 {
            frets = Array(0...sel.fret)
            intro = "Start from the open string (\(Theory.OPEN_NAMES[sel.string].uppercased())) and go up one fret at a time:"
        } else if sel.fret <= 12 {
            frets = Array(stride(from: 12, through: sel.fret, by: -1))
            intro = "Fret 12 is the open-string note again, one octave higher. Count back from there:"
        } else {
            frets = Array(12...sel.fret)
            intro = "Fret 12 is the open-string note again. Count up from there:"
        }
        let names = frets.map { Theory.mod(open + $0, 12) }
        var crosses = false
        if names.count > 1 {
            for k in 1..<names.count {
                let a = names[k - 1], b = names[k]
                if (a == 4 && b == 5) || (a == 5 && b == 4) || (a == 11 && b == 0) || (a == 0 && b == 11) { crosses = true }
            }
        }
        let pref = settings.accidentals
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                H3("How to find it")
                SmallText(intro)
                FlowLayout(hSpacing: 4, vSpacing: 4) {
                    ForEach(Array(frets.enumerated()), id: \.offset) { k, f in
                        let p = Theory.mod(open + f, 12)
                        let hex = Theme.pcHex(p)
                        HStack(spacing: 4) {
                            VStack(spacing: 3) {
                                Text(Theory.pcLabel(p, nm, pref)).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.inkOn(hex))
                                    .fixedSize()
                                    .frame(minWidth: 34).padding(.vertical, 4).padding(.horizontal, 6)
                                    .background(Color(hex: hex)).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(f == 0 ? "open" : "fret \(f)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                                    .fixedSize()
                            }
                            .padding(4)
                            .background(f == sel.fret ? Theme.accentSoft : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(f == sel.fret ? Theme.accent : .clear, lineWidth: 2))
                            if k < frets.count - 1 {
                                Text("›").font(.system(size: 15, weight: .heavy)).foregroundStyle(Color(hex: 0xB8BDC8)).fixedSize()
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                TipText(crosses
                        ? "Remember: E → F and B → C are only one fret apart. There is no black key between them."
                        : "One fret = one half step. Two frets = one whole step.")
            }
        }
    }

    // MARK: alphabet + piano

    private var alphabetCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                H3("The musical alphabet")
                SmallText("Music uses only seven letters, then starts again. Most neighbours are 2 frets apart, but E–F and B–C are only 1 fret apart.")
                FlowLayout(hSpacing: 6, vSpacing: 6) {
                    ForEach(Array([0, 1, 2, 3, 4, 5, 6, 0].enumerated()), id: \.offset) { k, l in
                        let hex = Theme.letterHex(l)
                        HStack(spacing: 6) {
                            Button { find = Theory.LETTER_PC[l] } label: {
                                Text(Theory.noteLabel(SpelledNote(l, 0), nm)).font(.system(size: 18, weight: .black)).foregroundStyle(Theme.inkOn(hex))
                                    .frame(width: 44, height: 44).background(Color(hex: hex)).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            if k < 7 {
                                let half = l == 2 || l == 6
                                Text(half ? "1 fret" : "2 frets").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(half ? Theme.accentDark : Theme.muted)
                                    .padding(.vertical, 2).padding(.horizontal, 6)
                                    .background(half ? Theme.accentSoft : Theme.soft).clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                piano
                SmallText("Piano view of the same notes. Tap a key to find it on the guitar.", muted: true)
            }
        }
    }

    private var piano: some View {
        let whites = [0, 2, 4, 5, 7, 9, 11]
        let blacks: [(Int, Int)] = [(1, 0), (3, 1), (6, 3), (8, 4), (10, 5)]
        return GeometryReader { geo in
            let w = geo.size.width
            let kw = w / 7
            ZStack(alignment: .topLeading) {
                ForEach(Array(whites.enumerated()), id: \.offset) { k, pc in
                    let on = pc == selPc
                    Button { pressKey(pc) } label: {
                        VStack { Spacer(); Text(Theory.pcLabel(pc, nm, .sharp)).font(.system(size: 13, weight: .heavy)).foregroundStyle(on ? Theme.accentDark : Theme.segText).padding(.bottom, 6) }
                            .frame(width: kw, height: 120)
                            .background(on ? Color(hex: 0xFFE9DC) : .white)
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
                            .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).stroke(Color(hex: 0xC9C2B4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offset(x: CGFloat(k) * kw)
                }
                ForEach(Array(blacks.enumerated()), id: \.offset) { _, b in
                    let (pc, after) = b
                    let on = pc == selPc
                    Button { pressKey(pc) } label: {
                        Rectangle().fill(on ? Theme.accent : Color(hex: 0x2B2F3A))
                            .frame(width: w * 0.084, height: 74)
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                            .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6).stroke(Theme.ink, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(Theory.pcLabel(pc, nm, .both))
                    .offset(x: CGFloat(after + 1) * kw - w * 0.042)
                }
            }
        }
        .frame(maxWidth: 420)
        .frame(height: 120)
        .padding(.vertical, 6)
    }

    private func pressKey(_ pc: Int) {
        find = pc
        services?.audio.pluck(60 + pc, when: 0, duration: 1.2)
    }

    // MARK: walk up a string

    private func walk(_ s: Int) {
        stopWalk()
        find = nil
        guard let audio = services?.audio, audio.ensure() else { return }
        let t0 = audio.now + 0.1, step = 0.32
        walkString = s
        walkMarks = []
        for f in 0...12 {
            audio.pluck(Theory.midiAt(s, f), when: t0 + Double(f) * step, duration: step + 0.1)
            let delay = 0.1 + Double(f) * step
            walkTasks.append(Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                var m = FretMark.note(s, f, settings: settings); m.pop = true
                walkMarks?.append(m)
            })
        }
        walkTasks.append(Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1 + 13 * step))
            guard !Task.isCancelled else { return }
            sel = Position(string: s, fret: 12)
        })
    }

    private func stopWalk() {
        for t in walkTasks { t.cancel() }
        walkTasks = []
        walkMarks = nil
        walkString = nil
    }
}


/// CSS `grid-template-columns: 1fr 1.25fr 1fr`: columns share the width by ratio, top-aligned.
fileprivate struct ProportionalHStack: Layout {
    var ratios: [CGFloat]
    var spacing: CGFloat = 16

    private func widths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let avail = total - spacing * CGFloat(max(0, n - 1))
        let sum = ratios.prefix(n).reduce(0, +)
        return (0..<n).map { avail * (ratios.indices.contains($0) ? ratios[$0] : 1) / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 1000
        let ws = widths(total, subviews.count)
        let h = zip(subviews, ws).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(bounds.width, subviews.count)
        var x = bounds.minX
        for (sv, w) in zip(subviews, ws) {
            sv.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: nil))
            x += w + spacing
        }
    }
}
