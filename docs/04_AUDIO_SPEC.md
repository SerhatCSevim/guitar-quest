# 04 — Sound and playback

Reference: `web/js/audio.js` (synth) and `js/player.js` (transport). No samples are used: the
guitar is synthesised, so the Mac port needs no sound files.

## 1. Signal chain (web)
```
plucks → guitarBus (gain 0.9) → peaking EQ 220 Hz +3 dB Q 1.1 → low-pass 5200 Hz Q 0.5 ┐
clicks → clickBus (gain 0.55) ─────────────────────────────────────────────────────────┼→ master (volume setting) → compressor → output
game chimes ───────────────────────────────────────────────────────────────────────────┘
compressor: threshold −14 dB, knee 10, ratio 4, attack 4 ms, release 200 ms
```

## 2. Plucked string (Karplus–Strong), one buffer per MIDI note, cached
```
f      = 440 · 2^((midi − 69)/12)
N      = max(2, floor(sr / f − 0.5))                 // delay-line length
length = sr · (midi < 52 ? 2.4 : 1.8) seconds
excite : N samples of white noise, one-pole low-pass  prev += 0.55·(r − prev); remove DC (subtract mean)
t60    = max(1.0, 3.4 − (midi − 40)·0.055)            // low strings ring longer
g      = 0.001^(1 / (f · t60))
loop   : out[n] = line[i];  line[i] = g · 0.5 · (line[i] + line[i+1 mod N]);  i = i+1 mod N
pitch  : the averaging filter makes the period N + 0.5 samples → play back at rate f·(N + 0.5)/sr
```
- Note gain = `(velocity or 0.75) · (0.92 + random·0.12)` (small human variation).
- With a duration: hold, then exponential fade to 0.0008 over 0.12 s, stop 0.15 s after the duration.
- Stop handle (pause/stop): fade to 0 with time constant 0.03 s, stop 0.2 s later.

## 3. Strum
`strum(midis low→high, when, {dir, spread, velocity, duration})`: down = low→high, up = high→low with velocity ×0.75;
default spread 16 ms between strings. The chord pages use spread 22 ms (down) / 12 ms (up), velocity 0.7,
duration 2.2 s. Jam: velocity 0.75 on beat 1, 0.55 otherwise.

## 4. Metronome click and game chimes
- Click: square wave 1760 Hz (bar start) / 1180 Hz (other beats); gain 0.0001 → 0.5 (accent) or 0.32 in 2 ms →
  0.0001 at 45 ms.
- Chime: correct = triangle MIDI 84 then 91 (+80 ms), peak 0.16, 0.35 s; wrong = sine MIDI 52, peak 0.25, 0.25 s.

## 5. Transport (`player.js`)
Input: items `[{ i, beat, beats, rest, midis, strum?, dir?, velocity? }]`, total beats, beats per bar (4).
State: `bpm, loop, metronome, countIn, sound, trainer {on, step, target}`.
- **Look-ahead scheduler**: every 25 ms schedule everything that starts within the next 0.12 s on the audio clock.
- **Play(from index)**: start time = now + 0.08 s; if count-in, one bar of clicks before the first item;
  "origin" = audio time of beat 0 (`start + countBeats·spb − startBeat·spb`).
- Clicks: one per integer beat (accent on bar start), scheduled while metronome is on **or** during count-in. The
  click counter always follows the music, so switching the metronome on mid-play never fires a burst of late clicks.
- Notes: single notes play `beats·spb + 0.12 s`; strums `beats·spb + 0.05 s`; only if `sound` is on.
- End of pass: if loop → next pass starts exactly at the end time from the same start index; the speed trainer
  raises bpm by `step` (up to `target`) before each new pass and reports it; no count-in on repeats.
  Else stop when the end time is reached.
- Position callback every animation frame: current item index (or −1), count-down number during count-in.
- Pause keeps the current index as the next start; Stop resets to 0; Seek(i) restarts from i (no count-in if
  it was playing); changing the tempo while playing = pause + play from the current item without count-in.

## 6. Mac mapping (design notes; the built version is in `Sources/GuitarQuest/Audio`)
- AVAudioEngine. Two options for sample-accurate timing:
  1. **Recommended:** one `AVAudioSourceNode` that renders a small voice mixer itself (pre-rendered KS buffers as
     `[Float]`, a sorted event list with sample start times, metronome clicks synthesised in the render block).
     Timing is then exact and pause/seek is just a change of the play head.
  2. `AVAudioPlayerNode.scheduleBuffer(_:at:)` with `AVAudioTime(sampleTime:atRate:)` per note — simpler but many
     nodes/buffers for chords.
- EQ: `AVAudioUnitEQ` (one parametric band 220 Hz/+3 dB, one low-pass band 5200 Hz). Compressor: Apple's
  Dynamics Processor audio unit via `AVAudioUnitEffect`. Exact parameter equivalence to Web Audio is not
  guaranteed — tune by ear against the web version.
- No autoplay limit on macOS, so the "first click unlocks sound" step disappears.
