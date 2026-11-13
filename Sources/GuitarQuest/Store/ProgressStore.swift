// Progress and settings. Same JSON shape as the web app's localStorage key `guitarQuest.v1`
// (see docs/05_DATA_AND_PROGRESS.md), so a Windows export can be imported unchanged.
import Foundation
import Observation
import MusicCore

struct Settings: Codable, Equatable {
    var naming: Naming = .letters
    var accidentals: AccidentalPref = .sharp
    var colors: Bool = true
    var volume: Double = 0.8

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        naming = (try? c.decodeIfPresent(Naming.self, forKey: .naming)) ?? .letters
        accidentals = (try? c.decodeIfPresent(AccidentalPref.self, forKey: .accidentals)) ?? .sharp
        colors = (try? c.decodeIfPresent(Bool.self, forKey: .colors)) ?? true
        volume = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? 0.8
    }
}

struct LevelInfo: Codable, Equatable {
    var stars = 0
    var best = 0
    var plays = 0
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stars = (try? c.decodeIfPresent(Int.self, forKey: .stars)) ?? 0
        best = (try? c.decodeIfPresent(Int.self, forKey: .best)) ?? 0
        plays = (try? c.decodeIfPresent(Int.self, forKey: .plays)) ?? 0
    }
}

struct PositionInfo: Codable, Equatable {
    var seen = 0
    var correct = 0
    var recent: [Int] = []
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seen = (try? c.decodeIfPresent(Int.self, forKey: .seen)) ?? 0
        correct = (try? c.decodeIfPresent(Int.self, forKey: .correct)) ?? 0
        recent = (try? c.decodeIfPresent([Int].self, forKey: .recent)) ?? []
    }
    /// Accuracy of the last 5 answers (falls back to the all-time ratio).
    var recentAccuracy: Double? {
        if !recent.isEmpty { return Double(recent.reduce(0, +)) / Double(recent.count) }
        return seen > 0 ? Double(correct) / Double(seen) : nil
    }
}

struct QuestData: Codable, Equatable {
    var levels: [String: LevelInfo] = [:]
    var positions: [String: PositionInfo] = [:]
    var answered = 0
    var correct = 0
    var bestStreak = 0
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levels = (try? c.decodeIfPresent([String: LevelInfo].self, forKey: .levels)) ?? [:]
        positions = (try? c.decodeIfPresent([String: PositionInfo].self, forKey: .positions)) ?? [:]
        answered = (try? c.decodeIfPresent(Int.self, forKey: .answered)) ?? 0
        correct = (try? c.decodeIfPresent(Int.self, forKey: .correct)) ?? 0
        bestStreak = (try? c.decodeIfPresent(Int.self, forKey: .bestStreak)) ?? 0
    }
}

struct TheoryData: Codable, Equatable {
    var answered = 0
    var correct = 0
    var best: [String: Int] = [:]
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answered = (try? c.decodeIfPresent(Int.self, forKey: .answered)) ?? 0
        correct = (try? c.decodeIfPresent(Int.self, forKey: .correct)) ?? 0
        best = (try? c.decodeIfPresent([String: Int].self, forKey: .best)) ?? [:]
    }
}

struct ProgressData: Codable, Equatable {
    var settings = Settings()
    var quest = QuestData()
    var theory = TheoryData()
    var practice: [String: Int] = [:]   // "YYYY-MM-DD" -> seconds

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
        quest = (try? c.decodeIfPresent(QuestData.self, forKey: .quest)) ?? QuestData()
        theory = (try? c.decodeIfPresent(TheoryData.self, forKey: .theory)) ?? TheoryData()
        // the web app stores rounded seconds, but accept fractions too
        let p = (try? c.decodeIfPresent([String: Double].self, forKey: .practice)) ?? [:]
        practice = p.mapValues { Int(($0).rounded()) }
    }

    /// Minimal shape check for an import: an object with at least one of the known top-level keys.
    static func looksValid(_ json: Any) -> Bool {
        guard let d = json as? [String: Any] else { return false }
        return ["settings", "quest", "theory", "practice"].contains { d[$0] != nil }
    }
}

