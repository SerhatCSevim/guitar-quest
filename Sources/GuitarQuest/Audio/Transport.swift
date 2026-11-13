// Transport: schedules notes and metronome clicks ahead of time on the audio clock. Port of web/js/player.js.
import Foundation
import Observation
import MusicCore

struct TransportItem {
    var i: Int
    var beat: Double
    var beats: Double
    var rest: Bool
    var midis: [Int]
    var strum: Bool = false
    var dir: StrumDirection = .down
    var velocity: Double? = nil
    // extra tags used by the Jam view
    var bar: Int = 0
    var slot: Int = 0
}

struct TrainerSettings: Equatable {
    var on = false
    var step = 5
    var target = 120
}

@Observable
@MainActor
final class Transport {
    static let lookahead = 0.12
    static let tickInterval = 0.025

    private let audio: AudioEngine
    private(set) var items: [TransportItem] = []
    private(set) var totalBeats: Double = 0
    var beatsPerBar = 4
    var bpm = 80
    var loop = false
    var metronome = true
    var countIn = true
    var sound = true
    var trainer = TrainerSettings()

    private(set) var playing = false
    private(set) var startIndex = 0
    /// Current item index (−1 = none) and count-in number (0 = none), updated ~60×/s while playing.
    private(set) var position = -1
    private(set) var countdown = 0

    var onPosition: ((_ index: Int, _ countdown: Int, _ beat: Double, _ seeking: Bool) -> Void)?
    var onState: ((Bool) -> Void)?
    var onLoop: ((Int) -> Void)?

    private struct Pass { var origin: Double; var spb: Double; var fromBeat: Double }
    private var pass = Pass(origin: 0, spb: 0.75, fromBeat: 0)
    private var nextItem = 0
    private var nextClick = 0
    private var countInUntil: Double = 0
    private var handles: [PluckHandle] = []
    private var scheduler: Timer?
    private var frameTimer: Timer?

    init(audio: AudioEngine) { self.audio = audio }

    func load(_ items: [TransportItem], totalBeats: Double, beatsPerBar: Int = 4) {
        stop()
        self.items = items
        self.totalBeats = totalBeats
        self.beatsPerBar = beatsPerBar
        startIndex = 0
    }

    func setTempo(_ newBpm: Int) {
        let b = max(30, min(240, newBpm))
        if b == bpm { return }
        let wasPlaying = playing
        let at = currentIndex()
        bpm = b
        if wasPlaying { pause(); play(from: at, skipCountIn: true) }
    }

    func currentIndex() -> Int { position >= 0 ? position : startIndex }

    func play(from index: Int? = nil, skipCountIn: Bool = false) {
        guard audio.ensure(), !items.isEmpty, !playing else { return }
        if let index { startIndex = max(0, min(items.count - 1, index)) }
        audio.warm(items.flatMap { $0.midis })
        playing = true
        let spb = 60.0 / Double(bpm)
        let startBeat = items[startIndex].beat
        let ctxNow = audio.now + 0.08
        let countBeats = countIn && !skipCountIn ? Double(beatsPerBar) : 0
        // pass = one run through the score; origin is the audio time of beat 0
        pass = Pass(origin: ctxNow + countBeats * spb - startBeat * spb, spb: spb, fromBeat: startBeat)
        nextItem = startIndex
        nextClick = Int(ceil(startBeat - countBeats - 1e-9))
        countInUntil = startBeat
        schedule()
        scheduler = Timer.scheduledTimer(withTimeInterval: Transport.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        }
        RunLoop.main.add(scheduler!, forMode: .common)
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.frame() }
        }
        RunLoop.main.add(frameTimer!, forMode: .common)
        frame()
        onState?(true)
    }

    private func schedule() {
        guard playing else { return }
        let horizon = audio.now + Transport.lookahead
        let p = pass
        // metronome (including the count-in bar before the start). The click counter always follows the
        // music, so switching the metronome on mid-play does not fire a burst of late clicks.
        let curBeat = (audio.now - p.origin) / p.spb
        if Double(nextClick) < floor(curBeat) { nextClick = Int(ceil(curBeat - 1e-9)) }
        while Double(nextClick) < totalBeats {
            let t = p.origin + Double(nextClick) * p.spb
            if t > horizon { break }
            if metronome || Double(nextClick) < countInUntil {
                let inBar = ((nextClick % beatsPerBar) + beatsPerBar) % beatsPerBar
                audio.click(when: t, accent: inBar == 0)
            }
            nextClick += 1
        }
        // notes
        while nextItem < items.count {
            let it = items[nextItem]
            let t = p.origin + it.beat * p.spb
            if t > horizon { break }
            if sound && !it.rest && !it.midis.isEmpty {
                let dur = it.beats * p.spb
                if it.strum {
                    handles.append(contentsOf: audio.strum(it.midis, when: t, dir: it.dir, velocity: it.velocity ?? 0.6, duration: dur + 0.05))
                } else {
                    for m in it.midis { if let h = audio.pluck(m, when: t, duration: dur + 0.12) { handles.append(h) } }
                }
                if handles.count > 64 { handles = Array(handles.suffix(64)) }
            }
            nextItem += 1
        }
        // end of pass
        let endT = p.origin + totalBeats * p.spb
        if nextItem >= items.count && endT <= horizon {
            if loop {
                if trainer.on && bpm < trainer.target {
                    bpm = min(trainer.target, bpm + trainer.step)
                    onLoop?(bpm)
                }
                let spb = 60.0 / Double(bpm)
                let loopStart = items[startIndex].beat
                pass = Pass(origin: endT - loopStart * spb, spb: spb, fromBeat: loopStart)
                nextItem = startIndex
                nextClick = Int(ceil(loopStart - 1e-9))
                countInUntil = loopStart
            } else if audio.now >= endT {
                stop()
            }
        }
    }

    private func frame() {
        guard playing else { return }
        let p = pass
        let beat = (audio.now - p.origin) / p.spb
        var idx = -1
        if beat >= p.fromBeat - 1e-6 {
            var k = startIndex
            while k < items.count {
                let it = items[k]
                if beat >= it.beat - 1e-6 && beat < it.beat + it.beats { idx = k; break }
                if it.beat > beat { break }
                k += 1
            }
        }
        let cd = beat < p.fromBeat ? Int(ceil(p.fromBeat - beat)) : 0
        if idx != position || cd != countdown {
            position = idx
            countdown = cd
            onPosition?(idx, cd, beat, false)
        }
    }

    private func stopTimers() {
        scheduler?.invalidate(); scheduler = nil
        frameTimer?.invalidate(); frameTimer = nil
    }

    func pause() {
        guard playing else { return }
        playing = false
        stopTimers()
        let t = audio.now
        for h in handles { h.stop(at: t) }
        handles = []
        if position >= 0 { startIndex = position }
        countdown = 0
        onState?(false)
    }

    func stop() {
        let was = playing
        playing = false
        stopTimers()
        let t = audio.now
        for h in handles { h.stop(at: t) }
        handles = []
        startIndex = 0
        position = -1
        countdown = 0
        onPosition?(-1, 0, 0, false)
        if was { onState?(false) }
    }

    func seek(_ i: Int) {
        guard !items.isEmpty else { return }
        let was = playing
        if was { pause() }
        startIndex = max(0, min(items.count - 1, i))
        position = -1
        onPosition?(startIndex, 0, items[startIndex].beat, true)
        if was { play(from: startIndex, skipCountIn: true) }
    }
}
