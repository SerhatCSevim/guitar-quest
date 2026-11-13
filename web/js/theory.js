/* Guitar Quest - music theory core. Pure functions, no DOM (also loaded by tests in Node). */
(function (GQ) {
  'use strict';

  const LETTERS = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  const LETTER_PC = [0, 2, 4, 5, 7, 9, 11];
  const SOLFEGE = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'];
  const MAJOR_SEMIS = [0, 2, 4, 5, 7, 9, 11];

  // Standard tuning. String 1 = high e (thinnest) ... string 6 = low E (thickest).
  const TUNING = [null, 64, 59, 55, 50, 45, 40];
  const OPEN_NAMES = [null, 'e', 'B', 'G', 'D', 'A', 'E'];

  const mod = (n, m) => ((n % m) + m) % m;

  function midiAt(string, fret) { return TUNING[string] + fret; }
  function freqOf(midi) { return 440 * Math.pow(2, (midi - 69) / 12); }

  /* ---------- spelled notes: { l: letter index 0..6, a: alteration -2..2 } ---------- */

  const ACC_PARSE = { '': 0, '#': 1, '♯': 1, '##': 2, 'x': 2, '𝄪': 2, 'b': -1, '♭': -1, 'bb': -2, '𝄫': -2 };
  const ACC_UNI = { '-2': '𝄫', '-1': '♭', '0': '', '1': '♯', '2': '𝄪' };
  const ACC_ASCII = { '-2': 'bb', '-1': 'b', '0': '', '1': '#', '2': '##' };

  function parseNote(name) {
    const m = /^([A-Ga-g])(##|#|x|bb|b|♯|♭|𝄪|𝄫)?$/.exec(String(name).trim());
    if (!m) throw new Error('Bad note name: ' + name);
    return { l: LETTERS.indexOf(m[1].toUpperCase()), a: ACC_PARSE[m[2] || ''] };
  }
  function notePc(n) { return mod(LETTER_PC[n.l] + n.a, 12); }
  function accText(a, ascii) { return (ascii ? ACC_ASCII : ACC_UNI)[a]; }
  function sameNote(x, y) { return x.l === y.l && x.a === y.a; }

  // naming: 'letters' | 'solfege' | 'both'
  function noteLabel(n, naming) {
    const acc = accText(n.a);
    if (naming === 'solfege') return SOLFEGE[n.l] + acc;
    if (naming === 'both') return LETTERS[n.l] + acc + ' (' + SOLFEGE[n.l] + acc + ')';
    return LETTERS[n.l] + acc;
  }
  function noteAscii(n) { return LETTERS[n.l] + accText(n.a, true); }

  const SHARP_SPELL = [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [3, 0], [3, 1], [4, 0], [4, 1], [5, 0], [5, 1], [6, 0]];
  const FLAT_SPELL = [[0, 0], [1, -1], [1, 0], [2, -1], [2, 0], [3, 0], [4, -1], [4, 0], [5, -1], [5, 0], [6, -1], [6, 0]];
  function spellPc(pc, pref) {
    const t = (pref === 'flat' ? FLAT_SPELL : SHARP_SPELL)[mod(pc, 12)];
    return { l: t[0], a: t[1] };
  }
  function isNaturalPc(pc) { return SHARP_SPELL[mod(pc, 12)][1] === 0; }

  // Label for an unspelled pitch class. pref: 'sharp' | 'flat' | 'both'
  function pcLabel(pc, naming, pref) {
    if (isNaturalPc(pc)) return noteLabel(spellPc(pc), naming);
    if (pref === 'both') return noteLabel(spellPc(pc, 'sharp'), naming) + '/' + noteLabel(spellPc(pc, 'flat'), naming);
    return noteLabel(spellPc(pc, pref), naming);
  }

  // The note `semis` semitones above tonic, written on scale degree `degree` (1-based).
  function degreeNote(tonic, degree, semis) {
    const l = mod(tonic.l + degree - 1, 7);
    const target = mod(notePc(tonic) + semis, 12);
    const a = mod(target - LETTER_PC[l] + 6, 12) - 6;
    return { l, a };
  }

  // Written octave of a spelled note that sounds at `midi` (scientific pitch, C4 = 60).
  function octaveOf(midi, n) {
    const natural = midi - n.a - LETTER_PC[n.l];
    return Math.round(natural / 12) - 1;
  }
  // Diatonic staff position; 0 = E4 (bottom line of the treble staff), 8 = F5 (top line).
  function staffPos(l, octave) { return octave * 7 + l - (4 * 7 + 2); }

  function degreeLabel(degree, semis) {
    const d = semis - MAJOR_SEMIS[(degree - 1) % 7] - 12 * Math.floor((degree - 1) / 7);
    return (d < 0 ? '♭'.repeat(-d) : '♯'.repeat(d)) + degree;
  }

  /* ---------- scales ---------- */

  const SCALES = {
    major: { name: 'Major', family: 'major', steps: [[1, 0], [2, 2], [3, 4], [4, 5], [5, 7], [6, 9], [7, 11]] },
    minor: { name: 'Natural minor', family: 'minor', steps: [[1, 0], [2, 2], [3, 3], [4, 5], [5, 7], [6, 8], [7, 10]] },
    majorPent: { name: 'Major pentatonic', family: 'major', pent: true, steps: [[1, 0], [2, 2], [3, 4], [5, 7], [6, 9]] },
    minorPent: { name: 'Minor pentatonic', family: 'minor', pent: true, steps: [[1, 0], [3, 3], [4, 5], [5, 7], [7, 10]] },
    blues: { name: 'Blues', family: 'minor', pent: true, blues: true, steps: [[1, 0], [3, 3], [4, 5], [5, 6], [5, 7], [7, 10]] },
  };

  function scaleNotes(tonic, scaleId) {
    return SCALES[scaleId].steps.map(([deg, semis]) => {
      const n = degreeNote(tonic, deg, semis);
      return { l: n.l, a: n.a, degree: deg, semis, label: degreeLabel(deg, semis), pc: notePc(n) };
    });
  }

  // Step sizes between neighbouring scale notes, including the step back to the octave.
  function stepPattern(scaleId) {
    const s = SCALES[scaleId].steps.map((x) => x[1]).concat([12]);
    const names = { 1: 'H', 2: 'W', 3: 'W+H' };
    const out = [];
    for (let i = 1; i < s.length; i++) out.push(names[s[i] - s[i - 1]] || String(s[i] - s[i - 1]));
    return out;
  }

  /* ---------- keys ---------- */

  const MAJOR_KEYS = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
  const MINOR_KEYS = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B'];
  function keyNames(family) { return family === 'minor' ? MINOR_KEYS : MAJOR_KEYS; }

  function relativeMinorOf(majorTonic) { return degreeNote(majorTonic, 6, 9); }
  function relativeMajorOf(minorTonic) { return degreeNote(minorTonic, 3, 3); }

  const SHARP_ORDER = [3, 0, 4, 1, 5, 2, 6]; // F C G D A E B
  const FLAT_ORDER = [6, 2, 5, 1, 4, 0, 3]; // B E A D G C F

  function keySignature(tonic, family) {
    const majorTonic = family === 'minor' ? relativeMajorOf(tonic) : tonic;
    const sc = scaleNotes(majorTonic, 'major');
    const alters = [0, 0, 0, 0, 0, 0, 0];
    sc.forEach((n) => { alters[n.l] = n.a; });
    const sharps = SHARP_ORDER.filter((l) => alters[l] > 0);
    const flats = FLAT_ORDER.filter((l) => alters[l] < 0);
    if (sharps.length && flats.length) throw new Error('Mixed key signature');
    const list = sharps.length ? sharps.map((l) => ({ l, a: alters[l] })) : flats.map((l) => ({ l, a: alters[l] }));
    return { fifths: sharps.length || -flats.length, alters, list, majorTonic };
  }

  /* ---------- chords ---------- */

  const CHORD_TYPES = {
    maj: { name: 'Major', sym: '', tones: [[1, 0], [3, 4], [5, 7]] },
    min: { name: 'Minor', sym: 'm', tones: [[1, 0], [3, 3], [5, 7]] },
    dim: { name: 'Diminished', sym: 'dim', tones: [[1, 0], [3, 3], [5, 6]] },
    aug: { name: 'Augmented', sym: 'aug', tones: [[1, 0], [3, 4], [5, 8]] },
    sus2: { name: 'Suspended 2nd', sym: 'sus2', tones: [[1, 0], [2, 2], [5, 7]] },
    sus4: { name: 'Suspended 4th', sym: 'sus4', tones: [[1, 0], [4, 5], [5, 7]] },
    power: { name: 'Power chord', sym: '5', tones: [[1, 0], [5, 7]] },
    dom7: { name: 'Dominant 7th', sym: '7', tones: [[1, 0], [3, 4], [5, 7], [7, 10]] },
    maj7: { name: 'Major 7th', sym: 'maj7', tones: [[1, 0], [3, 4], [5, 7], [7, 11]] },
    min7: { name: 'Minor 7th', sym: 'm7', tones: [[1, 0], [3, 3], [5, 7], [7, 10]] },
    m7b5: { name: 'Half-diminished 7th', sym: 'm7♭5', tones: [[1, 0], [3, 3], [5, 6], [7, 10]] },
    dim7: { name: 'Diminished 7th', sym: 'dim7', tones: [[1, 0], [3, 3], [5, 6], [7, 9]] },
  };

  function chordTones(root, type) {
    return CHORD_TYPES[type].tones.map(([deg, semis]) => {
      const n = degreeNote(root, deg, semis);
      return { l: n.l, a: n.a, degree: deg, semis, label: degreeLabel(deg, semis), pc: notePc(n) };
    });
  }
  function chordSymbol(root, type, naming) { return noteLabel(root, naming) + CHORD_TYPES[type].sym; }
  function chordFormula(type) { return CHORD_TYPES[type].tones.map(([d, s]) => degreeLabel(d, s)); }

  function typeFromIntervals(semis) {
    const key = semis.join(',');
    const table = {
      '4,7': 'maj', '3,7': 'min', '3,6': 'dim', '4,8': 'aug',
      '4,7,11': 'maj7', '3,7,10': 'min7', '4,7,10': 'dom7', '3,6,10': 'm7b5', '3,6,9': 'dim7',
    };
    return table[key] || null;
  }

  const ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];
  function romanFor(degreeIndex, type) {
    let r = ROMAN[degreeIndex];
    const lower = type === 'min' || type === 'dim' || type === 'min7' || type === 'm7b5' || type === 'dim7';
    if (lower) r = r.toLowerCase();
    if (type === 'dim') r += '°';
    else if (type === 'aug') r += '+';
    else if (type === 'maj7') r += 'maj7';
    else if (type === 'dom7' || type === 'min7') r += '7';
    else if (type === 'm7b5') r += 'ø7';
    else if (type === 'dim7') r += '°7';
    return r;
  }

  // Chords built on every step of the major or natural-minor scale.
  function harmonize(tonic, family, sevenths) {
    const sc = scaleNotes(tonic, family === 'minor' ? 'minor' : 'major');
    return sc.map((root, i) => {
      const stack = [2, 4].concat(sevenths ? [6] : []).map((k) => sc[(i + k) % 7]);
      const semis = stack.map((n) => mod(n.pc - root.pc, 12));
      const type = typeFromIntervals(semis);
      return { degree: i + 1, root: { l: root.l, a: root.a }, type, roman: romanFor(i, type) };
    });
  }

  /* ---------- fretboard ---------- */

  function positionsOfMidi(midi, maxFret) {
    const out = [];
    for (let s = 1; s <= 6; s++) {
      const f = midi - TUNING[s];
      if (f >= 0 && f <= maxFret) out.push({ string: s, fret: f });
    }
    return out;
  }
  function positionsOfPc(pc, maxFret) {
    const out = [];
    for (let s = 1; s <= 6; s++) {
      for (let f = 0; f <= maxFret; f++) if (mod(TUNING[s] + f, 12) === pc) out.push({ string: s, fret: f });
    }
    return out;
  }
  // First-position style choice: the lowest fret that can play the pitch.
  function lowestPosition(midi) {
    const all = positionsOfMidi(midi, 24);
    if (!all.length) return null;
    return all.reduce((best, p) => (p.fret < best.fret ? p : best));
  }

  /* ---------- scale shapes ---------- */

  function shapeOptions(scaleId) {
    const sc = SCALES[scaleId];
    const opts = [{ id: 'neck', name: 'Whole neck' }];
    if (sc.pent) {
      for (let k = 1; k <= 5; k++) opts.push({ id: 'box' + k, name: 'Shape ' + k });
    } else {
      opts.push({ id: 'open', name: 'Open position' });
      opts.push({ id: 'r6', name: 'Root on 6th string' });
      opts.push({ id: 'r5', name: 'Root on 5th string' });
      for (let k = 1; k <= 7; k++) opts.push({ id: '3nps' + k, name: '3 notes per string - form ' + k });
    }
    return opts;
  }

  function decorate(list, notesByPc, tonicPc) {
    return list.map((p) => {
      const midi = midiAt(p.string, p.fret);
      const n = notesByPc.get(mod(midi, 12));
      return {
        string: p.string, fret: p.fret, midi, pc: n.pc,
        spelled: { l: n.l, a: n.a }, degree: n.degree, label: n.label, isRoot: n.pc === tonicPc,
      };
    });
  }

  // Walk upward from (low E, startFret) collecting scale tones, `perString` on each string.
  function sequentialShape(pcSet, startFret, perString) {
    const seq = [];
    let m = TUNING[6] + startFret;
    while (seq.length < perString * 6) {
      if (pcSet.has(mod(m, 12))) seq.push(m);
      m++;
    }
    return seq.map((midi, i) => {
      const s = 6 - Math.floor(i / perString);
      return { string: s, fret: midi - TUNING[s] };
    });
  }

  function windowShape(pcSet, lo, hi) {
    const best = new Map();
    for (let s = 6; s >= 1; s--) {
      for (let f = Math.max(0, lo); f <= hi; f++) {
        const midi = midiAt(s, f);
        if (!pcSet.has(mod(midi, 12))) continue;
        const cur = best.get(midi);
        // The same pitch can appear on G (top of window) and B (bottom of window): keep the B-string one.
        if (!cur || s < cur.string) best.set(midi, { string: s, fret: f });
      }
    }
    return Array.from(best.values());
  }

  function buildShape(tonic, scaleId, shapeId, maxFret) {
    maxFret = maxFret || 15;
    const sc = SCALES[scaleId];
    const notes = scaleNotes(tonic, scaleId);
    const byPc = new Map(notes.map((n) => [n.pc, n]));
    const pcSet = new Set(byPc.keys());
    const tonicPc = notePc(tonic);
    let list;

    if (shapeId === 'neck') {
      list = [];
      for (let s = 6; s >= 1; s--) for (let f = 0; f <= maxFret; f++) if (pcSet.has(mod(midiAt(s, f), 12))) list.push({ string: s, fret: f });
    } else if (shapeId === 'open') {
      list = windowShape(pcSet, 0, 4);
    } else if (shapeId === 'r6' || shapeId === 'r5') {
      const s = shapeId === 'r6' ? 6 : 5;
      let r = mod(tonicPc - TUNING[s], 12);
      if (r === 0) r = 12;
      list = windowShape(pcSet, r - 1, r + 3);
    } else if (/^box\d$/.test(shapeId)) {
      const k = Number(shapeId.slice(3));
      // Shapes are numbered from the minor-pentatonic root on the 6th string (shared by relative major).
      const minorTonic = sc.family === 'major' ? relativeMinorOf(tonic) : tonic;
      const minorPent = scaleNotes(minorTonic, 'minorPent');
      const pentSet = new Set(minorPent.map((n) => n.pc));
      const startFret = mod(minorPent[k - 1].pc - TUNING[6], 12);
      const shape1Fret = mod(minorPent[0].pc - TUNING[6], 12);
      list = sequentialShape(pentSet, startFret, 2);
      const lowest = Math.min.apply(null, list.map((p) => p.fret));
      const highest = Math.max.apply(null, list.map((p) => p.fret));
      // Near the nut a 2-per-string walk can fall below an open string: play it an octave up instead.
      // Shapes that sit below shape 1 also move up when they still fit, so the shapes follow each other up the neck.
      if (lowest < 0 || (k > 1 && startFret < shape1Fret && highest + 12 <= maxFret)) {
        list = list.map((p) => ({ string: p.string, fret: p.fret + 12 }));
      }
      if (sc.blues) {
        const frets = list.map((p) => p.fret);
        const lo = Math.min.apply(null, frets), hi = Math.max.apply(null, frets);
        const bluePc = mod(notePc(minorTonic) + 6, 12);
        for (let s = 6; s >= 1; s--) for (let f = lo; f <= hi; f++) if (mod(midiAt(s, f), 12) === bluePc) list.push({ string: s, fret: f });
      }
    } else if (/^3nps\d$/.test(shapeId)) {
      const k = Number(shapeId.slice(4));
      const startFret = mod(notes[k - 1].pc - TUNING[6], 12);
      list = sequentialShape(pcSet, startFret, 3);
    } else {
      throw new Error('Unknown shape ' + shapeId);
    }

    const out = decorate(list, byPc, tonicPc).sort((a, b) => a.midi - b.midi || b.string - a.string);
    const frets = out.map((n) => n.fret);
    return { notes: out, minFret: Math.min.apply(null, frets), maxFret: Math.max.apply(null, frets) };
  }

  // Keep only the part of an (ascending) shape between its lowest and highest root.
  function rootToRoot(notes) {
    const idx = [];
    notes.forEach((n, i) => { if (n.isRoot) idx.push(i); });
    if (idx.length < 2) return notes.slice();
    return notes.slice(idx[0], idx[idx.length - 1] + 1);
  }

  // Note-index sequences for practice patterns over n ascending notes.
  function patternIndices(n, pattern) {
    const up = [], down = [];
    for (let i = 0; i < n; i++) up.push(i);
    for (let i = n - 1; i >= 0; i--) down.push(i);
    const out = [];
    const group = (size) => {
      if (n < size) return up.concat(down.slice(1));
      for (let i = 0; i + size <= n; i++) for (let j = 0; j < size; j++) out.push(i + j);
      for (let i = n - 1; i - size + 1 >= 0; i--) for (let j = 0; j < size; j++) out.push(i - j);
      return out;
    };
    switch (pattern) {
      case 'up': return up;
      case 'down': return down;
      case 'updown': return up.concat(down.slice(1));
      case 'groups3': return group(3);
      case 'groups4': return group(4);
      case 'thirds':
        if (n < 3) return up.concat(down.slice(1));
        for (let i = 0; i + 2 < n; i++) out.push(i, i + 2);
        for (let i = n - 1; i - 2 >= 0; i--) out.push(i, i - 2);
        return out;
      default: throw new Error('Unknown pattern ' + pattern);
    }
  }

  GQ.Theory = {
    LETTERS, LETTER_PC, SOLFEGE, MAJOR_SEMIS, TUNING, OPEN_NAMES, SCALES, CHORD_TYPES,
    MAJOR_KEYS, MINOR_KEYS, SHARP_ORDER, FLAT_ORDER,
    mod, midiAt, freqOf, parseNote, notePc, accText, sameNote, noteLabel, noteAscii, spellPc, isNaturalPc, pcLabel,
    degreeNote, octaveOf, staffPos, degreeLabel, scaleNotes, stepPattern, keyNames,
    relativeMinorOf, relativeMajorOf, keySignature, chordTones, chordSymbol, chordFormula, typeFromIntervals,
    romanFor, harmonize, positionsOfMidi, positionsOfPc, lowestPosition, shapeOptions, buildShape, rootToRoot,
    patternIndices,
  };
})(typeof window !== 'undefined' ? (window.GQ = window.GQ || {}) : (globalThis.GQ = globalThis.GQ || {}));
