// Song Player screen: backing track (YouTube / audio file) + synced tab + A/B loop + sync anchors.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MusicCore

struct SongPlayerView: View {
    @Bindable var controller: SongPlayerController
    let onBack: () -> Void

    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services

    @State private var linkText = ""
    @State private var showStaff = false
    @State private var showNames = true
    @State private var confirmClearAnchors = false

    private var settings: Settings { store.settings }
    private var song: SongEntry { controller.song }
    private var score: Score? { controller.score }
    private var player: MediaPlayerBase? { controller.player }

    var body: some View {
        let _ = model.settingsVersion
        VStack(alignment: .leading, spacing: 0) {
            header
            backingCard
            if controller.pdf != nil && (score == nil || controller.showPDF) {
                PDFTabCard(controller: controller, onImportTab: importTab)
            } else if score != nil {
                tabCard
                if controller.mode == .synth { synthBar }
                Card(padding: Theme.fretboardCardPadding) {
                    FretboardView(maxFret: fretboardMax, compact: true, marks: fretMarks) { s, f in
                        services?.audio.pluck(Theory.midiAt(s, f), duration: 1)
                    }
                }
            } else {
                noTabCard
            }
        }
        .onAppear { installKeys() }
        .onDisappear { model.keyHandler = nil }
    }

