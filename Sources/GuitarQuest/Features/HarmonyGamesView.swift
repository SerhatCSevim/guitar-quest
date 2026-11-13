// Chords & Harmony → Theory games: five games × Easy/Medium/Hard. Port of renderGames/nextTheory/checkTheory
// in web/js/views/harmony.js.
import SwiftUI
import MusicCore

struct TheoryGameDef: Identifiable {
    let id: String
    let name: String
    let desc: String
}

struct TheoryQuestion {
    enum Kind {
        case pc(Int)
        case spelled(SpelledNote)
        case multi([SpelledNote])
        case choice(answer: String, options: [String])
    }
    var kind: Kind
    var text: String
    var explain: String
    var stepFrom: SpelledNote? = nil
}

struct HarmonyGamesView: View {
    @Binding var state: HarmonyState
    @Environment(ProgressStore.self) private var store
    @Environment(\.services) private var services

    static let games: [TheoryGameDef] = [
        TheoryGameDef(id: "steps", name: "Half & whole steps", desc: "1 fret = half step, 2 frets = whole step."),
        TheoryGameDef(id: "scale", name: "Scale steps", desc: "Find a step of a major scale."),
        TheoryGameDef(id: "triad", name: "Build the chord", desc: "Spell a chord with its 3 notes."),
        TheoryGameDef(id: "family", name: "Chord families", desc: "Which chord is IV in G?"),
        TheoryGameDef(id: "keysig", name: "Key signatures", desc: "How many sharps or flats?"),
    ]

    // game state (web: gameState)
    @State private var score = 0
    @State private var streak = 0
    @State private var question: TheoryQuestion? = nil
    @State private var picked: [SpelledNote] = []
    @State private var acc = 0
    @State private var locked = false
    @State private var feedback = ""
    @State private var feedbackKind: FeedbackText.Kind = .none
    @State private var showNext = false
    @State private var goodAnswers: Set<String> = []      // choice labels / pc strings marked green
    @State private var badAnswer: String? = nil
    @State private var autoNext: DispatchWorkItem? = nil

    private var nm: Naming { store.settings.namingShort }
    private var bestKey: String { state.gameId + ":" + state.gameLevel.rawValue }
    @State private var questionNaming: Naming = .letters

    init(state: Binding<HarmonyState>) {
        _state = state
        // first question right away (onAppear also re-checks the naming setting)
        _question = State(initialValue: Self.makeQuestion(game: state.wrappedValue.gameId, level: state.wrappedValue.gameLevel, nm: .letters))
    }

