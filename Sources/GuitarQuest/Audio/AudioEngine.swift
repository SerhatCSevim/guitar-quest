// Sound: plucked-string synthesis (Karplus-Strong), strums, metronome clicks and game chimes.
// Port of web/js/audio.js. One AVAudioSourceNode renders everything sample-accurately:
//   plucks → guitar bus (0.9) → peaking EQ 220 Hz +3 dB → low-pass 5200 Hz ┐
//   clicks → click bus (0.55) ───────────────────────────────────────────────┼→ master (volume) → compressor → output
//   chimes ───────────────────────────────────────────────────────────────────┘
import AVFoundation
import Foundation
import os
import MusicCore

/// A handle to a sounding note; `stop(at:)` fades it out (pause / stop in the transport).
final class PluckHandle {
    fileprivate let id: Int
    fileprivate weak var engine: AudioEngine?
    fileprivate init(id: Int, engine: AudioEngine) { self.id = id; self.engine = engine }
    func stop(at time: Double? = nil) { engine?.stopVoice(id, at: time) }
}

final class AudioEngine {
    // MARK: public API (main thread)

    var sampleRate: Double { sr }

    /// Current audio time in seconds (monotonic while the engine runs).
    var now: Double {
        ensure()
        return Double(renderedSamples.withLock { $0 }) / sr
    }

    func setVolume(_ v: Double) { params.withLock { $0.volume = Float(max(0, min(1, v))) } }

    /// Play one note. `when` is an audio time (seconds, see `now`); 0 = as soon as possible.
    @discardableResult
    func pluck(_ midi: Int, when: Double = 0, velocity: Double = 0.75, duration: Double? = nil) -> PluckHandle? {
        guard ensure() else { return nil }
        let t = max(when, now)
        let buf = stringBuffer(midi)
        let vel = Float(velocity * (0.92 + Double.random(in: 0..<1) * 0.12))
        let id = nextId();
        var v = Voice(id: id, kind: .sample(buf), start: Int64(t * sr))
        v.gain = vel
        v.rate = buf.rate
        v.bus = .guitar
        if let dur = duration {
            v.holdEnd = Int64((t + dur) * sr)
            v.fadeMul = Float(pow(0.0008 / Double(vel), 1.0 / (0.12 * sr)))
            v.stopAt = Int64((t + dur + 0.15) * sr)
        }
        enqueue(.add(v))
        return PluckHandle(id: id, engine: self)
    }

    /// midis: low to high. dir down strums low→high, up high→low (lighter).
    @discardableResult
    func strum(_ midis: [Int], when: Double = 0, dir: StrumDirection = .down, spread: Double = 0.016, velocity: Double = 0.6, duration: Double? = nil) -> [PluckHandle] {
        guard ensure() else { return [] }
        let order = dir == .up ? Array(midis.reversed()) : midis
        let vel = velocity * (dir == .up ? 0.75 : 1)
        let base = when == 0 ? now : when
        return order.enumerated().compactMap { i, m in pluck(m, when: base + Double(i) * spread, velocity: vel, duration: duration) }
    }

    func click(when: Double, accent: Bool) {
        guard ensure() else { return }
        let t = max(when, now)
        let s0 = Int64(t * sr)
        var v = Voice(id: nextId(), kind: .osc(.square, Float(accent ? 1760 : 1180)), start: s0)
        v.bus = .click
        v.env = [EnvPoint(sample: s0, gain: 0.0001), EnvPoint(sample: s0 + Int64(0.002 * sr), gain: accent ? 0.5 : 0.32), EnvPoint(sample: s0 + Int64(0.045 * sr), gain: 0.0001)]
        v.stopAt = s0 + Int64(0.06 * sr)
        enqueue(.add(v))
    }