    // MARK: - header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                GQButton("Songs", icon: "chevron.left", style: .ghost, small: true, action: onBack)
                Text(song.title).font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1)
                if !song.artist.isEmpty { Text(song.artist).font(.system(size: 16)).foregroundStyle(Theme.muted) }
                Spacer()
                if let p = controller.piece, p.tracks.count > 1 {
                    Picker("Track", selection: Binding(get: { song.trackIndex }, set: { controller.selectTrack($0) })) {
                        ForEach(p.tracks.indices, id: \.self) { i in Text(p.tracks[i].name.isEmpty ? "Track \(i + 1)" : p.tracks[i].name).tag(i) }
                    }
                    .frame(width: 220)
                }
                if score != nil && controller.pdf != nil {
                    Field("Show") {
                        Segmented(options: [SegOption(false, "Tab"), SegOption(true, "PDF")],
                                  selection: Binding(get: { controller.showPDF }, set: { controller.showPDF = $0 }))
                    }
                }
                if score != nil && !controller.showPDF {
                    Field("Play with") {
                        Segmented(options: [SegOption(SongPlayMode.backing, "Backing track"), SegOption(.synth, "Guitar sound")],
                                  selection: Binding(get: { controller.mode }, set: { controller.setMode($0) }))
                    }
                }
            }
            if let t = controller.tabError { Text("Tab: \(t)").font(.system(size: 13)).foregroundStyle(Theme.bad) }
        }
        .padding(.top, 4).padding(.bottom, 14)
    }

    // MARK: - backing track

    private var backingCard: some View {
        Card {
            HStack(alignment: .top, spacing: 18) {
                mediaPanel.frame(width: 560)
                VStack(alignment: .leading, spacing: 12) {
                    sourceRow
                    if player != nil { transportRow; speedRow; loopRow }
                    if score != nil && player != nil { syncPanel }
                    if let e = controller.mediaError ?? player?.errorText { Text(e).font(.system(size: 13)).foregroundStyle(Theme.bad) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let yt = player as? YouTubePlayer {
                YouTubePlayerView(player: yt)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
            } else if player is LocalAudioPlayer {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.soft)
                    VStack(spacing: 8) {
                        Image(systemName: "waveform").font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.teal)
                        Text(controller.mediaTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.soft)
                    VStack(spacing: 6) {
                        Image(systemName: "play.rectangle").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.muted)
                        SmallText("No backing track yet. Paste a YouTube link or choose an audio file →", muted: true)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            }
            if !controller.mediaTitle.isEmpty, player is YouTubePlayer {
                SmallText(controller.mediaTitle, muted: true).lineLimit(1)
            }
        }
    }

    private var sourceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Field("Backing track") {
                Segmented(options: [SegOption(MediaKind.youtube, "YouTube"), SegOption(.file, "Audio file"), SegOption(.none, "None")],
                          selection: Binding(get: { song.mediaKind }, set: { controller.setMediaKind($0) }))
            }
            if song.mediaKind == .youtube {
                HStack(spacing: 8) {
                    TextField("Paste a YouTube link", text: $linkText)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                        .onSubmit { loadLink() }
                    GQButton("Load", small: true) { loadLink() }
                    if let id = song.youtubeId { SmallText("video \(id)", muted: true) }
                }
            } else if song.mediaKind == .file {
                HStack(spacing: 8) {
                    GQButton("Choose audio file…", icon: "folder", small: true) { chooseFile() }
                    if let p = song.mediaPath { SmallText(URL(fileURLWithPath: p).lastPathComponent, muted: true).lineLimit(1) }
                }
            }
        }
    }

    private func loadLink() {
        if controller.setYouTube(linkText) { linkText = "" }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the recording to play along with"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.setAudioFile(url)
    }

    private var transportRow: some View {
        HStack(spacing: 10) {
            let playing = controller.mode == .backing ? (player?.isPlaying ?? false) : controller.transportPlaying
            TransportButton(icon: playing ? "pause.fill" : "play.fill", on: playing, play: true, help: "Play / pause (space)") { controller.togglePlay() }
            TransportButton(icon: "stop.fill", help: "Stop (Esc)") { controller.stop() }
            if let p = player {
                Text("\(SongPlayerController.clock(p.currentTime)) / \(SongPlayerController.clock(p.duration))")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit().frame(width: 100, alignment: .leading)
                Slider(value: Binding(get: { min(p.currentTime, max(p.duration, 1)) }, set: { controller.seekMedia(to: $0) }),
                       in: 0...max(p.duration, 1))
                    .tint(Theme.accent)
                    .disabled(!p.isReady)
                if !p.isReady && p.errorText == nil { ProgressView().controlSize(.small) }
            }
        }
    }

    private var speedRow: some View {
        HStack(spacing: 8) {
            SmallText("Speed", muted: true)
            Segmented(options: [0.5, 0.75, 1.0].map { SegOption($0, $0 == 1 ? "1×" : String(format: "%g×", $0)) },
                      selection: Binding(get: { [0.5, 0.75, 1.0].contains(song.mediaRate) ? song.mediaRate : -1 }, set: { controller.setMediaRate($0) }))
            Picker("", selection: Binding(get: { song.mediaRate }, set: { controller.setMediaRate($0) })) {
                ForEach(YouTubePlayer.availableRates, id: \.self) { r in Text(String(format: "%g×", r)).tag(r) }
            }
            .labelsHidden().frame(width: 80)
            if controller.mode == .backing, score != nil {
                Toggle(isOn: Binding(get: { song.guitarAlong }, set: { v in controller.change { $0.guitarAlong = v } })) {
                    SmallText("Guitar sound along with the video")
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var loopRow: some View {
        HStack(spacing: 8) {
            TransportButton(icon: "repeat", label: "Loop A/B", on: song.loopOn, isToggle: true, help: "Repeat the chosen part (L)") { controller.toggleLoop() }
            if score == nil {
                // no tab: A/B are media times
                GQButton("Set A", small: true) { controller.setMediaLoopA() }
                GQButton("Set B", small: true) { controller.setMediaLoopB() }
                if let a = song.mediaLoopA, let b = song.mediaLoopB {
                    Text("A \(SongPlayerController.clockPrecise(a)) — B \(SongPlayerController.clockPrecise(b))").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.teal)
                    GQButton("Clear", style: .ghost, small: true) { controller.clearLoop() }
                } else if let a = song.mediaLoopA {
                    Text("A \(SongPlayerController.clockPrecise(a)) — set B").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                } else {
                    SmallText("Press Set A at the start of the part, Set B at its end.", muted: true)
                }
            } else if song.loopRange == nil, let a = song.loopStart {
                Text("A = bar \(a + 1) — now click above the bar where the loop should end").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                GQButton("Cancel", style: .ghost, small: true) { controller.clearLoop() }
            } else if let lr = song.loopRange {
                Text("Bars \(lr.lowerBound + 1)–\(lr.upperBound + 1)").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.teal)
                if let (a, b) = controller.mediaLoopBounds() {
                    SmallText("\(SongPlayerController.clockPrecise(a)) – \(SongPlayerController.clockPrecise(b))", muted: true)
                }
            } else {
                SmallText("Whole song. Click above a bar in the tab to set a loop.", muted: true)
            }
        }
    }

    // MARK: - sync

    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.teal)
                Text("Sync the tab with the recording").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
            }
            HStack(spacing: 10) {
                GQButton("Song starts now", icon: "flag.fill", style: .primary, small: true, disabled: !(player?.isReady ?? false)) { controller.markSongStart() }
                    .help("Press at the very first note of the song (pause the video there first if you like)")
                if let t0 = controller.songStartTime {
                    SmallText("Bar 1 = \(SongPlayerController.clockPrecise(t0))", muted: true)
                }
                HStack(spacing: 4) {
                    GQButton("−0.2 s", small: true) { controller.nudgeSync(by: -0.2) }.help("The tab is running late: move it earlier")
                    GQButton("+0.2 s", small: true) { controller.nudgeSync(by: 0.2) }.help("The tab is running early: move it later")
                }
                if controller.player?.isPlaying == true, let m = controller.cursorMeasure {
                    SmallText("Tab is at bar \(m + 1)", muted: true)
                }
            }
            SmallText("1. Play the video and press “Song starts now” on the very first note. 2. If the cursor drifts later in the song, pause where a bar starts, pick that bar and press Mark — two anchors correct a tempo difference.", muted: true)
            HStack(spacing: 8) {
                SmallText("Bar")
                Stepper(value: $controller.pendingAnchorBar, in: 1...max(1, score?.measures.count ?? 1)) {
                    Text("\(controller.pendingAnchorBar)").font(.system(size: 14, weight: .bold)).frame(minWidth: 28)
                }
                if let m = controller.cursorMeasure {
                    GQButton("Use bar \(m + 1) (cursor)", style: .ghost, small: true) { controller.pendingAnchorBar = m + 1 }
                }
                GQButton("Mark", icon: "mappin", style: .primary, small: true, disabled: !(player?.isReady ?? false)) {
                    controller.markAnchor(bar: controller.pendingAnchorBar)
                }
                if !song.anchors.isEmpty {
                    GQButton("Clear anchors", style: .ghost, small: true) { confirmClearAnchors = true }
                }
            }
            if song.anchors.isEmpty {
                SmallText("No anchors yet: the tab is assumed to start at 0:00 of the video — usually wrong, press “Song starts now”.", muted: true)
            } else {
                FlowLayout(hSpacing: 6, vSpacing: 6) {
                    ForEach(song.anchors, id: \.self) { a in
                        HStack(spacing: 4) {
                            Text("bar \(controller.barOfAnchor(a)) ↔ \(SongPlayerController.clockPrecise(a.mediaTime))").font(.system(size: 12, weight: .semibold))
                            Button { controller.removeAnchor(a) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(Theme.tealSoft).foregroundStyle(Theme.teal).clipShape(Capsule())
                    }
                }
            }
        }
        .alert("Remove all sync anchors?", isPresented: $confirmClearAnchors) {
            Button("Remove", role: .destructive) { controller.clearAnchors() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - tab

    private var notationOptions: NotationOptions {
        NotationOptions(showStaff: showStaff, showTab: true, showNames: showNames, colors: settings.colors, naming: settings.namingShort, minWidth: 520)
    }

    private var tabCard: some View {
        Card(padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let sc = score {
                        Text(controller.piece?.tracks[safe: song.trackIndex]?.name ?? "Tab").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                        SmallText("\(sc.measures.count) bars · ♩ = \(sc.tempo)" + (sc.tempoMap.count > 1 ? " (tempo changes)" : ""), muted: true)
                    }
                    Spacer()
                    GQButton("Set A at cursor", small: true, disabled: controller.cursorMeasure == nil) { controller.setLoopA() }
                    GQButton("Set B at cursor", small: true, disabled: controller.cursorMeasure == nil) { controller.setLoopB() }
                    GQButton("Clear loop", style: .ghost, small: true, disabled: song.loopRange == nil) { controller.clearLoop() }
                    Segmented(options: [SegOption(false, "Tab"), SegOption(true, "Staff + Tab")], selection: $showStaff)
                    TransportButton(label: "Note names", on: showNames, isToggle: true, help: "Show note names under the tab") { showNames.toggle() }
                }
                SmallText(controller.tapSetsA || song.loopRange == nil ? "Click above a bar to set the start of the loop (A)." : "Now click above the bar where the loop should end (B).", muted: true)
                ZStack {
                    if controller.isDebugActive {
                        ScoreView(score: score, options: notationOptions, active: controller.active, next: controller.next,
                                  loopRange: controller.displayLoopRange)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical) {
                                ScoreView(score: score, options: notationOptions, active: controller.active, next: controller.next,
                                          onSeek: { controller.seek(toEvent: $0) }, scrollProxy: proxy,
                                          loopRange: controller.displayLoopRange, onMeasureTap: { controller.tapMeasure($0) })
                                    .padding(.trailing, 4)
                            }
                            .frame(minHeight: 200, maxHeight: 420)
                        }
                    }
                    if controller.countdown > 0 && controller.transportPlaying {
                        Text(String(controller.countdown))
                            .font(.system(size: 110, weight: .black))
                            .foregroundStyle(Theme.accent.opacity(0.85))
                            .shadow(color: .white.opacity(0.9), radius: 10, y: 4)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    private var noTabCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                H3("No tab yet")
                SmallText("Import the song's tab to see it move with the video and to loop by bars. Until then the controls above loop any part of the video by time.", muted: true)
                HStack(spacing: 8) {
                    GQButton("Import tab…", icon: "square.and.arrow.down", style: .primary, small: true) { importTab() }
                    SmallText("Guitar Pro (.gp5 / .gp4 / .gp3 / .gp) or MusicXML (.musicxml / .xml / .mxl)", muted: true)
                }
                HStack(spacing: 8) {
                    GQButton("Add PDF tab…", icon: "doc.richtext", small: true) { importPDF() }
                    SmallText("A PDF shows its pages next to the video; mark each page once and they turn by themselves.", muted: true)
                }
            }
        }
    }

    private func importTab() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gp5"), UTType(filenameExtension: "gp4"), UTType(filenameExtension: "gp3"), UTType(filenameExtension: "gp"),
                                     UTType(filenameExtension: "musicxml"), UTType(filenameExtension: "mxl"), .xml, .pdf].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Guitar Pro / MusicXML tab, or a PDF of the tab"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.pathExtension.lowercased() == "pdf" { controller.importPDF(from: url) } else { controller.importTab(from: url) }
    }

    private func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.importPDF(from: url)
    }

    // MARK: - synth transport (Guitar sound mode)

    private var synthBar: some View {
        Card {
            FlowLayout(hSpacing: 18, vSpacing: 10, alignment: .center) {
                HStack(spacing: 6) {
                    TransportButton(icon: controller.transportPlaying ? "pause.fill" : "play.fill", on: controller.transportPlaying, play: true, help: "Play / pause (space)") { controller.togglePlay() }
                    TransportButton(icon: "stop.fill", help: "Stop (Esc)") { controller.stop() }
                    TransportButton(icon: "repeat", label: "Loop", on: song.loopOn, isToggle: true, help: "Repeat the loop") { controller.toggleLoop() }
                }
                .fixedSize()
                HStack(spacing: 6) {
                    SmallText("Tempo", muted: true)
                    TransportButton(label: "−5%", small: true) { controller.setSynthPercent(song.synthPercent - 5) }
                    Slider(value: Binding(get: { Double(song.synthPercent) }, set: { controller.setSynthPercent(Int($0.rounded())) }), in: 25...150, step: 1)
                        .tint(Theme.accent).frame(width: 160)
                    TransportButton(label: "+5%", small: true) { controller.setSynthPercent(song.synthPercent + 5) }
                    Text("\(song.synthPercent)% · \(controller.synthBPM) BPM").font(.system(size: 15, weight: .black)).frame(minWidth: 130, alignment: .leading)
                }
                .fixedSize()
                HStack(spacing: 6) {
                    TransportButton(icon: "metronome", label: "Click", on: controller.transport.metronome, isToggle: true, help: "Metronome") { controller.transport.metronome.toggle() }
                    TransportButton(label: "Count-in", on: controller.transport.countIn, isToggle: true, help: "One bar of clicks before starting") { controller.transport.countIn.toggle() }
                }
                .fixedSize()
                SmallText("Our guitar sound plays the tab; the video stays paused.", muted: true)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - fretboard

    private var fretboardMax: Int {
        let maxF = score?.events.compactMap { $0.notes.map { $0.fret }.max() }.max() ?? 0
        return max(15, min(22, maxF + 1))
    }

    private var fretMarks: [FretMark] {
        guard let sc = score else { return [] }
        var marks: [FretMark] = []
        if let a = controller.active, a < sc.events.count {
            if let nx = controller.next {
                for n in sc.events[nx].notes {
                    var m = FretMark.note(n.string, n.fret, settings: settings, spelled: n.spelled, label: "", kind: .ring)
                    m.opacity = 0.95
                    marks.append(m)
                }
            }
            for n in sc.events[a].notes {
                var m = FretMark.note(n.string, n.fret, settings: settings, spelled: n.spelled, kind: .root)
                m.pop = !controller.seeking
                marks.append(m)
            }
        }
        return marks
    }

    // MARK: - keys

    private func installKeys() {
        model.keyHandler = { press in
            if press.key == .space { controller.togglePlay(); return .handled }
            if press.key == .escape { controller.stop(); return .handled }
            if controller.pdf != nil && (score == nil || controller.showPDF) {
                if press.key == .rightArrow || press.key == .pageDown { controller.userChangedPage(controller.pdfPage + 1); return .handled }
                if press.key == .leftArrow || press.key == .pageUp { controller.userChangedPage(controller.pdfPage - 1); return .handled }
            }
            if press.characters == "[" { if score != nil { controller.setLoopA() } else { controller.setMediaLoopA() }; return .handled }
            if press.characters == "]" { if score != nil { controller.setLoopB() } else { controller.setMediaLoopB() }; return .handled }
            if press.characters.lowercased() == "l" { controller.toggleLoop(); return .handled }
            return .ignored
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
