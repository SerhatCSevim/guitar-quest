// Note Quest: games that connect tab numbers, staff notes and note names to the fretboard.
// Port of web/js/views/quest.js (texts, scoring, stars and adaptive weighting kept 1:1).
import SwiftUI
import AppKit
import MusicCore

private enum QuestMode: String { case round, blitz }

private struct Question {
    var pos: Position
    var midi: Int
    var pc: Int
    var spelled: SpelledNote
}

private enum PadState { case none, good, bad }

private struct GameState {
    var game: String
    var mode: QuestMode
    var staffToo: Bool
    var levelIdx: Int
    var level: QuestLevel
    var pool: [Position]
    var total: Int?            // nil = blitz (unlimited)
    var q = 0
    var score = 0
    var streak = 0
    var bestStreak = 0
    var correct = 0
    var answered = 0
    var misses: [String: Int] = [:]
    var timeLeft = 60
    var last: Position? = nil
    var locked = false
    var hint = false
    var cur: Question? = nil
    // presentation
    var feedback = ""
    var feedbackKind: FeedbackText.Kind = .none
    var padStates: [Int: PadState] = [:]
    var marks: [FretMark] = []
    var highlight: Int? = nil
    var showNext = false
    var hintDisabled = false
    var staffReveal = "Any place that plays exactly this sound counts."

    var fbMaxFret: Int { level.maxFret > 4 ? 15 : 12 }
}

private struct Result {
    var stars: Int
    var score: Int
    var correct: Int
    var answered: Int
    var bestStreak: Int
    var misses: [(Position, Int)]
    var levelIdx: Int
}

private enum Phase { case lobby, playing, finished(Result) }