    /// Small feedback sounds for games: correct = two triangle notes, wrong = one low sine.
    func chime(_ good: Bool) {
        guard ensure() else { return }
        let t = now
        let notes = good ? [84, 91] : [52]
        for (i, m) in notes.enumerated() {
            let t0 = t + Double(i) * 0.08
            let s0 = Int64(t0 * sr)
            var v = Voice(id: nextId(), kind: .osc(good ? .triangle : .sine, Float(Theory.freqOf(m))), start: s0)
            v.bus = .master
            v.env = [EnvPoint(sample: s0, gain: 0.0001), EnvPoint(sample: s0 + Int64(0.01 * sr), gain: good ? 0.16 : 0.25),
                     EnvPoint(sample: s0 + Int64((good ? 0.35 : 0.25) * sr), gain: 0.0001)]
            v.stopAt = s0 + Int64(0.4 * sr)
            enqueue(.add(v))
        }
    }

    /// Pre-render the string buffers for a set of notes (avoids a hiccup on the first play).
    func warm(_ midis: [Int]) { guard ensure() else { return }; for m in Set(midis) { _ = stringBuffer(m) } }

    func stopAllVoices() { enqueue(.stopAll(at: Int64(now * sr))) }

    // MARK: engine

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var sr: Double = 44100
    private var started = false
    private var cache: [Int: StringBuffer] = [:]
    private var idCounter = 0
    private func nextId() -> Int { idCounter += 1; return idCounter }

    init(volume: Double) { params.withLock { $0.volume = Float(volume) } }

    @discardableResult
    func ensure() -> Bool {
        if started { return true }
        let outFormat = engine.outputNode.inputFormat(forBus: 0)
        sr = outFormat.sampleRate > 0 ? outFormat.sampleRate : 44100
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        renderState.withLock { $0.dsp = DSPState(sr: sr) }
        let node = AVAudioSourceNode(format: fmt) { [state = renderState, params = params, rendered = renderedSamples] _, _, frameCount, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(frameCount)
            let p = params.withLock { $0 }
            let time = state.withLock { st -> Int64 in
                st.render(out, n, volume: p.volume)
                return st.time
            }
            rendered.withLock { $0 = time }
            // copy mono to any further channels
            for b in buffers.dropFirst() { if let d = b.mData?.assumingMemoryBound(to: Float.self) { d.update(from: out, count: n) } }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 1
        do {
            try engine.start()
            started = true
            source = node
        } catch {
            return false
        }
        return true
    }

    // MARK: render-thread state

    private struct Params { var volume: Float = 0.8 }
    private let params = OSAllocatedUnfairLock(initialState: Params())
    private let renderedSamples = OSAllocatedUnfairLock(initialState: Int64(0))
    private let renderState = OSAllocatedUnfairLock(initialState: RenderState())

    fileprivate enum Command {
        case add(Voice)
        case stop(id: Int, at: Int64)
        case stopAll(at: Int64)
    }

    private func enqueue(_ c: Command) {
        renderState.withLock { st in
            switch c {
            case .add(let v): st.voices.append(v)
            case .stop(let id, let at):
                if let i = st.voices.firstIndex(where: { $0.id == id }) { st.voices[i].stopFrom = max(at, st.time) }
            case .stopAll(let at):
                for i in st.voices.indices where st.voices[i].bus == .guitar { st.voices[i].stopFrom = max(at, st.time) }
            }
        }
    }

    fileprivate func stopVoice(_ id: Int, at time: Double?) {
        let at = Int64((time ?? now) * sr)
        enqueue(.stop(id: id, at: at))
    }

    // MARK: Karplus-Strong

    /// A short burst of filtered noise circulates in a delay line with a soft averaging filter.
    private func stringBuffer(_ midi: Int) -> StringBuffer {
        if let b = cache[midi] { return b }
        let f = Theory.freqOf(midi)
        let N = max(2, Int(floor(sr / f - 0.5)))
        let len = Int(floor(sr * (midi < 52 ? 2.4 : 1.8)))
        var out = [Float](repeating: 0, count: len)
        var line = [Float](repeating: 0, count: N)
        var prev: Float = 0, mean: Float = 0
        for i in 0..<N {
            let r = Float.random(in: -1..<1)
            prev += 0.55 * (r - prev)
            line[i] = prev
            mean += prev
        }
        mean /= Float(N)
        for i in 0..<N { line[i] -= mean }
        let t60 = max(1.0, 3.4 - Double(midi - 40) * 0.055) // low strings ring longer
        let g = Float(pow(0.001, 1 / (f * t60)))
        var idx = 0
        for n in 0..<len {
            let cur = line[idx]
            let nxt = line[idx + 1 == N ? 0 : idx + 1]
            out[n] = cur
            line[idx] = g * 0.5 * (cur + nxt)
            idx = idx + 1 == N ? 0 : idx + 1
        }
        // the averaging filter makes the real period N + 0.5 samples; correct it with the playback rate
        let buf = StringBuffer(samples: out, rate: f * (Double(N) + 0.5) / sr)
        cache[midi] = buf
        return buf
    }
}

enum StrumDirection: String { case down, up }

final class StringBuffer {
    let samples: [Float]
    let rate: Double
    init(samples: [Float], rate: Double) { self.samples = samples; self.rate = rate }
}

enum Waveform { case square, triangle, sine }
enum Bus { case guitar, click, master }

struct EnvPoint { var sample: Int64; var gain: Float }

struct Voice {
    enum Kind { case sample(StringBuffer); case osc(Waveform, Float) }
    let id: Int
    let kind: Kind
    let start: Int64
    var bus: Bus = .guitar
    var gain: Float = 1
    var rate: Double = 1
    var pos: Double = 0
    var phase: Float = 0
    var holdEnd: Int64? = nil      // after this sample the note fades (duration end)
    var fadeMul: Float = 1         // per-sample multiplier during the duration fade
    var stopAt: Int64? = nil       // remove the voice at this sample
    var stopFrom: Int64? = nil     // pause/stop requested: exponential fade from here (time constant 0.03 s)
    var env: [EnvPoint] = []       // oscillator envelope (exponential ramps between points)
    var level: Float = 1           // current envelope multiplier for duration fades