    var body: some View {
        let s = store.settings
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 14) {
                ForEach(Self.games) { g in
                    GameCardButton(name: g.name, desc: g.desc, on: g.id == state.gameId) {
                        state.gameId = g.id
                        restart()
                    }
                }
            }
            Card {
                Toolbar {
                    Field("Level") {
                        Segmented(options: [SegOption(TheoryLevel.easy, "Easy"), SegOption(.medium, "Medium"), SegOption(.hard, "Hard")], selection: $state.gameLevel,
                                  onChange: { _ in restart() })
                    }
                    HudStat(icon: "star.fill", value: String(score))
                    HudStat(icon: "flame.fill", value: String(streak), color: Theme.accent)
                    SmallText("Best streak: \(store.data.theory.best[bestKey] ?? 0)", muted: true)
                }
            }
            Card(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
                VStack(spacing: 12) {
                    Text(question?.text ?? "").font(.system(size: 20, weight: .heavy)).multilineTextAlignment(.center)
                    if let from = question?.stepFrom { stepStrip(from) }
                    pad(s)
                    FeedbackText(text: feedback, kind: feedbackKind)
                    if showNext { GQButton("Next", style: .primary) { nextTheory() } }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { if question == nil || questionNaming != nm { nextTheory() } }
        .onDisappear { autoNext?.cancel() }
    }

    // MARK: pads

    @ViewBuilder private func pad(_ s: Settings) -> some View {
        if let q = question {
            switch q.kind {
            case .choice(_, let options):
                FlowLayout(hSpacing: 10, vSpacing: 10) {
                    ForEach(options, id: \.self) { o in
                        ChoiceButton(text: o, state: goodAnswers.contains(o) ? .good : (badAnswer == o ? .bad : .none)) { checkTheory(.choice(o)) }
                    }
                }
                .frame(maxWidth: 820)
            case .pc:
                FlowLayout(hSpacing: 10, vSpacing: 10) {
                    ForEach(0..<12, id: \.self) { pc in
                        let st: PadButton.PadState = goodAnswers.contains("pc\(pc)") ? .good : (badAnswer == "pc\(pc)" ? .bad : .none)
                        PadButton(label: Theory.pcLabel(pc, nm, .both), hex: Theme.pcHex(pc), sharp: !Theory.isNaturalPc(pc), state: st) { checkTheory(.pc(pc)) }
                    }
                }
                .frame(maxWidth: 820)
            case .spelled, .multi:
                VStack(spacing: 10) {
                    Segmented(options: [SegOption(-1, "♭ flat"), SegOption(0, "♮ natural"), SegOption(1, "♯ sharp")], selection: $acc)
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { l in
                            PadButton(label: Theory.LETTERS[l], hex: Theme.letterHex(l)) {
                                let n = SpelledNote(l, acc)
                                acc = 0
                                if case .spelled = q.kind { checkTheory(.spelled(n)) } else { addPicked(n) }
                            }
                        }
                    }
                    if case .multi(let answer) = q.kind {
                        HStack(spacing: 8) {
                            ForEach(0..<answer.count, id: \.self) { i in
                                if i < picked.count {
                                    Button { if !locked { picked.remove(at: i) } } label: {
                                        Text(Theory.noteLabel(picked[i], s.naming)).font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.inkOn(Theme.spelledHex(picked[i])))
                                            .frame(minWidth: 46, minHeight: 40).padding(.horizontal, 8)
                                            .background(Color(hex: Theme.spelledHex(picked[i]))).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain).help("Remove")
                                } else {
                                    Text("?").font(.system(size: 18, weight: .black)).foregroundStyle(Color(hex: 0xB3AA9A))
                                        .frame(width: 46, height: 40)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xCFC6B6), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Seven neighbouring frets around the start note, so the step can be counted.
    private func stepStrip(_ from: SpelledNote) -> some View {
        let base = Theory.notePc(from)
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(-3...3, id: \.self) { k in
                    let pc = Theory.mod(base + k, 12)
                    let black = !Theory.isNaturalPc(pc)
                    let isFrom = k == 0
                    VStack(spacing: 1) {
                        Text(isFrom ? Theory.noteLabel(from, nm) : "?").font(.system(size: 15, weight: .black))
                        Text(isFrom ? "start" : (k > 0 ? "+\(k)" : "\(k)")).font(.system(size: 10)).opacity(0.7)
                    }
                    .foregroundStyle(isFrom ? Theme.ink : (black ? .white : Theme.ink))
                    .frame(width: 54, height: 54)
                    .background(isFrom ? Color(hex: 0xFFF3EC) : (black ? Color(hex: 0x2B2F3A) : .white))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(isFrom ? Theme.accent : (black ? Color(hex: 0x2B2F3A) : Theme.line), lineWidth: 2))
                }
            }
            SmallText("Each box is one fret (one half step). Dark boxes are black-key notes.", muted: true)
        }
    }

    // MARK: game flow

    private func restart() {
        autoNext?.cancel()
        score = 0; streak = 0
        nextTheory()
    }

    private static func rnd<T>(_ arr: [T]) -> T { arr.randomElement()! }

    private func nextTheory() {
        autoNext?.cancel()
        picked = []; acc = 0; locked = false
        showNext = false
        feedback = ""; feedbackKind = .none
        goodAnswers = []; badAnswer = nil
        questionNaming = nm
        question = Self.makeQuestion(game: state.gameId, level: state.gameLevel, nm: nm)
    }

    /// Port of nextTheory(): builds one random question for a game and level.
    static func makeQuestion(game: String, level: TheoryLevel, nm: Naming) -> TheoryQuestion {
        let keys = GameData.THEORY_LEVEL_KEYS[level]!
        let sym = { (r: SpelledNote, t: ChordType) in Theory.chordSymbol(r, t, nm) }
        var q: TheoryQuestion
        switch game {
        case "steps":
            let pool = level == .easy ? ["C", "D", "E", "F", "G", "A", "B"] : Theory.MAJOR_KEYS + ["C#", "D#", "G#", "A#"]
            let from = Theory.parseNote(rnd(pool))
            let size = rnd([1, 2])
            let up = level == .easy ? true : Double.random(in: 0..<1) < 0.6
            let pc = Theory.mod(Theory.notePc(from) + (up ? size : -size), 12)
            q = TheoryQuestion(kind: .pc(pc),
                               text: "What is a " + (size == 1 ? "half" : "whole") + " step " + (up ? "above" : "below") + " " + Theory.noteLabel(from, nm) + "?",
                               explain: (size == 1 ? "A half step is 1 fret" : "A whole step is 2 frets") + (up ? " up" : " down") + ": " + Theory.noteLabel(from, nm) + " → " + Theory.pcLabel(pc, nm, .both) + ".",
                               stepFrom: from)
        case "scale":
            let key = Theory.parseNote(rnd(keys))
            let deg = rnd(level == .easy ? [2, 3, 4, 5] : [2, 3, 4, 5, 6, 7])
            let sc = Theory.scaleNotes(key, .major)
            let ans = sc[deg - 1]
            q = TheoryQuestion(kind: .spelled(SpelledNote(ans.letter, ans.alter)),
                               text: "In " + Theory.noteLabel(key, nm) + " major, what is note number \(deg)?",
                               explain: Theory.noteLabel(key, nm) + " major: " + sc.enumerated().map { "\($0.offset + 1)=" + Theory.noteLabel(SpelledNote($0.element.letter, $0.element.alter), nm) }.joined(separator: "  "))
        case "triad":
            let key = Theory.parseNote(rnd(keys))
            let types: [ChordType] = level == .easy ? [.maj, .min] : level == .medium ? [.maj, .min, .dim] : [.maj, .min, .dim, .aug]
            let type = rnd(types)
            let tones = Theory.chordTones(key, type)
            q = TheoryQuestion(kind: .multi(tones.map { SpelledNote($0.letter, $0.alter) }),
                               text: "Spell " + sym(key, type) + " (" + Theory.chordType(type).name.lowercased() + "): pick its 3 notes.",
                               explain: sym(key, type) + " = " + Theory.chordFormula(type).joined(separator: "-") + " = " + tones.map { Theory.noteLabel(SpelledNote($0.letter, $0.alter), nm) }.joined(separator: " "))
        case "family":
            let key = Theory.parseNote(rnd(keys))
            let fam = Theory.harmonize(key, .major, false)
            let d = rnd(level == .easy ? [1, 4, 5] : level == .medium ? [1, 2, 4, 5, 6] : [1, 2, 3, 4, 5, 6, 7])
            let right = fam[d - 1]
            let explain = Theory.noteLabel(key, nm) + " major family: " + fam.map { $0.roman + "=" + sym($0.root, $0.type) }.joined(separator: "  ")
            let others = Array(fam.filter { $0.degree != d }.shuffled().prefix(3)) + [right]
            if Double.random(in: 0..<1) < 0.5 || level == .easy {
                q = TheoryQuestion(kind: .choice(answer: sym(right.root, right.type), options: others.map { sym($0.root, $0.type) }.shuffled()),
                                   text: "In the key of " + Theory.noteLabel(key, nm) + " major, which chord is " + right.roman + "?", explain: explain)
            } else {
                q = TheoryQuestion(kind: .choice(answer: right.roman, options: others.map { $0.roman }.shuffled()),
                                   text: "In the key of " + Theory.noteLabel(key, nm) + " major, " + sym(right.root, right.type) + " is which chord?", explain: explain)
            }
        default: // keysig
            let key = Theory.parseNote(rnd(keys))
            let ks = Theory.keySignature(key, .major)
            let label = { (f: Int) -> String in f == 0 ? "none" : "\(abs(f))" + (f > 0 ? " ♯" : " ♭") }
            if Double.random(in: 0..<1) < 0.6 || level == .easy {
                let all = [0, 1, 2, 3, 4, 5, 6, -1, -2, -3, -4, -5, -6]
                let opts = Array(all.filter { $0 != ks.fifths }.shuffled().prefix(3)) + [ks.fifths]
                q = TheoryQuestion(kind: .choice(answer: label(ks.fifths), options: opts.map(label).shuffled()),
                                   text: "How many sharps or flats does " + Theory.noteLabel(key, nm) + " major have?",
                                   explain: Theory.noteLabel(key, nm) + " major: " + (ks.fifths != 0 ? ks.list.map { Theory.noteLabel($0, nm) }.joined(separator: " ") : "no sharps or flats"))
            } else {
                let others = Array(Theory.MAJOR_KEYS.filter { Theory.keySignature(Theory.parseNote($0), .major).fifths != ks.fifths }.shuffled().prefix(3))
                let options = (others + [Theory.noteAscii(key)]).map { Theory.noteLabel(Theory.parseNote($0), nm) + " major" }.shuffled()
                q = TheoryQuestion(kind: .choice(answer: Theory.noteLabel(key, nm) + " major", options: options),
                                   text: "Which major key has " + (ks.fifths == 0 ? "no sharps or flats" : label(ks.fifths) + " (" + ks.list.map { Theory.noteLabel($0, nm) }.joined(separator: " ") + ")") + "?",
                                   explain: "Sharps come in the order F C G D A E B, flats in the order B E A D G C F.")
            }
        }
        return q
    }

    private func addPicked(_ n: SpelledNote) {
        guard !locked, let q = question, case .multi(let answer) = q.kind else { return }
        if picked.contains(where: { Theory.sameNote($0, n) }) { return }
        picked.append(n)
        if picked.count == answer.count { checkTheory(.multi(picked)) }
    }

    enum Answer { case pc(Int), spelled(SpelledNote), multi([SpelledNote]), choice(String) }

    private func checkTheory(_ ans: Answer) {
        guard !locked, let q = question else { return }
        var ok = false
        var right = ""
        switch (q.kind, ans) {
        case (.pc(let a), .pc(let x)): ok = x == a; right = Theory.pcLabel(a, nm, .both); goodAnswers = ["pc\(a)"]; if !ok { badAnswer = "pc\(x)" }
        case (.spelled(let a), .spelled(let x)): ok = Theory.sameNote(x, a); right = Theory.noteLabel(a, nm)
        case (.multi(let a), .multi(let x)): ok = x.count == a.count && a.allSatisfy { aa in x.contains { Theory.sameNote($0, aa) } }; right = a.map { Theory.noteLabel($0, nm) }.joined(separator: " ")
        case (.choice(let a, _), .choice(let x)): ok = x == a; right = a; goodAnswers = [a]; if !ok { badAnswer = x }
        default: return
        }
        locked = true
        store.recordTheory(state.gameId, ok)
        if ok {
            streak += 1
            score += 10 + (streak >= 3 ? 5 : 0)
            store.recordTheoryBest(bestKey, streak)
            services?.audio.chime(true)
            var shown = ""
            if case .spelled(let a) = q.kind { shown = Theory.noteLabel(a, nm) + ". " }
            feedback = "Correct! " + shown + q.explain
            feedbackKind = .good
            let w = DispatchWorkItem { nextTheory() }
            autoNext = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: w)
        } else {
            streak = 0
            services?.audio.chime(false)
            feedback = "The answer is " + right + ". " + q.explain
            feedbackKind = .bad
            showNext = true
        }
    }
}

struct GameCardButton: View {
    let name: String
    let desc: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                Text(desc).font(.system(size: 13.5)).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color(hex: 0xFFFBF8) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(on ? Theme.accent : (hover ? Theme.line : .clear), lineWidth: 2))
            .shadow(color: Theme.shadow, radius: 9, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ChoiceButton: View {
    let text: String
    var state: PadButton.PadState = .none
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(minWidth: 120).padding(.vertical, 12).padding(.horizontal, 22)
                .background(state == .good ? Theme.goodSoft : (state == .bad ? Theme.badSoft : Color.white))
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(state == .good ? Theme.good : (state == .bad ? Theme.bad : Theme.line), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
