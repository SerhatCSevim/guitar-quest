/* Guitar Quest - transport: schedules notes and metronome clicks ahead of time with the Web Audio clock. */
(function (GQ) {
  'use strict';
  const A = GQ.Audio;
  const LOOKAHEAD = 0.12, TICK_MS = 25;

  class Transport {
    constructor(opts) {
      this.opts = Object.assign({ onPosition: null, onState: null, onLoop: null }, opts || {});
      this.items = [];          // [{i, beat, beats, rest, midis, strum?, dir?}]
      this.totalBeats = 0;
      this.beatsPerBar = 4;
      this.bpm = 80;
      this.loop = false;
      this.metronome = true;
      this.countIn = true;
      this.sound = true;
      this.trainer = { on: false, step: 5, target: 120 };
      this.playing = false;
      this.startIndex = 0;
      this._raf = null;
      this._timer = null;
      this._handles = [];
      this._pos = -1;
    }

    load(items, totalBeats, beatsPerBar) {
      this.stop();
      this.items = items;
      this.totalBeats = totalBeats;
      this.beatsPerBar = beatsPerBar || 4;
      this.startIndex = 0;
    }

    setTempo(bpm) {
      bpm = Math.max(30, Math.min(240, Math.round(bpm)));
      if (bpm === this.bpm) return;
      const wasPlaying = this.playing;
      const at = this.currentIndex();
      this.bpm = bpm;
      if (wasPlaying) { this.pause(); this.play(at, true); }
    }

    currentIndex() { return this._pos >= 0 ? this._pos : this.startIndex; }

    play(fromIndex, skipCountIn) {
      if (!A.ensure() || !this.items.length) return;
      if (this.playing) return;
      if (fromIndex !== undefined && fromIndex !== null) this.startIndex = Math.max(0, Math.min(this.items.length - 1, fromIndex));
      A.warm(Array.from(new Set([].concat.apply([], this.items.map((it) => it.midis)))));
      this.playing = true;
      const spb = 60 / this.bpm;
      const startBeat = this.items[this.startIndex].beat;
      const ctxNow = A.now() + 0.08;
      const countBeats = this.countIn && !skipCountIn ? this.beatsPerBar : 0;
      // pass = one run through the score; origin is the audio time of beat 0
      this.pass = { origin: ctxNow + countBeats * spb - startBeat * spb, spb, fromBeat: startBeat };
      this.nextItem = this.startIndex;
      this.nextClick = Math.ceil(startBeat - countBeats - 1e-9);
      this.countInUntil = startBeat;
      this._schedule();
      this._timer = setInterval(() => this._schedule(), TICK_MS);
      this._frame();
      this._emitState();
    }

    _schedule() {
      if (!this.playing) return;
      const horizon = A.now() + LOOKAHEAD;
      const p = this.pass;
      // metronome (including the count-in bar before the start). The click counter always follows the
      // music, so switching the metronome on mid-play does not fire a burst of late clicks.
      const curBeat = (A.now() - p.origin) / p.spb;
      if (this.nextClick < Math.floor(curBeat)) this.nextClick = Math.ceil(curBeat - 1e-9);
      while (this.nextClick < this.totalBeats) {
        const t = p.origin + this.nextClick * p.spb;
        if (t > horizon) break;
        if (this.metronome || this.nextClick < this.countInUntil) {
          const inBar = ((this.nextClick % this.beatsPerBar) + this.beatsPerBar) % this.beatsPerBar;
          A.click(t, inBar === 0);
        }
        this.nextClick++;
      }
      // notes
      while (this.nextItem < this.items.length) {
        const it = this.items[this.nextItem];
        const t = p.origin + it.beat * p.spb;
        if (t > horizon) break;
        if (this.sound && !it.rest && it.midis.length) {
          const dur = it.beats * p.spb;
          if (it.strum) this._handles = this._handles.concat(A.strum(it.midis, t, { dir: it.dir, duration: dur + 0.05, velocity: it.velocity }));
          else it.midis.forEach((m) => this._handles.push(A.pluck(m, t, { duration: dur + 0.12 })));
          if (this._handles.length > 64) this._handles = this._handles.slice(-64);
        }
        this.nextItem++;
      }
      // end of pass
      const endT = p.origin + this.totalBeats * p.spb;
      if (this.nextItem >= this.items.length && endT <= horizon) {
        if (this.loop) {
          if (this.trainer.on && this.bpm < this.trainer.target) {
            this.bpm = Math.min(this.trainer.target, this.bpm + this.trainer.step);
            if (this.opts.onLoop) this.opts.onLoop(this.bpm);
          }
          const spb = 60 / this.bpm;
          const loopStart = this.items[this.startIndex].beat;
          this.pass = { origin: endT - loopStart * spb, spb, fromBeat: loopStart };
          this.nextItem = this.startIndex;
          this.nextClick = Math.ceil(loopStart - 1e-9);
          this.countInUntil = loopStart;
        } else if (A.now() >= endT) {
          this.stop();
        }
      }
    }

    _frame() {
      if (!this.playing) return;
      const p = this.pass;
      const beat = (A.now() - p.origin) / p.spb;
      let idx = -1;
      if (beat >= p.fromBeat - 1e-6) {
        for (let k = this.startIndex; k < this.items.length; k++) {
          const it = this.items[k];
          if (beat >= it.beat - 1e-6 && beat < it.beat + it.beats) { idx = k; break; }
          if (it.beat > beat) break;
        }
      }
      const countdown = beat < p.fromBeat ? Math.ceil(p.fromBeat - beat) : 0;
      if (idx !== this._pos || countdown !== this._countdown) {
        this._pos = idx;
        this._countdown = countdown;
        if (this.opts.onPosition) this.opts.onPosition(idx, countdown, beat);
      }
      this._raf = requestAnimationFrame(() => this._frame());
    }

    pause() {
      if (!this.playing) return;
      this.playing = false;
      clearInterval(this._timer); cancelAnimationFrame(this._raf);
      const t = A.now();
      this._handles.forEach((h) => h && h.stop(t));
      this._handles = [];
      if (this._pos >= 0) this.startIndex = this._pos;
      this._emitState();
    }

    stop() {
      const was = this.playing;
      this.playing = false;
      clearInterval(this._timer); cancelAnimationFrame(this._raf);
      const t = A.now();
      this._handles.forEach((h) => h && h.stop(t));
      this._handles = [];
      this.startIndex = 0;
      this._pos = -1;
      if (this.opts.onPosition) this.opts.onPosition(-1, 0, 0);
      if (was) this._emitState();
    }

    seek(i) {
      const was = this.playing;
      if (was) this.pause();
      this.startIndex = Math.max(0, Math.min(this.items.length - 1, i));
      this._pos = -1;
      if (this.opts.onPosition) this.opts.onPosition(this.startIndex, 0, this.items[this.startIndex] ? this.items[this.startIndex].beat : 0, true);
      if (was) this.play(this.startIndex, true);
    }

    _emitState() { if (this.opts.onState) this.opts.onState(this.playing); }
  }

  GQ.Transport = Transport;
})(window.GQ = window.GQ || {});