    init(id: Int, kind: Kind, start: Int64) { self.id = id; self.kind = kind; self.start = start }
}

struct RenderState {
    var time: Int64 = 0
    var voices: [Voice] = []
    var dsp: DSPState? = nil

    mutating func render(_ out: UnsafeMutablePointer<Float>, _ n: Int, volume: Float) {
        guard var d = dsp else { for k in 0..<n { out[k] = 0 }; time += Int64(n); return }
        d.render(&voices, &time, out, n, volume: volume)
        dsp = d
    }
}

/// RBJ biquad (peaking / low-pass) — matches Web Audio's BiquadFilterNode formulas.
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    static func lowpass(sr: Double, freq: Double, q: Double) -> Biquad {
        let w0 = 2 * Double.pi * freq / sr
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        let a0 = 1 + alpha
        var f = Biquad()
        f.b0 = Float((1 - cosw) / 2 / a0); f.b1 = Float((1 - cosw) / a0); f.b2 = f.b0
        f.a1 = Float(-2 * cosw / a0); f.a2 = Float((1 - alpha) / a0)
        return f
    }
    static func peaking(sr: Double, freq: Double, q: Double, gainDb: Double) -> Biquad {
        let A = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * freq / sr
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        let a0 = 1 + alpha / A
        var f = Biquad()
        f.b0 = Float((1 + alpha * A) / a0); f.b1 = Float(-2 * cosw / a0); f.b2 = Float((1 - alpha * A) / a0)
        f.a1 = Float(-2 * cosw / a0); f.a2 = Float((1 - alpha / A) / a0)
        return f
    }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// Simple feed-forward compressor (threshold −14 dB, knee 10, ratio 4, attack 4 ms, release 200 ms).
struct Compressor {
    let threshold: Float = -14, knee: Float = 10, ratio: Float = 4
    var attackCoef: Float, releaseCoef: Float
    var envDb: Float = -100
    init(sr: Double) {
        attackCoef = Float(exp(-1 / (0.004 * sr)))
        releaseCoef = Float(exp(-1 / (0.2 * sr)))
    }
    @inline(__always) mutating func process(_ x: Float) -> Float {
        let inDb = 20 * log10(max(abs(x), 1e-6))
        envDb = inDb > envDb ? attackCoef * envDb + (1 - attackCoef) * inDb : releaseCoef * envDb + (1 - releaseCoef) * inDb
        let over = envDb - threshold
        var gainDb: Float = 0
        if over > knee / 2 { gainDb = -(over - over / ratio) }
        else if over > -knee / 2 { let t = over + knee / 2; gainDb = -(1 - 1 / ratio) * t * t / (2 * knee) }
        return x * pow(10, gainDb / 20)
    }
}

struct DSPState {
    let sr: Double
    var body: Biquad
    var lp: Biquad
    var comp: Compressor
    let stopCoef: Float
    var guitar = [Float](repeating: 0, count: 8192)
    init(sr: Double) {
        self.sr = sr
        body = .peaking(sr: sr, freq: 220, q: 1.1, gainDb: 3)
        lp = .lowpass(sr: sr, freq: 5200, q: 0.5)
        comp = Compressor(sr: sr)
        stopCoef = Float(exp(-1 / (0.03 * sr)))
    }

