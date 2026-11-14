// Local backing track (mp3 / m4a / wav / aiff) played with AVPlayer. Slow-down keeps the pitch (spectral algorithm).
import AVFoundation
import Foundation

@Observable
@MainActor
final class LocalAudioPlayer: MediaPlayerBase {
    let url: URL
    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private let item: AVPlayerItem
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var wantsPlaying = false

    init(url: URL) {
        self.url = url
        let asset = AVURLAsset(url: url)
        item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        super.init()
        title = url.deletingPathExtension().lastPathComponent
        rate = 1

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let d = item.duration
                    if d.isNumeric { self.duration = CMTimeGetSeconds(d) }
                    self.isReady = true
                case .failed:
                    self.errorText = item.error?.localizedDescription ?? "The audio file could not be loaded."
                    self.isReady = false
                default: break
                }
            }
        }
        // duration from the asset as well (available before the item is ready on some files)
        Task { @MainActor [weak self] in
            if let d = try? await asset.load(.duration), d.isNumeric, let self, self.duration == 0 {
                self.duration = CMTimeGetSeconds(d)
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if t.isNumeric { self.currentTime = CMTimeGetSeconds(t) }
                // keep isPlaying honest if the player stalled or was stopped externally
                let playing = self.player.rate > 0
                if self.isPlaying != playing && self.wantsPlaying == playing { self.isPlaying = playing }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.wantsPlaying = false
                self.currentTime = self.duration
            }
        }
    }

    override func play() {
        guard errorText == nil else { return }
        if duration > 0, currentTime >= duration - 0.05 { seek(to: 0) }
        wantsPlaying = true
        player.rate = Float(rate)
        isPlaying = true
    }

    override func pause() {
        wantsPlaying = false
        player.pause()
        isPlaying = false
    }

    override func seek(to seconds: Double) {
        let t = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    override func applyRate() {
        let r = max(0.25, min(2, rate))
        if r != rate { rate = r; return } // didSet re-enters once with the clamped value
        if isPlaying { player.rate = Float(r) }
    }

    override func shutdown() {
        pause()
        if let o = timeObserver { player.removeTimeObserver(o); timeObserver = nil }
        statusObservation?.invalidate(); statusObservation = nil
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        player.replaceCurrentItem(with: nil)
    }
}
