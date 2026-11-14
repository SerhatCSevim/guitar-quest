// Backing-track players for the Song Player: a local audio file (AVPlayer) or a YouTube video (WKWebView + IFrame API).
// Both expose the same observable surface so the Songs screen can drive the tab cursor from either clock.
import AppKit
import Foundation
import Observation

/// Base class (subclassed by LocalAudioPlayer and YouTubePlayer). All members are main-actor.
@Observable
@MainActor
class MediaPlayerBase {
    /// The player can accept commands (file loaded / YouTube player ready).
    var isReady = false
    var isPlaying = false
    /// Seconds, refreshed ~30× per second while playing.
    var currentTime: Double = 0
    var duration: Double = 0
    /// Playback rate 0.25 … 2 (pitch preserved where the backend allows it).
    var rate: Double = 1 { didSet { applyRate() } }
    var errorText: String? = nil
    /// Human-readable title when the backend knows it (YouTube video title, file name).
    var title: String = ""

    func play() {}
    func pause() {}
    func seek(to seconds: Double) {}
    func applyRate() {}
    /// Stop timers / release the backend. Called when the screen goes away.
    func shutdown() {}

    func toggle() { isPlaying ? pause() : play() }
}

enum MediaCheck {
    /// `GQ_MEDIA_CHECK=<youtube id or url>` headless self-check (implemented in YouTubePlayer.swift).
    @MainActor static func runIfRequested(_ services: Services) { MediaCheckImpl.run(services) }
}

// MARK: - headless self-checks
// `GQ_MEDIA_CHECK=<youtube id or url> .build/debug/GuitarQuest`   → YouTube player: ready, duration, seek, play, rate
// `GQ_MEDIA_CHECK_FILE=<audio file> .build/debug/GuitarQuest`    → LocalAudioPlayer with the same script
enum MediaCheckImpl {
    @MainActor static func run(_ services: Services) {
        let env = ProcessInfo.processInfo.environment
        if let v = env["GQ_MEDIA_CHECK"], !v.isEmpty {
            guard let id = YouTubePlayer.videoId(from: v) else { print("media check: cannot parse a video id from \(v)"); exit(1) }
            let player = YouTubePlayer(videoId: id)
            // the page needs to live in a window to run its JavaScript; keep it hidden behind everything
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = player.webView
            window.alphaValue = 0
            window.orderBack(nil)
            print("media check: YouTube \(id)")
            runScript(player, label: "youtube") { window.orderOut(nil) }
        } else if let f = env["GQ_MEDIA_CHECK_FILE"], !f.isEmpty {
            let player = LocalAudioPlayer(url: URL(fileURLWithPath: f))
            print("media check: file \(f)")
            runScript(player, label: "file") {}
        }
    }

    @MainActor private static func runScript(_ player: MediaPlayerBase, label: String, cleanup: @escaping () -> Void) {
        var failures: [String] = []
        func finish() {
            player.pause()
            player.shutdown()
            cleanup()
            if failures.isEmpty { print("media check ok (\(label))") } else { print("media check FAILED (\(label)): " + failures.joined(separator: "; ")) }
            exit(failures.isEmpty ? 0 : 1)
        }
        func after(_ s: Double, _ block: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + s) { block() }
        }
        // debugging aid: dump what the page shows after 8 s (GQ_MEDIA_DEBUG=1)
        if ProcessInfo.processInfo.environment["GQ_MEDIA_DEBUG"] == "1", let yt = player as? YouTubePlayer {
            after(8) {
                let js = """
                (function(){ function txt(d){ try { return (d.body.innerText||'').replace(/\\s+/g,' ').slice(0,500); } catch(e){ return 'x:'+e; } }
                  var f = document.querySelector('iframe'); var inner = ''; var err = '';
                  try { if (f && f.contentDocument) { inner = txt(f.contentDocument); var e = f.contentDocument.querySelector('.ytp-error'); err = e ? e.innerText : ''; } } catch(e) { inner = 'cross-origin: ' + e; }
                  var e2 = document.querySelector('.ytp-error');
                  return JSON.stringify({ url: location.href, title: document.title, top: txt(document), iframes: document.querySelectorAll('iframe').length, inner: inner, err: err || (e2 ? e2.innerText : ''), mp: !!document.getElementById('movie_player'), player: typeof player, YT: typeof YT }); })()
                """
                yt.webView.evaluateJavaScript(js) { r, e in print("  page: \(r ?? "nil") \(e.map { "error: \($0)" } ?? "")") }
            }
        }
        // 1. wait for ready (≤ 25 s)
        var waited = 0.0
        nonisolated(unsafe) var poll: Timer? = nil
        poll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in
                waited += 0.2
                if let e = player.errorText { poll?.invalidate(); failures.append("error: \(e)"); finish(); return }
                guard player.isReady else {
                    if waited >= 25 { poll?.invalidate(); failures.append("not ready after 25 s"); finish() }
                    return
                }
                poll?.invalidate()
                print(String(format: "  ready after %.1f s: title \"%@\", duration %.1f s", waited, player.title, player.duration))
                if player.duration <= 0 { failures.append("duration is 0") }
                // 2. seek + play, then wait until playback has really started (YouTube buffers after a seek)
                let seekTo = min(30, max(0, player.duration - 10))
                player.seek(to: seekTo)
                player.play()
                var started = 0.0
                nonisolated(unsafe) var startPoll: Timer? = nil
                startPoll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                    Task { @MainActor in
                        started += 0.2
                        let going = player.isPlaying && player.currentTime > seekTo + 0.4
                        if !going && started < 12 { return }
                        startPoll?.invalidate()
                        print(String(format: "  playing %.1f s after seek(%.0f)+play: currentTime %.2f, isPlaying %@", started, seekTo, player.currentTime, player.isPlaying ? "true" : "false"))
                        if !going { failures.append("playback did not start within 12 s") }
                        // 3. measure 2 s at rate 1, then 2 s at rate 0.5
                        let t1 = player.currentTime
                        after(2) {
                            let t2 = player.currentTime
                            print(String(format: "  rate 1.0 for 2 s: %.2f → %.2f (Δ %.2f, expected ≈ 2.0)", t1, t2, t2 - t1))
                            if abs((t2 - t1) - 2) > 0.8 { failures.append(String(format: "full-speed advance %.2f s off", t2 - t1)) }
                            player.rate = 0.5
                            after(0.5) {
                                let t3 = player.currentTime
                                after(2) {
                                    let t4 = player.currentTime
                                    print(String(format: "  rate 0.5 for 2 s: %.2f → %.2f (Δ %.2f, expected ≈ 1.0), rate now %.2f", t3, t4, t4 - t3, player.rate))
                                    if abs((t4 - t3) - 1) > 0.5 { failures.append(String(format: "half-speed advance %.2f s off", t4 - t3)) }
                                    player.pause()
                                    after(0.5) {
                                        print("  paused: isPlaying \(player.isPlaying)")
                                        if player.isPlaying { failures.append("still playing after pause()") }
                                        finish()
                                    }
                                }
                            }
                        }
                    }
                }
                RunLoop.main.add(startPoll!, forMode: .common)
            }
        }
        RunLoop.main.add(poll!, forMode: .common)
        // keep the process alive while the checks run
        RunLoop.main.run(until: Date().addingTimeInterval(60))
        failures.append("timed out")
        finish()
    }
}
