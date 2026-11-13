/* Guitar Quest - sound: plucked-string synthesis (Karplus-Strong), strums and metronome clicks. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory;
  let ctx = null, master = null, guitarBus = null, clickBus = null;
  const cache = new Map();

  function ensure() {
    if (!ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      ctx = new AC({ latencyHint: 'interactive' });
      const comp = ctx.createDynamicsCompressor();
      comp.threshold.value = -14; comp.knee.value = 10; comp.ratio.value = 4;
      comp.attack.value = 0.004; comp.release.value = 0.2;
      master = ctx.createGain();
      master.gain.value = GQ.Store.settings().volume;
      master.connect(comp); comp.connect(ctx.destination);
      // A gentle low-pass and a little body warmth make the plucked string sound less synthetic.
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 5200; lp.Q.value = 0.5;
      const body = ctx.createBiquadFilter(); body.type = 'peaking'; body.frequency.value = 220; body.gain.value = 3; body.Q.value = 1.1;
      guitarBus = ctx.createGain(); guitarBus.gain.value = 0.9;
      guitarBus.connect(body); body.connect(lp); lp.connect(master);
      clickBus = ctx.createGain(); clickBus.gain.value = 0.55; clickBus.connect(master);
    }
    if (ctx.state === 'suspended') ctx.resume();
    return ctx;
  }
  function now() { return ensure() ? ctx.currentTime : 0; }
  function setVolume(v) { if (master) master.gain.setTargetAtTime(v, ctx.currentTime, 0.02); }

  // Karplus-Strong: a short burst of filtered noise circulates in a delay line with a soft averaging filter.
  function stringBuffer(midi) {
    if (cache.has(midi)) return cache.get(midi);
    const sr = ctx.sampleRate;
    const f = T.freqOf(midi);
    const N = Math.max(2, Math.floor(sr / f - 0.5));
    const len = Math.floor(sr * (midi < 52 ? 2.4 : 1.8));
    const out = new Float32Array(len);
    const line = new Float32Array(N);
    let prev = 0, mean = 0;
    for (let i = 0; i < N; i++) { const r = Math.random() * 2 - 1; prev += 0.55 * (r - prev); line[i] = prev; mean += prev; }
    mean /= N;
    for (let i = 0; i < N; i++) line[i] -= mean;
    const t60 = Math.max(1.0, 3.4 - (midi - 40) * 0.055); // low strings ring longer
    const g = Math.pow(0.001, 1 / (f * t60));
    let idx = 0;
    for (let n = 0; n < len; n++) {
      const cur = line[idx];
      const nxt = line[idx + 1 === N ? 0 : idx + 1];
      out[n] = cur;
      line[idx] = g * 0.5 * (cur + nxt);
      idx = idx + 1 === N ? 0 : idx + 1;
    }
    // the averaging filter makes the real period N + 0.5 samples; correct it with the playback rate
    const buf = ctx.createBuffer(1, len, sr);
    buf.copyToChannel(out, 0);
    const entry = { buf, rate: f * (N + 0.5) / sr };
    cache.set(midi, entry);
    return entry;
  }

  // Play one note. Returns a handle with stop(time).
  function pluck(midi, when, opts) {
    if (!ensure()) return null;
    opts = opts || {};
    const t = Math.max(when || 0, ctx.currentTime);
    const s = stringBuffer(midi);
    const src = ctx.createBufferSource();
    src.buffer = s.buf;
    src.playbackRate.value = s.rate;
    const g = ctx.createGain();
    const vel = (opts.velocity || 0.75) * (0.92 + Math.random() * 0.12);
    g.gain.setValueAtTime(vel, t);
    src.connect(g); g.connect(guitarBus);
    src.start(t);
    const dur = opts.duration;
    if (dur) {
      g.gain.setValueAtTime(vel, t + dur);
      g.gain.exponentialRampToValueAtTime(0.0008, t + dur + 0.12);
      src.stop(t + dur + 0.15);
    }
    return { stop(at) { try { const tt = Math.max(at || ctx.currentTime, ctx.currentTime); g.gain.cancelScheduledValues(tt); g.gain.setTargetAtTime(0, tt, 0.03); src.stop(tt + 0.2); } catch (e) { /* already stopped */ } } };
  }

  // midis: low to high. dir 'down' strums low->high, 'up' high->low (lighter).
  function strum(midis, when, opts) {
    if (!ensure()) return [];
    opts = opts || {};
    const order = opts.dir === 'up' ? midis.slice().reverse() : midis;
    const spread = opts.spread || 0.016;
    const vel = (opts.velocity || 0.6) * (opts.dir === 'up' ? 0.75 : 1);
    return order.map((m, i) => pluck(m, (when || ctx.currentTime) + i * spread, { velocity: vel, duration: opts.duration }));
  }

  function click(when, accent) {
    if (!ensure()) return;
    const t = Math.max(when, ctx.currentTime);
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = 'square';
    o.frequency.value = accent ? 1760 : 1180;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(accent ? 0.5 : 0.32, t + 0.002);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.045);
    o.connect(g); g.connect(clickBus);
    o.start(t); o.stop(t + 0.06);
  }

  // Small feedback sounds for games.
  function chime(good) {
    if (!ensure()) return;
    const t = ctx.currentTime;
    const notes = good ? [84, 91] : [52];
    notes.forEach((m, i) => {
      const o = ctx.createOscillator(); const g = ctx.createGain();
      o.type = good ? 'triangle' : 'sine';
      o.frequency.value = T.freqOf(m);
      g.gain.setValueAtTime(0.0001, t + i * 0.08);
      g.gain.exponentialRampToValueAtTime(good ? 0.16 : 0.25, t + i * 0.08 + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.08 + (good ? 0.35 : 0.25));
      o.connect(g); g.connect(master);
      o.start(t + i * 0.08); o.stop(t + i * 0.08 + 0.4);
    });
  }

  function warm(midis) { if (!ensure()) return; midis.forEach((m) => stringBuffer(m)); }

  GQ.Audio = { ensure, now, setVolume, pluck, strum, click, chime, warm, get ctx() { return ctx; } };
})(window.GQ = window.GQ || {});
