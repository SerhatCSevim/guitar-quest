// YouTube backing video: a WKWebView running the YouTube IFrame Player API. The page posts ready / state / time /
// error messages to native; native drives it with evaluateJavaScript. This is the app's only online feature.
import AppKit
import Foundation
import SwiftUI
import WebKit

@Observable
@MainActor
final class YouTubePlayer: MediaPlayerBase {
    let videoId: String
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var proxy: MessageProxy?
    @ObservationIgnored private var navDelegate: NavDelegate?
    @ObservationIgnored private var snapping = false
    @ObservationIgnored private var pendingSeek: Double? = nil
    @ObservationIgnored private var pendingPlay = false

    static let availableRates: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    /// The https origin the player page claims. YouTube refuses embeds whose referer is youtube.com itself
    /// (error 152-4), so the page is given the app's own (non-served) origin instead.
    static let pageOrigin = ProcessInfo.processInfo.environment["GQ_YT_ORIGIN"] ?? "https://guitarquest.app"

    enum EmbedMode: String { case iframeAPI, direct }
    /// How the player is embedded. `GQ_YT_MODE=direct` switches to loading the /embed/ page as the top document
    /// and talking to YouTube's player element directly (used when the IFrame API rejects the host).
    nonisolated(unsafe) static var embedMode: EmbedMode = {
        EmbedMode(rawValue: ProcessInfo.processInfo.environment["GQ_YT_MODE"] ?? "") ?? .iframeAPI
    }()

