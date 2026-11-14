// Song Player: one song = an imported tab (optional) + a backing track (YouTube / audio file, optional).
// The controller owns the two clocks — the media player (Backing track mode) and the synth Transport (Guitar sound
// mode) — maps media time to score ticks with SyncMap, runs the A/B loop and persists every change to the library.
import SwiftUI
import AppKit
import Observation
import PDFKit
import MusicCore

enum SongPlayMode: String { case backing, synth }

@Observable
@MainActor
final class SongPlayerController {
    let services: Services
    let library: SongLibrary
    private(set) var song: SongEntry

    // tab
    private(set) var piece: ImportedPiece? = nil
    private(set) var score: Score? = nil
    private(set) var tabError: String? = nil
    private(set) var syncMap: SyncMap? = nil
    private(set) var tempoTimeline: TempoTimeline? = nil

    // PDF tab
    private(set) var pdf: PDFDocument? = nil
    private(set) var pdfPage = 0
    private var lastManualPageChange = Date.distantPast
    /// When a song has both a Guitar Pro/MusicXML tab and a PDF: which one the tab card shows.
    var showPDF = false

    // media
    private(set) var player: MediaPlayerBase? = nil
    var mediaError: String? = nil
    private var rateApplied = false

    // synth
    let transport: Transport
    private var items: [TransportItem] = []

    // cursor
    private(set) var active: Int? = nil
    private(set) var next: Int? = nil
    private(set) var currentTick: Double? = nil      // media-derived tick (backing mode)
    private(set) var transportPosition = -1
    private(set) var countdown = 0
    private(set) var transportPlaying = false
    private(set) var seeking = false

    // loop editing: next tap sets A (true) or B (false)
    var tapSetsA = true
    var pendingAnchorBar = 1

    private var timer: Timer?
    private var clockRunning = false
    /// Snapshot aid: fixes the cursor on an event (GQ_SONGS_DEBUG_ACTIVE) and renders the score without a ScrollView.
    private(set) var isDebugActive = false
    func debugActive(_ i: Int) { isDebugActive = true; setActive(i) }

    var mode: SongPlayMode { SongPlayMode(rawValue: song.playMode) ?? .backing }

    init(song: SongEntry, services: Services, library: SongLibrary) {
        self.song = song
        self.services = services
        self.library = library
        transport = Transport(audio: services.audio)
        transport.loop = true
        transport.countIn = true
        transport.metronome = false
        transport.onPosition = { [weak self] idx, cd, _, seek in
            guard let self else { return }
            transportPosition = idx; countdown = cd; seeking = seek
            if mode == .synth { setActive(idx >= 0 ? idx : nil) }
        }
        transport.onState = { [weak self] p in
            guard let self else { return }
            transportPlaying = p
            if !p { countdown = 0 }
            updateClock()
        }
        loadTab()
        loadPDF()
        loadMedia()
        startTimer()
    }

    // MARK: - PDF tab

    func loadPDF() {
        pdf = nil; pdfPage = 0
        guard let url = library.pdfURL(song), let doc = PDFDocument(url: url), doc.pageCount > 0 else { return }
        pdf = doc
        if score == nil { showPDF = true }
    }

    func importPDF(from url: URL) {
        do {
            song = try library.importPDF(from: url, into: song)
            loadPDF()
            showPDF = true
            services.model.toast("PDF added: \(url.lastPathComponent)")
        } catch { tabError = "\(error)" }
    }

    func removePDF() {
        song = library.removePDF(from: song)
        pdf = nil; pdfPage = 0; showPDF = false
    }

    func userChangedPage(_ p: Int) {
        guard let doc = pdf else { return }
        let clamped = max(0, min(doc.pageCount - 1, p))
        if clamped != pdfPage { pdfPage = clamped }
        lastManualPageChange = Date()
    }

    /// Records "the recording is at the current second on the page shown now" (one anchor per page).
    func markPage() {
        guard let t = player?.currentTime else { return }
        change { s in
            s.pageAnchors.removeAll { $0.page == pdfPage || abs($0.mediaTime - t) < 0.5 }
            s.pageAnchors.append(PageAnchor(page: pdfPage, mediaTime: t))
            s.pageAnchors.sort { $0.mediaTime < $1.mediaTime }
        }
        services.model.toast("Page \(pdfPage + 1) marked at \(Self.clockPrecise(t))")
    }
    func removePageAnchor(_ page: Int) { change { $0.pageAnchors.removeAll { $0.page == page } } }
    func clearPageAnchors() { change { $0.pageAnchors = [] } }