    mutating func render(_ voices: inout [Voice], _ time: inout Int64, _ out: UnsafeMutablePointer<Float>, _ n: Int, volume: Float) {
        let t0 = time
        for k in 0..<n { out[k] = 0 }
        if guitar.count < n { guitar = [Float](repeating: 0, count: n) }
        for k in 0..<n { guitar[k] = 0 }
        var i = 0
        while i < voices.count {
            var v = voices[i]
            var remove = false
            for k in 0..<n {
                let t = t0 + Int64(k)
                if t < v.start { continue }
                if let s = v.stopAt, t >= s { remove = true; break }
                var sample: Float = 0
                switch v.kind {
                case .sample(let buf):
                    let p = Int(v.pos)
                    if p + 1 >= buf.samples.count { remove = true; break }
                    let frac = Float(v.pos - Double(p))
                    sample = buf.samples[p] * (1 - frac) + buf.samples[p + 1] * frac
                    v.pos += v.rate
                    if let h = v.holdEnd, t >= h { v.level *= v.fadeMul }
                    sample *= v.gain * v.level
                case .osc(let wave, let freq):
                    switch wave {
                    case .square: sample = v.phase < 0.5 ? 1 : -1
                    case .triangle: sample = 4 * abs(v.phase - 0.5) - 1
                    case .sine: sample = sin(2 * Float.pi * v.phase)
                    }
                    v.phase += freq / Float(sr)
                    if v.phase >= 1 { v.phase -= 1 }
                    sample *= envGain(v.env, at: t)
                }
                if let sf = v.stopFrom, t >= sf {
                    v.level *= stopCoef
                    if t - sf > Int64(0.2 * sr) { remove = true; break }
                    if case .osc = v.kind { sample *= v.level }
                }
                switch v.bus {
                case .guitar: guitar[k] += sample * 0.9
                case .click: out[k] += sample * 0.55
                case .master: out[k] += sample
                }
            }
            if remove { voices.remove(at: i) } else { voices[i] = v; i += 1 }
        }
        for k in 0..<n {
            let g = lp.process(body.process(guitar[k]))
            let mixed = (out[k] + g) * volume
            out[k] = max(-1, min(1, comp.process(mixed)))
        }
        time = t0 + Int64(n)
    }

    @inline(__always) func envGain(_ env: [EnvPoint], at t: Int64) -> Float {
        guard let first = env.first else { return 1 }
        if t <= first.sample { return first.gain }
        for j in 1..<env.count {
            let a = env[j - 1], b = env[j]
            if t <= b.sample {
                let span = Float(max(1, b.sample - a.sample))
                let u = Float(t - a.sample) / span
                // exponential ramp like Web Audio exponentialRampToValueAtTime
                return a.gain * pow(b.gain / a.gain, u)
            }
        }
        return env.last!.gain
    }
}
