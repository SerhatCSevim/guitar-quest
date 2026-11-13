/* Guitar Quest - builds playable scores (scale exercises, songs). Pure, no DOM.
   Time is counted in ticks: 12 ticks = 1 quarter-note beat, 48 ticks = one 4/4 bar. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory;
  const TPB = 12, BAR = 48;
  const DUR = { 'w': 48, 'h.': 36, 'h': 24, 'q.': 18, 'q': 12, '8.': 9, '8': 6, '16': 3 };
  const RHYTHMS = {
    q: { name: 'Quarter notes', unit: 12, tuplet: 0 },
    e: { name: 'Eighth notes', unit: 6, tuplet: 0 },
    t: { name: 'Triplets', unit: 4, tuplet: 3 },
    s: { name: 'Sixteenth notes', unit: 3, tuplet: 0 },
  };
  const PATTERNS = {
    updown: 'Up and down',
    up: 'Up only',
    down: 'Down only',
    groups3: 'Groups of 3',
    groups4: 'Groups of 4',
    thirds: 'Thirds (skip a note)',
  };

  function noteObj(string, fret, spelled) {
    return { string, fret, midi: T.midiAt(string, fret), spelled };
  }

  // Assign ticks and split events into bars. Every bar must add up to exactly one 4/4 bar.
  function finalize(events, meta) {
    let tick = 0;
    const measures = [];
    events.forEach((ev, i) => {
      ev.i = i;
      ev.tick = tick;
      ev.measure = Math.floor(tick / BAR);
      if (Math.floor((tick + ev.dur - 1) / BAR) !== ev.measure) throw new Error('Event ' + i + ' crosses a bar line');
      (measures[ev.measure] = measures[ev.measure] || []).push(i);
      tick += ev.dur;
    });
    if (tick % BAR !== 0) throw new Error('Score does not end on a bar line (' + tick + ' ticks)');
    return Object.assign({ time: [4, 4], tpb: TPB, bar: BAR, events, measures, totalTicks: tick }, meta);
  }

  function longNote(remaining) {
    // duration that fills the rest of a bar starting on a beat
    if ([48, 36, 24, 12].indexOf(remaining) < 0) throw new Error('Cannot fill ' + remaining);
    return remaining;
  }

  /* opts: { tonic: 'A', scaleId, shapeId, pattern, rhythm: 'q'|'e'|'t'|'s', range: 'root'|'full', tempo } */
  function buildScaleScore(opts) {
    const tonic = T.parseNote(opts.tonic);
    const sc = T.SCALES[opts.scaleId];
    const shape = T.buildShape(tonic, opts.scaleId, opts.shapeId, 24);
    let notes = shape.notes;
    if (opts.shapeId === 'neck') throw new Error('Pick a shape to practise');
    if (opts.range === 'root') notes = T.rootToRoot(notes);
    const idx = T.patternIndices(notes.length, opts.pattern);
    const r = RHYTHMS[opts.rhythm];
    const events = [];
    const body = idx.slice(0, -1);
    const last = idx[idx.length - 1];
    body.forEach((k) => {
      const n = notes[k];
      events.push({ dur: r.unit, tuplet: r.tuplet, notes: [noteObj(n.string, n.fret, n.spelled)] });
    });
    let tick = body.length * r.unit;
    while (tick % TPB !== 0) { events.push({ dur: r.unit, tuplet: r.tuplet, rest: true, notes: [] }); tick += r.unit; }
    const n = notes[last];
    events.push({ dur: longNote(BAR - (tick % BAR)), tuplet: 0, notes: [noteObj(n.string, n.fret, n.spelled)] });
    const shapeName = (T.shapeOptions(opts.scaleId).find((o) => o.id === opts.shapeId) || {}).name;
    return finalize(events, {
      title: T.noteLabel(tonic) + ' ' + sc.name.toLowerCase(),
      subtitle: shapeName + ' - ' + PATTERNS[opts.pattern] + ' - ' + r.name.toLowerCase(),
      keySig: T.keySignature(tonic, sc.family),
      tempo: opts.tempo || 80,
      source: 'scale',
    });
  }

  function parseToken(tok) {
    const m = /^(r|[A-G](?:#|b)?)(\d)?(?::(w|h\.|h|q\.|q|8\.|8|16))?(?:@(\d)\/(\d+))?$/.exec(tok);
    if (!m) throw new Error('Bad token ' + tok);
    const dur = DUR[m[3] || 'q'];
    if (m[1] === 'r') return { dur, rest: true, notes: [] };
    const spelled = T.parseNote(m[1]);
    const octave = Number(m[2]);
    const midi = (octave + 1) * 12 + T.LETTER_PC[spelled.l] + spelled.a;
    const pos = m[4] ? { string: Number(m[4]), fret: Number(m[5]) } : T.lowestPosition(midi);
    if (!pos || T.midiAt(pos.string, pos.fret) !== midi) throw new Error('Unplayable note ' + tok);
    return { dur, notes: [noteObj(pos.string, pos.fret, spelled)] };
  }

  function buildSongScore(song) {
    const events = [];
    song.notes.split('|').forEach((bar, bi) => {
      const toks = bar.trim().split(/\s+/).filter(Boolean);
      let sum = 0;
      toks.forEach((t) => { const ev = parseToken(t); ev.tuplet = 0; sum += ev.dur; events.push(ev); });
      if (sum !== BAR) throw new Error(song.id + ': bar ' + (bi + 1) + ' has ' + sum + ' ticks');
    });
    const tonic = T.parseNote(song.key);
    return finalize(events, {
      title: song.title, subtitle: song.origin + ' - ' + song.strings,
      keySig: T.keySignature(tonic, song.family), tempo: song.tempo, source: 'song',
    });
  }

  // Seconds-free timeline for the player: start/duration in beats.
  function timeline(score) {
    return score.events.map((ev) => ({
      i: ev.i, beat: ev.tick / TPB, beats: ev.dur / TPB, rest: !!ev.rest,
      midis: ev.notes.map((n) => n.midi),
    }));
  }

  GQ.Exercises = { TPB, BAR, DUR, RHYTHMS, PATTERNS, buildScaleScore, buildSongScore, parseToken, finalize, timeline };
})(typeof window !== 'undefined' ? (window.GQ = window.GQ || {}) : (globalThis.GQ = globalThis.GQ || {}));
