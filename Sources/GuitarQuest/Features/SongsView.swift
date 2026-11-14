// Songs: the song library (imported tabs + backing tracks) and the Song Player. See SongPlayerView.swift / SongPlayerController.swift.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MusicCore

struct SongsView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services

    @State private var controller: SongPlayerController?
    @State private var importError: String?
    @State private var confirmDelete: SongEntry?
    @State private var debugLibrary: SongLibrary?
    @State private var debugServices: Services?

    init() {
        // Debug aids for snapshots: GQ_SONGS_DEBUG=player opens the first song; =tab opens a temporary library with the
        // MusicXML sample (never touches the real library).
        let env = ProcessInfo.processInfo.environment
        if let d = env["GQ_SONGS_DEBUG"] {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gq-songs-debug-\(UUID().uuidString).json")
            let st = ProgressStore(fileURL: tmp)
            let lib: SongLibrary
            if d == "tab" {
                lib = SongLibrary(folder: URL(fileURLWithPath: "/tmp/gq-songs", isDirectory: true))
                let sample = env["GQ_SONGS_DEBUG_FILE"] ?? (NSHomeDirectory() + "/Projects/GuitarQuest/Sources/GoldenCheck/Samples/mary.musicxml")
                if !lib.songs.contains(where: { $0.hasTab }) {
                    var e = SongEntry(title: "Mary Had a Little Lamb (sample)", artist: "Traditional")
                    e.mediaKind = .youtube; e.youtubeId = "b1FvLjvrGMI"
                    e.loopStart = 2; e.loopEnd = 4
                    e.anchors = [SyncAnchor(mediaTime: 12, tick: 0)]
                    lib.update(e)
                    _ = try? lib.importTab(from: URL(fileURLWithPath: sample), into: e)
                }
            } else {
                lib = SongLibrary()
            }
            let svc = Services(store: st, audio: AudioEngine(volume: 0), clock: PracticeClock(store: st), model: AppModel(), songs: lib)
            _debugLibrary = State(initialValue: lib)
            _debugServices = State(initialValue: svc)
            if let song = lib.songs.first(where: { d == "tab" ? $0.hasTab : true }) {
                let c = SongPlayerController(song: song, services: svc, library: lib)
                if let i = Int(env["GQ_SONGS_DEBUG_ACTIVE"] ?? "") { c.debugActive(i) }
                _controller = State(initialValue: c)
            }
        }
    }

    private var library: SongLibrary? { debugLibrary ?? services?.songs }

    var body: some View {
        let _ = model.settingsVersion
        Group {
            if let c = controller {
                SongPlayerView(controller: c, onBack: { closePlayer() })
            } else {
                libraryView
            }
        }
        .onDisappear { closePlayer() }
    }

    private func closePlayer() {
        controller?.shutdown()
        controller = nil
        model.keyHandler = nil
    }

    private func open(_ song: SongEntry) {
        guard let services, let library else { return }
        var s = song
        s.lastOpened = Date()
        library.update(s)
        controller = SongPlayerController(song: s, services: services, library: library)
    }

    // MARK: - library

    private var libraryView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewHead(title: "Songs", lead: "Your songs: a tab, the video or recording it goes with, and the bars you are working on. Loop any part at any speed.")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        GQButton("Import tab…", icon: "square.and.arrow.down", style: .primary) { importTab() }
                        GQButton("Add song (video only)", icon: "plus") { addEmptySong() }
                        Spacer()
                        SmallText("Tab files: Guitar Pro (.gp5, .gp4, .gp3, .gp), MusicXML (.musicxml, .xml, .mxl) or a PDF of the tab", muted: true)
                    }
                    if let importError {
                        Text(importError).font(.system(size: 13)).foregroundStyle(Theme.bad)
                    }
                }
            }
            .padding(.bottom, 16)
            if let library, !library.songs.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(library.songs.sorted { $0.lastOpened > $1.lastOpened }) { song in
                        SongCard(song: song, onOpen: { open(song) }, onDelete: { confirmDelete = song })
                    }
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        H3("No songs yet")
                        SmallText("Import a tab file, or add a song with just its video to loop parts of it while you practise.", muted: true)
                    }
                }
            }
            TipText("Where to get tabs: Guitar Pro files from Ultimate Guitar (community versions are free with an account) or Songsterr Plus, a MusicXML export from the teacher, or a PDF you bought (Musicnotes, Sheet Music Direct). Guitar Pro and MusicXML tabs follow the recording note by note; a PDF shows its pages and turns them for you.")
                .padding(.top, 16)
        }
        .alert("Delete this song?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) { if let s = confirmDelete { library?.remove(s) }; confirmDelete = nil }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("\(confirmDelete?.title ?? "") and its loop, anchors and imported tab file will be removed. The video or audio file itself is not deleted.")
        }
    }

    private func importTab() {
        guard let library else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gp5"), UTType(filenameExtension: "gp4"), UTType(filenameExtension: "gp3"), UTType(filenameExtension: "gp"), UTType(filenameExtension: "musicxml"), UTType(filenameExtension: "mxl"), .xml, .pdf].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Guitar Pro (.gp5 / .gp4 / .gp3 / .gp) or MusicXML (.musicxml / .xml / .mxl) tab, or a PDF of the tab"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.pathExtension.lowercased() == "pdf" {
            do {
                let song = try library.importPDF(from: url)
                importError = nil
                model.toast("PDF added: \(url.lastPathComponent)")
                open(song)
            } catch { importError = "\(error)" }
            return
        }
        do {
            let (song, piece) = try library.importTab(from: url)
            importError = nil
            model.toast("Imported \(piece.tracks.count == 1 ? "1 track" : "\(piece.tracks.count) tracks") from \(url.lastPathComponent)")
            open(song)
        } catch {
            importError = "\(error)"
        }
    }

    private func addEmptySong() {
        guard let library else { return }
        let s = SongEntry(title: "New song")
        library.update(s)
        open(s)
    }
}

// MARK: - card

struct SongCard: View {
    let song: SongEntry
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(song.title).font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1)
                    if !song.artist.isEmpty { Text(song.artist).font(.system(size: 14)).foregroundStyle(Theme.muted).lineLimit(1) }
                    Spacer()
                }
                HStack(spacing: 8) {
                    if song.hasTab { Tag(text: "Tab") }
                    if song.hasPDF { Tag(text: "PDF tab") }
                    if !song.hasTab && !song.hasPDF { Tag(text: "No tab yet") }
                    if song.mediaKind == .youtube && song.youtubeId != nil { Tag(text: "YouTube") }
                    if song.mediaKind == .file && song.mediaPath != nil { Tag(text: "Audio file") }
                    if let lr = song.loopRange { Tag(text: "Loop: bars \(lr.lowerBound + 1)–\(lr.upperBound + 1)") }
                    else if let a = song.mediaLoopA, let b = song.mediaLoopB { Tag(text: "Loop: \(SongPlayerController.clock(a))–\(SongPlayerController.clock(b))") }
                }
                if let name = song.tabOriginalName { SmallText("Tab: \(name)", muted: true) }
                else if let name = song.pdfOriginalName { SmallText("PDF: \(name)", muted: true) }
                else { SmallText("Import a tab to see it synced with the video.", muted: true) }
                if let t = song.youtubeTitle, !t.isEmpty { SmallText(t, muted: true).lineLimit(1) }
                HStack(spacing: 8) {
                    GQButton("Open", icon: "play.fill", style: .primary, small: true, action: onOpen)
                    GQButton("Delete", style: .ghost, small: true, action: onDelete)
                }
                .padding(.top, 4)
            }
        }
    }
}