    /// Auto page turn while the recording plays (not right after the user flipped a page by hand).
    private func followPDFPage(now: Double) {
        guard pdf != nil, !song.pageAnchors.isEmpty, Date().timeIntervalSince(lastManualPageChange) > 3 else { return }
        let due = song.pageAnchors.filter { $0.mediaTime <= now + 0.05 }.max { $0.mediaTime < $1.mediaTime }
        if let d = due, d.page != pdfPage { pdfPage = d.page }
    }

    // MARK: - persistence

    private func persist() { library.update(song) }

    func change(_ edit: (inout SongEntry) -> Void) {
        edit(&song)
        persist()
    }

    // MARK: - tab

    func loadTab() {
        piece = nil; score = nil; tabError = nil
        guard let url = library.fileURL(song) else { rebuildSync(); return }
        do {
            let p = try SongLibrary.parse(url)
            piece = p
            selectTrack(min(song.trackIndex, max(0, p.tracks.count - 1)), persistChange: false)
        } catch {
            tabError = "\(error)"
            rebuildSync()
        }
    }

    func selectTrack(_ index: Int, persistChange: Bool = true) {
        guard let p = piece, !p.tracks.isEmpty else { score = nil; rebuildSync(); return }
        let i = max(0, min(p.tracks.count - 1, index))
        if persistChange && i != song.trackIndex { change { $0.trackIndex = i } }
        score = p.tracks[i].score
        // keep the loop inside the piece
        if let sc = score, let b = song.loopEnd, b >= sc.measures.count { change { $0.loopStart = nil; $0.loopEnd = nil } }
        rebuildSync()
        rebuildTransport()
        setActive(nil)
    }

    func importTab(from url: URL) {
        do {
            let (updated, _) = try library.importTab(from: url, into: song)
            song = updated
            change { $0.loopStart = nil; $0.loopEnd = nil; $0.anchors = [] }
            loadTab()
            services.model.toast("Tab imported: \(url.lastPathComponent)")
        } catch {
            tabError = "\(error)"
        }
    }

    private func rebuildSync() {
        guard let sc = score else { syncMap = nil; tempoTimeline = nil; return }
        let tl = TempoTimeline(score: sc)
        tempoTimeline = tl
        syncMap = SyncMap(timeline: tl, anchors: song.anchors)
    }

    private func rebuildTransport() {
        transport.stop()
        guard let sc = score else { items = []; return }
        let base = Double(max(1, sc.tempo))
        items = Exercises.timeline(sc, baseTempo: base).map { TransportItem(i: $0.i, beat: $0.beat, beats: $0.beats, rest: $0.rest, midis: $0.midis) }
        let total = items.last.map { $0.beat + $0.beats } ?? 0
        transport.load(items, totalBeats: total, beatsPerBar: sc.time.first ?? 4)
        applyTransportSettings()
    }

    private func applyTransportSettings() {
        guard let sc = score else { return }
        transport.bpm = max(30, min(240, Int((Double(sc.tempo) * Double(song.synthPercent) / 100).rounded())))
        transport.loop = song.loopOn
        if let lr = song.loopRange, let startIdx = sc.eventIndex(atTick: sc.measureStart(lr.lowerBound)) {
            let endTick = sc.measureStart(lr.upperBound) + sc.measureLength(lr.upperBound)
            let endBeat = tempoTimeline.map { $0.seconds(atTick: endTick) * Double(max(1, sc.tempo)) / 60 }
            transport.setRange(startIndex: startIdx, endBeat: endBeat)
        } else {
            transport.setRange(startIndex: nil, endBeat: nil)
        }
    }

    var synthBPM: Int { transport.bpm }

    func setSynthPercent(_ pct: Int) {
        change { $0.synthPercent = max(25, min(150, pct)) }
        guard let sc = score else { return }
        let bpm = max(30, min(240, Int((Double(sc.tempo) * Double(song.synthPercent) / 100).rounded())))
        transport.setTempo(bpm)
    }

    // MARK: - media