@Observable
final class ProgressStore {
    private(set) var data: ProgressData
    let fileURL: URL
    private var saveWork: DispatchWorkItem?

    static let defaultURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("GuitarQuest", isDirectory: true).appendingPathComponent("progress.json")
    }()

    init(fileURL: URL = ProgressStore.defaultURL) {
        self.fileURL = fileURL
        data = ProgressData()
        load()
    }

    var settings: Settings { data.settings }

    func load() {
        if let raw = try? Data(contentsOf: fileURL), let d = try? JSONDecoder().decode(ProgressData.self, from: raw) {
            data = d
        } else {
            data = ProgressData()
        }
    }

    /// Debounced (250 ms) like the web app; `flush()` writes immediately.
    func save() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    func flush() {
        saveWork?.cancel(); saveWork = nil
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            try enc.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            // storage unavailable: run without saving (same as the web app)
        }
    }

    // MARK: settings
    func update(_ change: (inout Settings) -> Void) { change(&data.settings); save() }

    // MARK: quest
    static func today(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func recordAnswer(_ string: Int, _ fret: Int, _ correct: Bool) {
        let k = "\(string):\(fret)"
        var p = data.quest.positions[k] ?? PositionInfo()
        p.seen += 1
        if correct { p.correct += 1 }
        p.recent = Array((p.recent + [correct ? 1 : 0]).suffix(5))
        data.quest.positions[k] = p
        data.quest.answered += 1
        if correct { data.quest.correct += 1 }
        save()
    }
    func recordStreak(_ n: Int) { if n > data.quest.bestStreak { data.quest.bestStreak = n; save() } }
    func recordLevel(_ game: String, _ level: String, stars: Int, score: Int) {
        let k = "\(game):\(level)"
        var cur = data.quest.levels[k] ?? LevelInfo()
        cur.stars = max(cur.stars, stars)
        cur.best = max(cur.best, score)
        cur.plays += 1
        data.quest.levels[k] = cur
        save()
    }
    func levelInfo(_ game: String, _ level: String) -> LevelInfo { data.quest.levels["\(game):\(level)"] ?? LevelInfo() }
    func positionInfo(_ string: Int, _ fret: Int) -> PositionInfo? { data.quest.positions["\(string):\(fret)"] }

    // MARK: theory games
    func recordTheory(_ game: String, _ correct: Bool) {
        data.theory.answered += 1
        if correct { data.theory.correct += 1 }
        save()
    }
    func recordTheoryBest(_ key: String, _ streak: Int) {
        if streak > (data.theory.best[key] ?? 0) { data.theory.best[key] = streak; save() }
    }

    // MARK: practice clock
    func addPractice(_ seconds: Double) {
        guard seconds > 0 else { return }
        let d = ProgressStore.today()
        data.practice[d] = Int((Double(data.practice[d] ?? 0) + seconds).rounded())
        save()
    }

    // MARK: reset / import / export
    func reset() {
        let keep = data.settings
        data = ProgressData()
        data.settings = keep
        try? FileManager.default.removeItem(at: fileURL)
        flush()
    }

    var hasProgress: Bool {
        data.quest.answered > 0 || !data.quest.levels.isEmpty || data.theory.answered > 0 || !data.practice.isEmpty
    }

    enum ImportError: Error, LocalizedError {
        case unreadable, badShape
        var errorDescription: String? {
            switch self {
            case .unreadable: return "The file could not be read."
            case .badShape: return "This is not a Guitar Quest progress file."
            }
        }
    }

    /// Validates and decodes a progress file (does not apply it).
    static func readProgress(from url: URL) throws -> ProgressData {
        guard let raw = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        guard let json = try? JSONSerialization.jsonObject(with: raw), ProgressData.looksValid(json),
              let d = try? JSONDecoder().decode(ProgressData.self, from: raw) else { throw ImportError.badShape }
        return d
    }

    func replace(with imported: ProgressData) {
        data = imported
        flush()
    }

    func export(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(data).write(to: url, options: .atomic)
    }
}