    init(videoId: String) {
        self.videoId = videoId
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 360), configuration: config)
        super.init()
        let proxy = MessageProxy(owner: self)
        self.proxy = proxy
        controller.add(proxy, name: "gq")
        let nav = NavDelegate(owner: self)
        navDelegate = nav
        webView.navigationDelegate = nav
        webView.setValue(false, forKey: "drawsBackground")
        // YouTube rejects embeds from user agents that do not look like a browser (error 152/153)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        switch Self.embedMode {
        case .iframeAPI:
            webView.loadHTMLString(Self.html(videoId: videoId), baseURL: URL(string: Self.pageOrigin + "/player"))
        case .direct:
            let script = WKUserScript(source: Self.directScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            controller.addUserScript(script)
            var req = URLRequest(url: URL(string: "https://www.youtube.com/embed/\(videoId)?enablejsapi=1&playsinline=1&controls=1&rel=0&modestbranding=1")!)
            req.setValue(Self.pageOrigin + "/", forHTTPHeaderField: "Referer")
            webView.load(req)
        }
    }

    /// Accepts a bare 11-character id, youtu.be/ID, watch?v=ID, /shorts/ID, /embed/ID, /live/ID.
    static func videoId(from text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        func valid(_ id: String) -> Bool {
            id.count == 11 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
        if valid(s) { return s }
        guard let url = URL(string: s.hasPrefix("http") ? s : "https://" + s), let host = url.host?.lowercased() else { return nil }
        let comps = url.pathComponents.filter { $0 != "/" }
        if host.hasSuffix("youtu.be") {
            if let id = comps.first, valid(id) { return id }
            return nil
        }
        guard host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") else { return nil }
        if let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = q.first(where: { $0.name == "v" })?.value, valid(v) { return v }
        if comps.count >= 2, ["shorts", "embed", "live", "v"].contains(comps[0]), valid(comps[1]) { return comps[1] }
        return nil
    }

    // MARK: commands

    override func play() {
        guard isReady else { pendingPlay = true; return }
        js("player.playVideo()")
    }

    override func pause() {
        pendingPlay = false
        guard isReady else { return }
        js("player.pauseVideo()")
    }

    override func seek(to seconds: Double) {
        let t = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = t
        guard isReady else { pendingSeek = t; return }
        js("player.seekTo(\(t), true)")
    }

    override func applyRate() {
        guard !snapping else { return }
        let snapped = Self.availableRates.min { abs($0 - rate) < abs($1 - rate) } ?? 1
        if snapped != rate {
            snapping = true
            rate = snapped
            snapping = false
            return // the didSet re-entry (guarded above) is skipped; apply below on this call
        }
        if isReady { js("player.setPlaybackRate(\(snapped))") }
    }

    override func shutdown() {
        pendingPlay = false
        js("try { stopGQ(); player.pauseVideo(); } catch (e) {}")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "gq")
        webView.navigationDelegate = nil
        proxy = nil
        isPlaying = false
    }

    private func js(_ code: String) {
        webView.evaluateJavaScript("try { \(code) } catch (e) { 'err:' + e }") { _, _ in }
    }

    // MARK: messages from the page

    fileprivate func handle(_ body: Any) {
        guard let d = body as? [String: Any], let kind = d["kind"] as? String else { return }
        switch kind {
        case "ready":
            duration = (d["duration"] as? Double) ?? 0
            if let t = d["title"] as? String, !t.isEmpty { title = t }
            isReady = true
            errorText = nil
            js("player.setPlaybackRate(\(rate))")
            if let s = pendingSeek { pendingSeek = nil; js("player.seekTo(\(s), true)") }
            if pendingPlay { pendingPlay = false; js("player.playVideo()") }
        case "state":
            let s = (d["state"] as? String) ?? ""
            switch s {
            case "playing": isPlaying = true
            case "paused", "ended", "cued": isPlaying = false
            default: break // buffering / unstarted keep the current flag
            }
            if s == "ended" { currentTime = duration }
            if let dur = d["duration"] as? Double, dur > 0 { duration = dur }
        case "time":
            if let t = d["time"] as? Double { currentTime = t }
        case "error":
            let code = (d["code"] as? Int) ?? -1
            switch code {
            case 2: errorText = "Invalid YouTube video id."
            case 5: errorText = "The video cannot be played here (HTML5 player error)."
            case 100: errorText = "This video was not found or is private."
            case 101, 150: errorText = "This video cannot be embedded. Watch it on YouTube or use a local audio file."
            default: errorText = "YouTube error \(code)."
            }
            isPlaying = false
        default: break
        }
    }

    fileprivate func navigationFailed(_ error: Error) {
        errorText = "Could not load the YouTube player: \(error.localizedDescription)"
    }

    // MARK: page

    private static func html(videoId: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script>
        var player = null, gqTimer = null;
        function post(m) { try { window.webkit.messageHandlers.gq.postMessage(m); } catch (e) {} }
        var tag = document.createElement('script'); tag.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('p', {
            videoId: '\(videoId)', width: '100%', height: '100%',
            playerVars: { playsinline: 1, controls: 1, rel: 0, modestbranding: 1, enablejsapi: 1, origin: '\(pageOrigin)' },
            events: {
              onReady: function () {
                var title = '';
                try { title = (player.getVideoData() || {}).title || ''; } catch (e) {}
                post({ kind: 'ready', duration: player.getDuration() || 0, title: title });
                startGQ();
              },
              onStateChange: function (e) {
                var names = { '-1': 'unstarted', '0': 'ended', '1': 'playing', '2': 'paused', '3': 'buffering', '5': 'cued' };
                post({ kind: 'state', state: names[String(e.data)] || String(e.data), duration: player.getDuration() || 0 });
              },
              onError: function (e) { post({ kind: 'error', code: e.data }); }
            }
          });
        }
        function startGQ() {
          stopGQ();
          gqTimer = setInterval(function () {
            if (player && player.getCurrentTime) post({ kind: 'time', time: player.getCurrentTime() });
          }, 100);
        }
        function stopGQ() { if (gqTimer) { clearInterval(gqTimer); gqTimer = null; } }
        setTimeout(function () { if (!player) post({ kind: 'error', code: -2 }); }, 20000);
        </script></body></html>
        """
    }

    /// Direct mode: the embed page is the document; YouTube's player element exposes the same methods as the IFrame API.
    private static let directScript = """
    (function () {
      var gqTimer = null; window.player = null;
      function post(m) { try { window.webkit.messageHandlers.gq.postMessage(m); } catch (e) {} }
      window.stopGQ = function () { if (gqTimer) { clearInterval(gqTimer); gqTimer = null; } };
      var tries = 0;
      var find = setInterval(function () {
        tries++;
        var p = document.getElementById('movie_player');
        if (p && p.getPlayerState && p.getDuration && p.getDuration() > 0) {
          clearInterval(find);
          window.player = p;
          var title = '';
          try { title = (p.getVideoData() || {}).title || ''; } catch (e) {}
          post({ kind: 'ready', duration: p.getDuration() || 0, title: title });
          try {
            p.addEventListener('onStateChange', function (st) {
              var names = { '-1': 'unstarted', '0': 'ended', '1': 'playing', '2': 'paused', '3': 'buffering', '5': 'cued' };
              post({ kind: 'state', state: names[String(st)] || String(st), duration: p.getDuration() || 0 });
            });
            p.addEventListener('onError', function (e) { post({ kind: 'error', code: e }); });
          } catch (e) {}
          gqTimer = setInterval(function () { try { post({ kind: 'time', time: p.getCurrentTime() }); } catch (e) {} }, 100);
        } else if (tries > 200) {
          clearInterval(find);
          var err = document.querySelector('.ytp-error');
          post({ kind: 'error', code: err ? 152 : -2 });
        }
      }, 100);
    })();
    """

    // MARK: helpers (weak proxies avoid WKWebView ↔ owner retain cycles)

    private final class MessageProxy: NSObject, WKScriptMessageHandler {
        weak var owner: YouTubePlayer?
        init(owner: YouTubePlayer) { self.owner = owner }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let body = message.body
            Task { @MainActor [weak owner] in owner?.handle(body) }
        }
    }

    private final class NavDelegate: NSObject, WKNavigationDelegate {
        weak var owner: YouTubePlayer?
        init(owner: YouTubePlayer) { self.owner = owner }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak owner] in owner?.navigationFailed(error) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak owner] in owner?.navigationFailed(error) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // keep the player inside: links that would leave the embed open in the user's browser instead
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Shows the player's web view. Give it a 16:9 frame (e.g. `.aspectRatio(16/9, contentMode: .fit)`).
struct YouTubePlayerView: NSViewRepresentable {
    let player: YouTubePlayer
    func makeNSView(context: Context) -> WKWebView { player.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