    func loadMedia() {
        player?.shutdown()
        player = nil
        mediaError = nil
        rateApplied = false
        switch song.mediaKind {
        case .youtube:
            if let id = song.youtubeId { player = YouTubePlayer(videoId: id) }
        case .file:
            if let path = song.mediaPath {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) { player = LocalAudioPlayer(url: url) }
                else { mediaError = "The audio file was not found: \(url.lastPathComponent)" }
            }
        case .none:
            break
        }
    }

    func setMediaKind(_ kind: MediaKind) {
        guard kind != song.mediaKind else { return }
        change { $0.mediaKind = kind }
        loadMedia()
    }

    /// Returns false when the text is not a YouTube link / id.
    @discardableResult
    func setYouTube(_ text: String) -> Bool {
        guard let id = YouTubePlayer.videoId(from: text) else { mediaError = "That does not look like a YouTube link."; return false }
        change { $0.mediaKind = .youtube; $0.youtubeId = id; $0.youtubeTitle = nil; $0.mediaLoopA = nil; $0.mediaLoopB = nil; $0.anchors = [] }
        rebuildSync()
        loadMedia()
        return true
    }

    func setAudioFile(_ url: URL) {
        change { $0.mediaKind = .file; $0.mediaPath = url.path; $0.mediaLoopA = nil; $0.mediaLoopB = nil; $0.anchors = [] }
        rebuildSync()
        loadMedia()
    }

    var mediaTitle: String {
        if let t = player?.title, !t.isEmpty { return t }
        if let t = song.youtubeTitle, !t.isEmpty { return t }
        if song.mediaKind == .file, let p = song.mediaPath { return URL(fileURLWithPath: p).lastPathComponent }
        return ""
    }

    func setMediaRate(_ r: Double) {
        change { $0.mediaRate = r }
        player?.rate = r
    }

    // MARK: - play control

    func togglePlay() {
        switch mode {
        case .backing:
            guard let p = player, p.isReady else { return }
            if p.isPlaying { p.pause() } else {
                // start inside the loop if the cursor is outside it
                if song.loopOn, let (a, b) = mediaLoopBounds(), p.currentTime < a - 0.05 || p.currentTime >= b { p.seek(to: a) }
                p.play()
            }
        case .synth:
            guard score != nil else { return }
            if transport.playing { transport.pause() } else { applyTransportSettings(); transport.play() }
        }
    }

    func stop() {
        switch mode {
        case .backing:
            player?.pause()
            if let (a, _) = mediaLoopBounds() { player?.seek(to: a) } else { player?.seek(to: 0) }
        case .synth:
            transport.stop()
        }
    }

    func setMode(_ m: SongPlayMode) {
        guard m != mode else { return }
        if mode == .backing { player?.pause() } else { transport.stop() }
        change { $0.playMode = m.rawValue }
        setActive(nil)
        updateClock()
    }

    var isPlaying: Bool { mode == .backing ? (player?.isPlaying ?? false) : transportPlaying }

    func seek(toEvent i: Int) {
        guard let sc = score, i >= 0, i < sc.events.count else { return }
        switch mode {
        case .backing:
            guard let p = player, let sm = syncMap else { return }
            p.seek(to: max(0, sm.mediaTime(atTick: Double(sc.events[i].tick))))
            setActive(i)
        case .synth:
            transport.seek(i)
        }
    }

    func seekMedia(to seconds: Double) { player?.seek(to: seconds) }

    // MARK: - loop (bars)

    /// Measure under the cursor (media or transport), nil when unknown.
    var cursorMeasure: Int? {
        guard let sc = score else { return nil }
        if mode == .synth {
            let idx = transportPosition >= 0 ? transportPosition : transport.startIndex
            return idx < sc.events.count ? sc.events[idx].measure : nil
        }
        if let t = currentTick, t >= 0 { return min(sc.measures.count - 1, sc.measureIndex(atTick: Int(t))) }
        return nil
    }

    /// Click above a bar: first sets A, second sets B (swapped if before A), third starts over.
    func tapMeasure(_ m: Int) {
        guard score != nil else { return }
        if tapSetsA || song.loopStart == nil {
            change { $0.loopStart = m; $0.loopEnd = m }
            tapSetsA = false
        } else {
            let a = song.loopStart ?? m
            change { $0.loopStart = min(a, m); $0.loopEnd = max(a, m) }
            tapSetsA = true
        }
        pendingAnchorBar = m + 1
        applyTransportSettings()
    }

    func setLoopA(atCursor: Bool = true) {
        guard let m = cursorMeasure else { return }
        change { $0.loopStart = m; if let b = $0.loopEnd, b < m { $0.loopEnd = m }; if $0.loopEnd == nil { $0.loopEnd = m } }
        tapSetsA = false
        applyTransportSettings()
    }

    func setLoopB(atCursor: Bool = true) {
        guard let m = cursorMeasure else { return }
        change { $0.loopEnd = m; if let a = $0.loopStart, a > m { $0.loopStart = m }; if $0.loopStart == nil { $0.loopStart = 0 } }
        tapSetsA = true
        applyTransportSettings()
    }

    func clearLoop() {
        change { $0.loopStart = nil; $0.loopEnd = nil; $0.mediaLoopA = nil; $0.mediaLoopB = nil }
        tapSetsA = true
        applyTransportSettings()
    }

    func toggleLoop() {
        change { $0.loopOn.toggle() }
        transport.loop = song.loopOn
    }

    /// Loop bounds in media seconds: from the bar loop (via the sync map) or, without a tab, the A/B media points.
    func mediaLoopBounds() -> (Double, Double)? {
        if let sc = score, let lr = song.loopRange, let sm = syncMap {
            let a = sm.mediaTime(atTick: Double(sc.measureStart(lr.lowerBound)))
            let b = sm.mediaTime(atTick: Double(sc.measureStart(lr.upperBound) + sc.measureLength(lr.upperBound)))
            return b > a ? (max(0, a), b) : nil
        }
        if let a = song.mediaLoopA, let b = song.mediaLoopB, b > a { return (a, b) }
        return nil
    }

    // MARK: - loop (media seconds, no tab)

    func setMediaLoopA() {
        guard let t = player?.currentTime else { return }
        change { $0.mediaLoopA = t; if let b = $0.mediaLoopB, b <= t { $0.mediaLoopB = nil } }
    }

    func setMediaLoopB() {
        guard let t = player?.currentTime else { return }
        change { $0.mediaLoopB = t; if let a = $0.mediaLoopA, a >= t { $0.mediaLoopA = max(0, t - 4) } ; if $0.mediaLoopA == nil { $0.mediaLoopA = max(0, t - 8) } }
    }

    // MARK: - sync anchors

    func markAnchor(bar: Int) {
        guard let sc = score, let p = player, bar >= 1, bar <= sc.measures.count else { return }
        let tick = sc.measureStart(bar - 1)
        let t = p.currentTime
        change {
            $0.anchors.removeAll { $0.tick == tick || abs($0.mediaTime - t) < 0.5 }
            $0.anchors.append(SyncAnchor(mediaTime: t, tick: tick))
            $0.anchors.sort { $0.mediaTime < $1.mediaTime }
        }
        rebuildSync()
        services.model.toast("Anchor: bar \(bar) at \(SongPlayerController.clock(t))")
    }

    func removeAnchor(_ a: SyncAnchor) {
        change { $0.anchors.removeAll { $0 == a } }
        rebuildSync()
    }

    func clearAnchors() {
        change { $0.anchors = [] }
        rebuildSync()
    }

    func barOfAnchor(_ a: SyncAnchor) -> Int { (score?.measureIndex(atTick: a.tick) ?? 0) + 1 }

    // MARK: - clock (30 Hz)

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let p = player else { if mode == .backing { currentTick = nil }; return }
        if p.isReady && !rateApplied { rateApplied = true; p.rate = song.mediaRate }
        if let t = p.title as String?, !t.isEmpty, song.youtubeTitle != t, song.mediaKind == .youtube { song.youtubeTitle = t; persist() }
        updateClock()
        guard mode == .backing else { return }
        let now = p.currentTime
        if p.isPlaying { followPDFPage(now: now) }
        // A/B loop
        if song.loopOn, p.isPlaying, let (a, b) = mediaLoopBounds(), now >= b - 0.02 {
            p.seek(to: a)
            if let sc = score, let sm = syncMap { currentTick = sm.tick(atMediaTime: a); setActive(sc.eventIndex(atTick: Int(max(0, currentTick!)))) }
            return
        }
        guard let sc = score, let sm = syncMap else { currentTick = nil; return }
        let tk = sm.tick(atMediaTime: now)
        currentTick = tk
        if tk < 0 || tk >= Double(sc.totalTicks) { setActive(nil); return }
        let idx = sc.eventIndex(atTick: Int(tk))
        setActive(idx)
    }

    private func setActive(_ idx: Int?) {
        guard idx != active else { return }
        let previous = active
        active = idx
        guard let sc = score else { next = nil; return }
        if let i = idx {
            var k = i + 1
            var nx: Int? = nil
            while k < sc.events.count { if !sc.events[k].rest { nx = k; break }; k += 1 }
            next = nx
            // guitar along with the backing track: pluck when the cursor arrives at a note (not on seeks)
            if mode == .backing, song.guitarAlong, let p = player, p.isPlaying, previous != nil || i == 0 {
                let ev = sc.events[i]
                let secs = (tempoTimeline?.seconds(atTick: ev.tick + ev.dur) ?? 0) - (tempoTimeline?.seconds(atTick: ev.tick) ?? 0)
                for n in ev.notes where !n.tied { services.audio.pluck(n.midi, duration: max(0.15, secs / max(0.25, p.rate)) + 0.1) }
            }
        } else { next = nil }
    }

    private func updateClock() {
        let running = isPlaying
        if running != clockRunning {
            clockRunning = running
            if running { services.clock.start("song") } else { services.clock.stop("song") }
        }
    }

    func shutdown() {
        timer?.invalidate(); timer = nil
        transport.stop()
        player?.shutdown()
        player = nil
        if clockRunning { services.clock.stop("song"); clockRunning = false }
    }

    // MARK: - helpers

    static func clock(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
    static func clockPrecise(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00.0" }
        let m = Int(s) / 60
        return String(format: "%d:%04.1f", m, s - Double(m * 60))
    }
}
