// The Song Player's library: imported tab files (MusicXML / Guitar Pro .gp .gp5 .gp4 .gp3) plus, per song, the backing track
// (local audio file or YouTube video), the sync anchors and the practice loop. Stored under
// ~/Library/Application Support/GuitarQuest/songs/ (library.json + one copy of each imported file).
import Foundation
import Observation
import MusicCore

enum MediaKind: String, Codable { case none, file, youtube }

struct SongEntry: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var artist: String = ""
    /// File name inside the songs folder (nil = no tab yet, video only).
    var tabFile: String? = nil
    /// Original file name, shown in the UI.
    var tabOriginalName: String? = nil
    var trackIndex: Int = 0
    var mediaKind: MediaKind = .none
    /// Local audio file: bookmark-free absolute path (family Mac, no sandbox). YouTube: the 11-character video id.
    var mediaPath: String? = nil
    var youtubeId: String? = nil
    var youtubeTitle: String? = nil
    var anchors: [SyncAnchor] = []
    /// Practice loop in measures (0-based, inclusive). nil = whole piece.
    var loopStart: Int? = nil
    var loopEnd: Int? = nil
    /// Playback speed of the backing track (0.25…2) and of the synth (percent of the written tempo).
    var mediaRate: Double = 1
    var synthPercent: Int = 100
    /// A/B loop in media seconds, used when the song has no tab (video looper) — kept separately from the bar loop.
    var mediaLoopA: Double? = nil
    var mediaLoopB: Double? = nil
    var loopOn: Bool = true
    /// Pluck the tab's notes while the backing track plays.
    var guitarAlong: Bool = false
    /// "backing" or "synth" — which clock drives the cursor.
    var playMode: String = "backing"
    var created: Date = Date()
    var lastOpened: Date = Date()

    var hasTab: Bool { tabFile != nil }
    var hasMedia: Bool { mediaKind == .youtube ? youtubeId != nil : mediaKind == .file ? mediaPath != nil : false }
    var loopRange: ClosedRange<Int>? {
        guard let a = loopStart, let b = loopEnd else { return nil }
        return min(a, b)...max(a, b)
    }
}

@Observable
final class SongLibrary {
    private(set) var songs: [SongEntry] = []
    let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("library.json") }

    static let defaultFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("GuitarQuest", isDirectory: true).appendingPathComponent("songs", isDirectory: true)
    }()

    init(folder: URL = SongLibrary.defaultFolder) {
        self.folder = folder
        load()
        seedIfEmpty()
    }

    /// First launch: the song the boy is learning right now, with the lesson video attached (tab to be imported).
    private func seedIfEmpty() {
        guard songs.isEmpty, !FileManager.default.fileExists(atPath: indexURL.path) else { return }
        var s = SongEntry(title: "Tornado of Souls", artist: "Megadeth")
        s.mediaKind = .youtube
        s.youtubeId = "b1FvLjvrGMI"
        s.youtubeTitle = "Megadeth - Tornado of Souls - Guitar Tab | Lesson | Cover | Tutorial (Mr. Tabs)"
        songs = [s]
        save()
    }

    func load() {
        if let d = try? Data(contentsOf: indexURL), let list = try? JSONDecoder().decode([SongEntry].self, from: d) { songs = list }
        else { songs = [] }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(songs).write(to: indexURL, options: .atomic)
        } catch { /* storage unavailable: keep running */ }
    }

    func update(_ song: SongEntry) {
        if let i = songs.firstIndex(where: { $0.id == song.id }) { songs[i] = song } else { songs.append(song) }
        save()
    }

    func remove(_ song: SongEntry) {
        songs.removeAll { $0.id == song.id }
        if let f = song.tabFile { try? FileManager.default.removeItem(at: folder.appendingPathComponent(f)) }
        save()
    }

    func fileURL(_ song: SongEntry) -> URL? { song.tabFile.map { folder.appendingPathComponent($0) } }

    // MARK: importing tab files

    enum TabFormat { case musicXML, compressedMusicXML, guitarPro7, guitarPro345, unsupported(String) }

    static func format(of url: URL) -> TabFormat {
        switch url.pathExtension.lowercased() {
        case "musicxml", "xml": return .musicXML
        case "mxl": return .compressedMusicXML
        case "gp": return .guitarPro7
        case "gpx": return .unsupported("Guitar Pro 6 (.gpx) files are not supported. Open the file in Guitar Pro or TuxGuitar and export it as .gp5, .gp or MusicXML.")
        case "gp3", "gp4", "gp5": return .guitarPro345
        case "ptb": return .unsupported("Power Tab files are not supported. Export as MusicXML.")
        default: return .unsupported("Unknown file type. Supported: Guitar Pro (.gp5 / .gp4 / .gp3 / .gp) and MusicXML (.musicxml / .xml / .mxl).")
        }
    }

    /// Reads and parses a tab file (without adding it to the library).
    static func parse(_ url: URL) throws -> ImportedPiece {
        switch format(of: url) {
        case .musicXML:
            return try ScoreImporter.importMusicXML(try Data(contentsOf: url))
        case .compressedMusicXML:
            // the container lists the root file; most exporters put a single .xml/.musicxml at the top level
            let names = try zipList(url)
            let container = names.contains("META-INF/container.xml") ? try zipRead(url, "META-INF/container.xml") : nil
            var root = names.first { $0.lowercased().hasSuffix(".xml") && !$0.hasPrefix("META-INF") } ?? names.first { $0.lowercased().hasSuffix(".musicxml") }
            if let c = container, let s = String(data: c, encoding: .utf8),
               let r = s.range(of: "full-path=\""), let e = s[r.upperBound...].firstIndex(of: "\"") {
                root = String(s[r.upperBound..<e])
            }
            guard let root else { throw ImportError.unsupported("The .mxl archive has no MusicXML file inside.") }
            return try ScoreImporter.importMusicXML(try zipRead(url, root))
        case .guitarPro7:
            return try ScoreImporter.importGPIF(try zipRead(url, "Content/score.gpif"))
        case .guitarPro345:
            return try ScoreImporter.importGP345(try Data(contentsOf: url))
        case .unsupported(let why):
            throw ImportError.unsupported(why)
        }
    }

    /// Copies the file into the library folder and creates the entry (or attaches the tab to an existing song).
    func importTab(from url: URL, into existing: SongEntry? = nil) throws -> (SongEntry, ImportedPiece) {
        let piece = try SongLibrary.parse(url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var song = existing ?? SongEntry(title: piece.title.isEmpty ? url.deletingPathExtension().lastPathComponent : piece.title, artist: piece.artist)
        if let old = song.tabFile { try? FileManager.default.removeItem(at: folder.appendingPathComponent(old)) }
        let name = song.id + "." + url.pathExtension.lowercased()
        let dest = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: url, to: dest)
        song.tabFile = name
        song.tabOriginalName = url.lastPathComponent
        song.trackIndex = 0
        if song.title.isEmpty { song.title = piece.title }
        if song.artist.isEmpty { song.artist = piece.artist }
        update(song)
        return (song, piece)
    }

    // MARK: zip helpers (system unzip; no third-party code)

    static func zipList(_ url: URL) throws -> [String] {
        let out = try run("/usr/bin/unzip", ["-Z1", url.path])
        return out.split(separator: "\n").map(String.init)
    }

    static func zipRead(_ url: URL, _ member: String) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", url.path, member]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, !data.isEmpty else { throw ImportError.unsupported("Could not read \(member) from the archive.") }
        return data
    }

    private static func run(_ exe: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
