// My Progress: practice time, accuracy, fretboard mastery map and level stars. Port of web/js/views/progress.js.
import SwiftUI
import MusicCore

struct ProgressView_: View {
    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @State private var askReset = false
    @State private var debugData: ProgressData? = nil

    init() {
        // snapshot aid: GQ_PROGRESS_DEBUG=1 shows fake progress (never written to the store)
        if ProcessInfo.processInfo.environment["GQ_PROGRESS_DEBUG"] != nil { _debugData = State(initialValue: Self.fakeData()) }
        StandaloneSnapshot.renderIfRequested("progress") { AnyView(ProgressView_()) }
    }

    private var data: ProgressData { debugData ?? store.data }

    var body: some View {
        let _ = model.settingsVersion
        let d = data
        let q = d.quest, p = d.practice
        VStack(alignment: .leading, spacing: 16) {
            ViewHead(title: "My Progress", lead: "Little and often wins: 15 minutes a day is better than one long session a week.")
                .padding(.bottom, -16)
            statGrid(q, p)
            chartCard(p)
            mapCard(q)
            starsCard
            theoryCard(d.theory)
            HStack { Spacer(); GQButton("Reset all progress", style: .ghost, small: true) { askReset = true } }
        }
        .alert("Delete all progress, stars and practice time on this computer?", isPresented: $askReset) {
            Button("Delete", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - stats

    private func day(_ offset: Int) -> String {
        ProgressStore.today(Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date())
    }

    private func statGrid(_ q: QuestData, _ p: [String: Int]) -> some View {
        // day streak: consecutive days with ≥ 60 s; today counts only once it has ≥ 60 s
        var streak = 0
        var off = (p[day(0)] ?? 0) >= 60 ? 0 : 1
        while (p[day(off)] ?? 0) >= 60 { streak += 1; off += 1 }
        let todayMin = Int((Double(p[day(0)] ?? 0) / 60).rounded())
        let weekSec = (0..<7).reduce(0) { $0 + (p[day($1)] ?? 0) }
        let acc = q.answered > 0 ? Int((100.0 * Double(q.correct) / Double(q.answered)).rounded()) : 0
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            bigStat("\(todayMin) min", "practised today")
            bigStat("\(Int((Double(weekSec) / 60).rounded())) min", "this week")
            bigStat("\(streak) " + (streak == 1 ? "day" : "days"), "practice streak", icon: "flame.fill", color: Theme.accent)
            bigStat(String(q.answered), "notes answered")
            bigStat("\(acc)%", "correct")
            bigStat(String(q.bestStreak), "best answer streak", icon: "star.fill", color: Theme.gold)
        }
    }

    private func bigStat(_ value: String, _ label: String, icon: String? = nil, color: Color = Theme.accent) -> some View {
        Card {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.system(size: 26, weight: .black)).foregroundStyle(Theme.ink)
                    Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let icon {
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).offset(x: 4, y: -4)
                }
            }
        }
    }

    // MARK: - 14-day chart

    private func chartCard(_ p: [String: Int]) -> some View {
        let days = (0..<14).reversed().map { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) ?? Date() }
        let mins = days.map { Double(p[ProgressStore.today($0)] ?? 0) / 60 }
        let maxM = max(15, mins.max() ?? 0)
        let names = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        return Card {
            H3("Practice minutes - last 14 days")
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, t in
                    let m = mins[i]
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(m >= 1 ? String(Int(m.rounded())) : " ").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.muted)
                        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 6)
                            .fill(m >= 15 ? Theme.good : Color(hex: 0xCFC6B6))
                            .frame(maxWidth: 40)
                            .frame(height: max(2, m / maxM * 120))
                        Text(names[Calendar.current.component(.weekday, from: t) - 1]).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(Int(m.rounded())) min")
                }
            }
            .frame(height: 170)
            .padding(.top, 18)
            SmallText("Green bars reached the 15-minute goal. Time counts while a Note Quest round, the Studio or the Jam is running.", muted: true)
                .padding(.top, 6)
        }
    }

    // MARK: - fretboard map

    private func mapCard(_ q: QuestData) -> some View {
        var marks: [FretMark] = []
        for s in 1...6 {
            for f in 0...12 {
                let pc = Theory.mod(Theory.midiAt(s, f), 12)
                let label = Theory.pcLabel(pc, .letters, .sharp)
                guard let info = q.positions["\(s):\(f)"], info.seen > 0 else {
                    marks.append(FretMark(string: s, fret: f, label: "", color: .white.opacity(0.18), kind: .note))
                    continue
                }
                let r = info.recentAccuracy ?? 0
                let color: Color = r >= 0.8 ? Color(hex: 0x2E9E5B) : r >= 0.5 ? Color(hex: 0xF29B30) : Color(hex: 0xD64545)
                marks.append(FretMark(string: s, fret: f, label: label, color: color, textColor: .white, kind: .note))
            }
        }
        return Card {
            H3("Fretboard map")
            SmallText("Every Note Quest answer colours its fret: green = you know it, orange = getting there, red = needs practice, grey = not tried yet.", muted: true)
                .padding(.bottom, 8)
            FretboardView(maxFret: 12, compact: true, interactive: false, marks: marks)
        }
    }

    // MARK: - stars table

    private var starsCard: some View {
        let games = GameData.GAMES, levels = GameData.LEVELS
        let total = levels.reduce(0) { acc, l in acc + games.reduce(0) { $0 + levelInfo($1.id, l.id).stars } }
        return Card {
            H3("Note Quest stars")
            SmallText("\(total) of \(levels.count * games.count * 3) stars collected.")
                .padding(.bottom, 6)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
                GridRow {
                    header("Level")
                    ForEach(games) { g in header(g.name) }
                }
                ForEach(levels) { l in
                    Divider().gridCellUnsizedAxes(.horizontal).gridCellColumns(games.count + 1).overlay(Theme.soft)
                    GridRow {
                        Text(l.name).font(.system(size: 14)).foregroundStyle(Theme.ink).padding(.vertical, 7)
                        ForEach(games) { g in Stars(count: levelInfo(g.id, l.id).stars, size: 17).padding(.vertical, 7) }
                    }
                }
            }
        }
    }

    private func levelInfo(_ game: String, _ level: String) -> LevelInfo { data.quest.levels["\(game):\(level)"] ?? LevelInfo() }

    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .semibold)).kerning(0.6).foregroundStyle(Theme.muted).padding(.vertical, 7)
    }

    // MARK: - theory

    private func theoryCard(_ th: TheoryData) -> some View {
        Card {
            H3("Theory games")
            if th.answered > 0 {
                Text("\(th.correct) of \(th.answered) theory questions correct (\(Int((100.0 * Double(th.correct) / Double(th.answered)).rounded()))%).")
                    .foregroundStyle(Theme.ink)
            } else {
                Text("No theory games played yet - try them in Chords & Harmony.").foregroundStyle(Theme.ink)
            }
        }
    }

    // MARK: - debug data

    private static func fakeData() -> ProgressData {
        var d = ProgressData()
        for i in 0..<10 {
            let key = ProgressStore.today(Calendar.current.date(byAdding: .day, value: -i, to: Date())!)
            d.practice[key] = [900, 1200, 300, 0, 1100, 950, 60, 1300, 400, 1000][i]
        }
        var rng = SeededRNG(seed: 7)
        for s in 1...6 { for f in 0...12 where Int.random(in: 0..<3, using: &rng) > 0 {
            var p = PositionInfo(); p.seen = 5; p.correct = Int.random(in: 1...5, using: &rng)
            p.recent = (0..<5).map { _ in Int.random(in: 0...1, using: &rng) }
            d.quest.positions["\(s):\(f)"] = p
        } }
        d.quest.answered = 124; d.quest.correct = 101; d.quest.bestStreak = 14
        for (k, v) in [("tab:s12", 3), ("tab:s34", 2), ("staff:s12", 1), ("hunt:first", 3), ("tab:first", 2)] {
            var l = LevelInfo(); l.stars = v; l.best = 100; l.plays = 2; d.quest.levels[k] = l
        }
        d.theory.answered = 20; d.theory.correct = 16
        return d
    }
}