struct QuestView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services

    @State private var lobbyGame = "tab"
    @State private var lobbyMode: QuestMode = .round
    @State private var lobbyStaffToo = false
    @State private var phase: Phase = .lobby
    @State private var st: GameState? = nil
    @State private var flashes: [FretFlash] = []
    @State private var timers: [DispatchWorkItem] = []
    @State private var blitzTimer: Timer? = nil

    init() {
        QuestSnapshot.runIfRequested()
        // Debug aid for snapshots: GQ_QUEST_DEBUG=game|wrong|staff|hunt|result starts in that state.
        if let dbg = ProcessInfo.processInfo.environment["GQ_QUEST_DEBUG"], !dbg.isEmpty, dbg != "lobby" {
            var s = GameState(game: dbg == "staff" ? "staff" : dbg == "hunt" ? "hunt" : "tab", mode: .round, staffToo: dbg == "game",
                              levelIdx: 0, level: GameData.LEVELS[0], pool: GameData.LEVELS[0].pool, total: 10)
            let pos = Position(string: 2, fret: 3)
            let midi = Theory.midiAt(pos.string, pos.fret)
            s.cur = Question(pos: pos, midi: midi, pc: Theory.mod(midi, 12), spelled: Theory.spellPc(Theory.mod(midi, 12)))
            s.q = 3; s.answered = 2; s.correct = 2; s.score = 25; s.streak = 2
            if s.game == "hunt" { s.highlight = 2 }
            if dbg == "wrong" {
                s.locked = true; s.showNext = true; s.hintDisabled = true
                s.padStates = [0: .bad, 2: .good]
                s.feedback = "Not C. String 2 is B. Count up 3 frets: C, C♯, D. So it is D."; s.feedbackKind = .bad
                s.marks = [FretMark(string: 2, fret: 3, label: "D", color: Theme.letterColor(1), kind: .root, pop: true)]
            }
            if dbg == "result" {
                _phase = State(initialValue: .finished(Result(stars: 2, score: 85, correct: 8, answered: 10, bestStreak: 5,
                                                                misses: [(Position(string: 1, fret: 3), 2), (Position(string: 2, fret: 1), 1)], levelIdx: 0)))
            } else {
                _phase = State(initialValue: .playing)
            }
            _st = State(initialValue: s)
        }
    }

    private var settings: Settings { store.settings }
    private var nm: Naming { settings.namingShort }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .lobby: lobby
            case .playing: game
            case .finished(let r): result(r)
            }
        }
        .id(model.settingsVersion)
        .onAppear { installKeys() }
        .onDisappear { teardown() }
    }

    // MARK: - lobby

    private var lobby: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewHead(title: "Note Quest", lead: "Learn where every note lives. Pick a game, then a level. Three stars unlock bragging rights!")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(GameData.GAMES) { g in
                    let on = lobbyGame == g.id
                    Button { lobbyGame = g.id } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            GameArt(id: g.id).frame(height: 62).padding(.bottom, 4)
                            Text(g.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                            Text(g.desc).font(.system(size: 13.5)).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 14).padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(on ? Color(hex: 0xFFFBF8) : Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(on ? Theme.accent : Color.clear, lineWidth: 2))
                        .shadow(color: Theme.shadow, radius: 9, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)
            Card {
                Toolbar {
                    Field("Round") {
                        Segmented(options: [SegOption(QuestMode.round, "10 questions"), SegOption(.blitz, "60-second blitz")], selection: $lobbyMode)
                    }
                    if lobbyGame == "tab" {
                        Field("Also show the staff") {
                            Segmented(options: [SegOption(false, "No"), SegOption(true, "Yes")], selection: $lobbyStaffToo)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
                ForEach(Array(GameData.LEVELS.enumerated()), id: \.element.id) { i, lv in
                    let info = store.levelInfo(lobbyGame, lv.id)
                    HStack(alignment: .center, spacing: 12) {
                        Text(String(i + 1)).font(.system(size: 17, weight: .black)).foregroundStyle(Theme.teal)
                            .frame(width: 38, height: 38).background(Theme.tealSoft).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lv.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                            Text(lv.hint).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            Stars(count: info.stars)
                            if info.plays > 0 { Text("Best score \(info.best)").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        GQButton("Play", style: .primary) { startGame(i) }
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .shadow(color: Theme.shadow, radius: 9, y: 6)
                }
            }
        }
    }

    // MARK: - game

    @ViewBuilder private var game: some View {
        if let s = st, let c = s.cur {
            let g = GameData.GAMES.first { $0.id == s.game }!
            VStack(alignment: .leading, spacing: 0) {
                // HUD
                HStack(spacing: 16) {
                    GQButton("Levels", icon: "chevron.left", style: .ghost) { showLobby() }
                    (Text(g.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                     + Text(" · " + s.level.name).font(.system(size: 16)).foregroundStyle(Theme.muted))
                    hudProgress(s)
                    HudStat(icon: "star.fill", value: String(s.score))
                    HudStat(icon: "flame.fill", value: String(s.streak), color: Theme.accent)
                }
                .padding(.vertical, 10).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .shadow(color: Theme.shadow, radius: 9, y: 6)
                .padding(.bottom, 16)

                // question card
                VStack(spacing: 8) {
                    if s.game == "tab" {
                        Text("Which note is this?").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                        HStack(spacing: 22) {
                            BigTab(string: c.pos.string, fret: c.pos.fret).frame(width: 340)
                            if s.staffToo {
                                ScoreView(score: Exercises.singleEvent(notes: [ScoreNote(string: c.pos.string, fret: c.pos.fret, midi: c.midi, spelled: c.spelled)]),
                                          options: NotationOptions(showStaff: true, showTab: false, showNames: false, colors: false, minWidth: 200))
                                    .frame(width: 250)
                            }
                        }
                    } else if s.game == "staff" {
                        Text("Find this note on the fretboard").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                        ScoreView(score: Exercises.singleEvent(notes: [ScoreNote(string: c.pos.string, fret: c.pos.fret, midi: c.midi, spelled: c.spelled)]),
                                  options: NotationOptions(showStaff: true, showTab: false, showNames: false, colors: false, minWidth: 200))
                            .frame(width: 300)
                            .scaleEffect(1.25, anchor: .top)
                            .padding(.bottom, 30)
                        Text(s.staffReveal).font(.system(size: 14)).foregroundStyle(Theme.muted)
                    } else {
                        let label = Theory.noteLabel(c.spelled, nm)
                        let hex = Theme.spelledHex(c.spelled)
                        Text("Find").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                        HStack(spacing: 14) {
                            BigNote(label: label, hex: hex)
                            Text("on string \(c.pos.string) (\(Theory.OPEN_NAMES[c.pos.string].uppercased()))").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
                        }
                        Text("The string is highlighted on the fretboard below.").font(.system(size: 14)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .shadow(color: Theme.shadow, radius: 9, y: 6)
                .padding(.bottom, 16)

                // answer pad
                if s.game == "tab" {
                    let pcs = s.level.acc ? Array(0..<12) : [0, 2, 4, 5, 7, 9, 11]
                    HStack(spacing: 10) {
                        ForEach(pcs, id: \.self) { pc in
                            PadButton(label: Theory.pcLabel(pc, nm, .both), hex: Theme.pcHex(pc), sharp: !Theory.isNaturalPc(pc),
                                      state: padState(s.padStates[pc])) { answerPc(pc) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                }

                FeedbackText(text: s.feedback, kind: s.feedbackKind).padding(.bottom, 10)

                HStack(spacing: 10) {
                    GQButton("Hint", icon: "lightbulb.fill", style: .ghost, disabled: s.hintDisabled || s.locked || s.hint) { useHint() }
                    if s.showNext { GQButton("Next", style: .primary) { nextQuestion() } }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

                Card(padding: Theme.fretboardCardPadding) {
                    FretboardView(maxFret: s.fbMaxFret, interactive: s.game != "tab", marks: s.marks, highlightString: s.highlight, flashes: $flashes) { str, f in
                        answerPosition(str, f)
                    }
                }
            }
        }
    }

    private func padState(_ p: PadState?) -> PadButton.PadState {
        switch p { case .good: return .good; case .bad: return .bad; default: return .none }
    }

    @ViewBuilder private func hudProgress(_ s: GameState) -> some View {
        HStack(spacing: 10) {
            if s.mode == .blitz {
                Text("\(s.timeLeft)s").font(.system(size: 20, weight: .black)).foregroundStyle(s.timeLeft <= 10 ? Theme.bad : Theme.teal).frame(minWidth: 50, alignment: .leading)
            } else if let total = s.total {
                HStack(spacing: 4) {
                    ForEach(0..<total, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4).fill(i < s.answered ? Theme.teal : (i == s.q - 1 ? Theme.accent : Color(hex: 0xE6E0D5))).frame(width: 18, height: 8)
                    }
                }
                Text("Question \(min(s.q, total)) of \(total)").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - result

    private func result(_ r: Result) -> some View {
        let msg = r.stars == 3 ? "Amazing - three stars!" : r.stars == 2 ? "Well done!" : r.stars == 1 ? "Good start - keep going!" : "Practice makes perfect. Try again!"
        return HStack {
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { k in
                        Image(systemName: "star.fill").font(.system(size: 56)).foregroundStyle(k < r.stars ? Theme.gold : Color(hex: 0xDCD5C8))
                    }
                }
                Text(msg).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
                HStack(spacing: 28) {
                    stat("Score", String(r.score)); stat("Correct", "\(r.correct) / \(r.answered)"); stat("Best streak", String(r.bestStreak))
                }
                .padding(.vertical, 6)
                if !r.misses.isEmpty {
                    VStack(spacing: 6) {
                        Text("Notes to practise").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                        FlowLayout(hSpacing: 6, vSpacing: 6) {
                            ForEach(Array(r.misses.enumerated()), id: \.offset) { _, m in
                                HStack(spacing: 6) {
                                    NoteBadge(pc: Theory.mod(Theory.midiAt(m.0.string, m.0.fret), 12), settings: settings, small: true)
                                    Text("string \(m.0.string), fret \(m.0.fret)").font(.system(size: 13, weight: .semibold))
                                }
                                .padding(.vertical, 5).padding(.horizontal, 10)
                                .background(Color.white).clipShape(Capsule()).overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                HStack(spacing: 10) {
                    GQButton("Play again", style: .primary) { startGame(r.levelIdx) }
                    if r.levelIdx < GameData.LEVELS.count - 1 { GQButton("Next level") { startGame(r.levelIdx + 1) } }
                    GQButton("All levels", style: .ghost) { showLobby() }
                }
            }
            .padding(30)
            .frame(maxWidth: 640)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: Theme.shadow, radius: 9, y: 6)
            .padding(.vertical, 20)
            Spacer()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 28, weight: .black)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - flow

    private func later(_ ms: Int, _ fn: @escaping () -> Void) {
        let w = DispatchWorkItem(block: fn)
        timers.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: w)
    }
    private func clearTimers() {
        timers.forEach { $0.cancel() }; timers = []
        blitzTimer?.invalidate(); blitzTimer = nil
    }
    private func startBlitzTimer() {
        blitzTimer?.invalidate()
        blitzTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                guard st != nil else { return }
                st!.timeLeft -= 1
                if st!.timeLeft <= 0 { finish() }
            }
        }
    }

    private func teardown() {
        clearTimers()
        model.keyHandler = nil
        services?.clock.stop("quest")
    }

    private func showLobby() {
        teardown()
        st = nil
        phase = .lobby
        installKeys()
    }

    private func startGame(_ levelIdx: Int) {
        // replaying from a game or the result screen keeps that game's mode/options; from the lobby use the lobby choices
        var game = lobbyGame, mode = lobbyMode, staffToo = lobbyStaffToo
        if let old = st, !isLobby { game = old.game; mode = old.mode; staffToo = old.staffToo }
        teardown()
        let level = GameData.LEVELS[levelIdx]
        let s = GameState(game: game, mode: mode, staffToo: staffToo, levelIdx: levelIdx, level: level, pool: level.pool,
                          total: mode == .round ? 10 : nil)
        st = s
        phase = .playing
        installKeys()
        services?.clock.start("quest")
        if s.mode == .blitz { startBlitzTimer() }
        nextQuestion()
    }

    private var isLobby: Bool { if case .lobby = phase { return true } else { return false } }

    private func weightOf(_ p: Position) -> Double {
        guard let info = store.positionInfo(p.string, p.fret), !info.recent.isEmpty else { return 2 }
        let acc = Double(info.recent.reduce(0, +)) / Double(info.recent.count)
        return 1 + 3 * (1 - acc)
    }
    private func pickPosition(_ s: GameState) -> Position {
        let cands = s.pool.filter { p in s.last == nil || p.string != s.last!.string || p.fret != s.last!.fret }
        let weights = cands.map(weightOf)
        var r = Double.random(in: 0..<1) * weights.reduce(0, +)
        for i in cands.indices { r -= weights[i]; if r <= 0 { return cands[i] } }
        return cands[cands.count - 1]
    }

    private func nextQuestion() {
        guard var s = st else { return }
        clearTimers()
        if s.mode == .blitz && s.timeLeft > 0 { startBlitzTimer() }
        if let total = s.total, s.q >= total { finish(); return }
        s.q += 1
        s.locked = false; s.hint = false
        let pos = pickPosition(s)
        s.last = pos
        let midi = Theory.midiAt(pos.string, pos.fret), pc = Theory.mod(midi, 12)
        let spelled: SpelledNote
        if Theory.isNaturalPc(pc) { spelled = Theory.spellPc(pc) }
        else if s.game == "staff" { spelled = Theory.spellPc(pc, Bool.random() ? .sharp : .flat) }
        else { spelled = Theory.spellPc(pc, settings.spellPref) }
        s.cur = Question(pos: pos, midi: midi, pc: pc, spelled: spelled)
        s.showNext = false
        s.hintDisabled = false
        s.feedback = ""; s.feedbackKind = .none
        s.padStates = [:]
        s.marks = []
        s.highlight = s.game == "hunt" ? pos.string : nil
        s.staffReveal = "Any place that plays exactly this sound counts."
        st = s
    }

    // MARK: - answers

    private func answerPc(_ pc: Int) {
        guard let s = st, !s.locked, let c = s.cur else { return }
        result(correct: pc == c.pc, pickedPc: pc, pos: nil)
    }

    private func answerPosition(_ str: Int, _ f: Int) {
        guard let s = st, !s.locked, s.game != "tab", let c = s.cur else { return }
        if s.game == "hunt" {
            if str != c.pos.string {
                model.toast("Use string \(c.pos.string) (\(Theory.OPEN_NAMES[c.pos.string].uppercased())) - the highlighted one.")
                return
            }
            result(correct: Theory.mod(Theory.midiAt(str, f), 12) == c.pc, pickedPc: nil, pos: Position(string: str, fret: f))
        } else {
            result(correct: Theory.midiAt(str, f) == c.midi, pickedPc: nil, pos: Position(string: str, fret: f))
        }
    }

    private func mark(_ string: Int, _ fret: Int, spelled: SpelledNote? = nil, kind: MarkKind = .note, opacity: Double = 1, pop: Bool = false) -> FretMark {
        var m = FretMark.note(string, fret, settings: settings, spelled: spelled, kind: kind)
        m.opacity = opacity; m.pop = pop
        return m
    }

    private func result(correct: Bool, pickedPc: Int?, pos: Position?) {
        guard var s = st, let c = s.cur else { return }
        s.locked = true
        blitzTimer?.invalidate(); blitzTimer = nil
        s.answered += 1
        store.recordAnswer(c.pos.string, c.pos.fret, correct)
        s.hintDisabled = true
        let name = Theory.noteLabel(c.spelled, nm)
        if correct {
            s.correct += 1; s.streak += 1
            s.bestStreak = max(s.bestStreak, s.streak)
            store.recordStreak(s.streak)
            let pts = s.hint ? 5 : 10 + (s.streak >= 3 ? 5 : 0)
            s.score += pts
            if let pc = pickedPc { s.padStates[pc] = .good }
            let str = pos?.string ?? c.pos.string, f = pos?.fret ?? c.pos.fret
            s.marks = [mark(str, f, spelled: c.spelled, kind: .root, pop: true)]
            flashes.append(FretFlash(string: str, fret: f, good: true, start: Date()))
            services?.audio.pluck(Theory.midiAt(str, f), when: 0, duration: 1.2)
            let cheers = ["Great!", "Yes!", "Correct!", "Nice one!", "Super!", "You got it!"]
            let explain = s.game == "tab" ? "Fret \(c.pos.fret) on string \(c.pos.string) is \(name)." : "\(name) = string \(str), fret \(f)."
            s.feedback = cheers.randomElement()! + " " + explain + "  +\(pts)" + (s.streak >= 3 ? " (streak bonus!)" : "")
            s.feedbackKind = .good
            st = s
            later(s.mode == .blitz ? 650 : 1300) { nextQuestion() }
        } else {
            s.streak = 0
            let key = "\(c.pos.string):\(c.pos.fret)"
            s.misses[key, default: 0] += 1
            if let pc = pickedPc { s.padStates[pc] = .bad }
            if s.game == "tab" { s.padStates[c.pc] = .good }
            var marks: [FretMark] = []
            if s.game == "staff" {
                for p in Theory.positionsOfMidi(c.midi, s.fbMaxFret) { marks.append(mark(p.string, p.fret, spelled: c.spelled, kind: .root, pop: true)) }
            } else if s.game == "hunt" {
                for f in 0...s.fbMaxFret where Theory.mod(Theory.midiAt(c.pos.string, f), 12) == c.pc {
                    marks.append(mark(c.pos.string, f, spelled: c.spelled, kind: .root, pop: true))
                }
            } else {
                marks.append(mark(c.pos.string, c.pos.fret, spelled: c.spelled, kind: .root, pop: true))
            }
            if let p = pos {
                marks.append(mark(p.string, p.fret, kind: .ghost, opacity: 0.5))
                flashes.append(FretFlash(string: p.string, fret: p.fret, good: false, start: Date()))
            }
            s.marks = marks
            if let audio = services?.audio { audio.pluck(c.midi, when: audio.now + 0.15, duration: 1.2) }
            s.feedback = explainWrong(s, c, pickedPc: pickedPc, pos: pos)
            s.feedbackKind = .bad
            if s.mode == .blitz { st = s; later(1600) { nextQuestion() } }
            else { s.showNext = true; st = s }
        }
    }

    private func ladderText(_ string: Int, _ fret: Int) -> String {
        let open = Theory.TUNING[string]
        let pref = settings.spellPref
        let openName = Theory.OPEN_NAMES[string].uppercased()
        if fret == 0 { return "0 means the string is played open (no finger), and string \(string) open is \(openName)." }
        if fret <= 7 {
            let steps = (1...fret).map { Theory.pcLabel(Theory.mod(open + $0, 12), nm, pref) }
            return "String \(string) is \(openName). Count up \(fret)" + (fret == 1 ? " fret: " : " frets: ") + steps.joined(separator: ", ") + "."
        }
        var steps: [String] = []
        if fret <= 12 {
            if fret <= 11 { for f in stride(from: 11, through: fret, by: -1) { steps.append(Theory.pcLabel(Theory.mod(open + f, 12), nm, pref)) } }
        } else {
            for f in 13...fret { steps.append(Theory.pcLabel(Theory.mod(open + f, 12), nm, pref)) }
        }
        return "Fret 12 is \(openName) again." + (steps.isEmpty ? "" : " Then " + (fret < 12 ? "back" : "up") + ": " + steps.joined(separator: ", ") + ".")
    }

    private func explainWrong(_ s: GameState, _ c: Question, pickedPc: Int?, pos: Position?) -> String {
        let name = Theory.noteLabel(c.spelled, nm)
        if s.game == "tab" {
            let picked = Theory.pcLabel(pickedPc ?? 0, nm, .both)
            return "Not \(picked). " + ladderText(c.pos.string, c.pos.fret) + " So it is \(name)."
        }
        let got = Theory.midiAt(pos!.string, pos!.fret)
        if s.game == "staff" {
            if Theory.mod(got, 12) == c.pc {
                return "Right letter, wrong octave! \(name) on the staff is a " + (got > c.midi ? "lower" : "higher") + " \(name). The marked places are correct."
            }
            return "That was \(Theory.pcLabel(Theory.mod(got, 12), nm, .both)). This note is \(name) - it lives at the marked places."
        }
        return "That was \(Theory.pcLabel(Theory.mod(got, 12), nm, .both)). \(name) on string \(c.pos.string) is at the marked fret."
    }

    private func useHint() {
        guard var s = st, !s.locked, !s.hint, let c = s.cur else { return }
        s.hint = true
        if s.game == "tab" {
            var marks: [FretMark] = []
            let from = c.pos.fret <= 7 ? 0 : 12
            let lo = min(from, c.pos.fret), hi = max(from, c.pos.fret)
            for f in lo...hi {
                if f == c.pos.fret { marks.append(FretMark(string: c.pos.string, fret: f, label: "?", color: Theme.ink, kind: .target)) }
                else { marks.append(mark(c.pos.string, f, opacity: 0.8)) }
            }
            s.marks = marks
            s.highlight = c.pos.string
            s.feedback = "Hint: count fret by fret from " + (from == 0 ? "the open string" : "fret 12") + ". (Hints give 5 points.)"
            s.feedbackKind = .hint
        } else if s.game == "staff" {
            s.staffReveal = "Hint: this note is \(Theory.noteLabel(c.spelled, nm)). (Hints give 5 points.)"
        } else {
            var marks: [FretMark] = []
            for f in 0...s.fbMaxFret {
                let pc = Theory.mod(Theory.midiAt(c.pos.string, f), 12)
                if Theory.isNaturalPc(pc) && pc != c.pc { marks.append(mark(c.pos.string, f, opacity: 0.8)) }
            }
            s.marks = marks
            s.feedback = "Hint: the other natural notes on this string are shown. Your note is in one of the gaps or empty frets. (Hints give 5 points.)"
            s.feedbackKind = .hint
        }
        st = s
    }

    private func finish() {
        clearTimers()
        guard let s = st else { return }
        let acc = s.answered > 0 ? Double(s.correct) / Double(s.answered) : 0
        let stars: Int
        if s.mode == .blitz { stars = s.correct >= 20 ? 3 : s.correct >= 12 ? 2 : s.correct >= 6 ? 1 : 0 }
        else { stars = acc >= 0.9 ? 3 : acc >= 0.7 ? 2 : acc >= 0.5 ? 1 : 0 }
        store.recordLevel(s.game, s.level.id, stars: stars, score: s.score)
        services?.clock.stop("quest")
        model.keyHandler = nil
        let misses = s.misses.sorted { $0.value > $1.value }.prefix(4).map { kv -> (Position, Int) in
            let parts = kv.key.split(separator: ":").map { Int($0)! }
            return (Position(string: parts[0], fret: parts[1]), kv.value)
        }
        phase = .finished(Result(stars: stars, score: s.score, correct: s.correct, answered: s.answered, bestStreak: s.bestStreak, misses: misses, levelIdx: s.levelIdx))
        if stars > 0 { services?.audio.chime(true) }
    }

    // MARK: - keyboard

    private func installKeys() {
        model.keyHandler = { press in
            guard case .playing = phase, let s = st else { return .ignored }
            if (press.key == .return || press.key == .space), s.showNext { nextQuestion(); return .handled }
            if s.game == "tab", !s.locked, !s.level.acc, let ch = press.characters.uppercased().first, let l = Theory.LETTERS.firstIndex(of: String(ch)) {
                answerPc(Theory.LETTER_PC[l]); return .handled
            }
            return .ignored
        }
    }
}

// MARK: - big tab question

private struct BigTab: View {
    let string: Int
    let fret: Int
    var body: some View {
        let W = 340.0, top = 22.0, gap = 22.0
        let H = top * 2 + gap * 5
        Canvas { ctx, size in
            let s = size.width / W
            ctx.scaleBy(x: s, y: s)
            for st in 1...6 {
                let y = top + Double(st - 1) * gap
                ctx.draw(Text(Theory.OPEN_NAMES[st]).font(.system(size: 14, weight: .heavy)).foregroundColor(Color(hex: 0x9AA0AD)), at: CGPoint(x: 14, y: y), anchor: .center)
                var p = Path(); p.move(to: CGPoint(x: 30, y: y)); p.addLine(to: CGPoint(x: W - 10, y: y))
                ctx.stroke(p, with: .color(st == string ? Theme.ink : Color(hex: 0x8E94A3)), lineWidth: st == string ? 2 : 1.4)
            }
            for (k, c) in ["T", "A", "B"].enumerated() {
                let y = top + gap * (1.5 + Double(k) * 1.1) + 2 - 6
                ctx.fill(Path(roundedRect: CGRect(x: 52 - 9, y: y - 10, width: 18, height: 20), cornerRadius: 5), with: .color(.white))
                ctx.draw(Text(c).font(.system(size: 18, weight: .black)).foregroundColor(Color(hex: 0x2B2F3A)), at: CGPoint(x: 52, y: y), anchor: .center)
            }
            let y = top + Double(string - 1) * gap, x = 200.0, w = 16 * Double(String(fret).count) + 12
            let box = Path(roundedRect: CGRect(x: x - w / 2, y: y - 14, width: w, height: 28), cornerRadius: 6)
            ctx.fill(box, with: .color(Color(hex: 0xFFF3EC)))
            ctx.stroke(box, with: .color(Theme.accent), lineWidth: 2)
            ctx.draw(Text(String(fret)).font(.system(size: 24, weight: .black)).foregroundColor(Theme.accentDark), at: CGPoint(x: x, y: y), anchor: .center)
        }
        .aspectRatio(W / H, contentMode: .fit)
    }
}

// MARK: - game card art

private struct GameArt: View {
    let id: String
    var body: some View {
        Canvas { ctx, size in
            let s = size.height / 60
            ctx.scaleBy(x: s, y: s)
            func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ c: Color, _ w: Double) {
                var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2)); ctx.stroke(p, with: .color(c), lineWidth: w)
            }
            if id == "tab" {
                for y in [10.0, 18, 26, 34, 42, 50] { line(6, y, 114, y, Color(hex: 0x9AA0AD), 1.4) }
                ctx.fill(Path(CGRect(x: 52, y: 19, width: 16, height: 14)), with: .color(.white))
                ctx.draw(Text("2").font(.system(size: 14, weight: .heavy)).foregroundColor(Theme.ink), at: CGPoint(x: 60, y: 26), anchor: .center)
                ctx.draw(Text("= ?").font(.system(size: 14, weight: .heavy)).foregroundColor(Theme.accent), at: CGPoint(x: 96, y: 26), anchor: .leading)
            } else if id == "staff" {
                for y in [14.0, 22, 30, 38, 46] { line(6, y, 114, y, Color(hex: 0x9AA0AD), 1.2) }
                let t = CGAffineTransform(translationX: 60, y: 26).rotated(by: -22 * .pi / 180).translatedBy(x: -60, y: -26)
                ctx.fill(Path(ellipseIn: CGRect(x: 54, y: 21.6, width: 12, height: 8.8)).applying(t), with: .color(Color(hex: 0x5E35B1)))
                line(65.5, 26, 65.5, 2, Theme.ink, 1.4)
            } else {
                ctx.fill(Path(roundedRect: CGRect(x: 6, y: 8, width: 108, height: 44), cornerRadius: 4), with: .color(Color(hex: 0x5A371B)))
                for (k, y) in [14.0, 21, 28, 35, 42, 49].enumerated() { line(6, y, 114, y, k == 2 ? Color(hex: 0xFFD27A) : Color(hex: 0xD9D2C3), k == 2 ? 2.4 : 1.1) }
                for x in [30.0, 52, 72, 90, 106] { line(x, 8, x, 52, Color(hex: 0xC9C9C9), 1.6) }
                ctx.fill(Path(ellipseIn: CGRect(x: 55.5, y: 21.5, width: 13, height: 13)), with: .color(Color(hex: 0x0097A7)))
            }
        }
        .aspectRatio(2, contentMode: .fit)
    }
}

// MARK: - standalone snapshot (debug aid; GQ_QUEST_SNAPSHOT=/dir renders this screen alone to /dir/quest-<state>.png)

@MainActor
private enum QuestSnapshot {
    nonisolated(unsafe) static var done = false
    static func runIfRequested() {
        guard !done, let dir = ProcessInfo.processInfo.environment["GQ_QUEST_SNAPSHOT"], !dir.isEmpty else { return }
        done = true
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gq-quest-snapshot.json")
        let store = ProgressStore(fileURL: tmp)
        let model = AppModel()
        let services = Services(store: store, audio: AudioEngine(volume: 0), clock: PracticeClock(store: store), model: model)
        let state = ProcessInfo.processInfo.environment["GQ_QUEST_DEBUG"] ?? "lobby"
        let content = QuestView()
            .environment(store).environment(model).environment(\.services, services)
            .padding(22)
            .frame(width: 1280)
            .background(Theme.bg)
        let r = ImageRenderer(content: content)
        r.scale = 1
        r.proposedSize = ProposedViewSize(width: 1280, height: nil)
        if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("quest-\(state).png"))
            print("quest snapshot: quest-\(state).png \(cg.width)x\(cg.height)")
        }
    }
}
