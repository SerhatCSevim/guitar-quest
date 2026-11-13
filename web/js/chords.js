/* Guitar Quest - chord voicings (open shapes + moveable barre shapes) and chord diagrams. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory;
  const X = -1; // muted string

  // Frets and fingers are listed from the 6th (low E) string to the 1st (high e) string.
  // 0 in fingers = open or muted string.
  const OPEN = [
    ['C', 'maj', [X, 3, 2, 0, 1, 0], [0, 3, 2, 0, 1, 0]],
    ['C', 'dom7', [X, 3, 2, 3, 1, 0], [0, 3, 2, 4, 1, 0]],
    ['C', 'maj7', [X, 3, 2, 0, 0, 0], [0, 3, 2, 0, 0, 0]],
    ['D', 'maj', [X, X, 0, 2, 3, 2], [0, 0, 0, 1, 3, 2]],
    ['D', 'min', [X, X, 0, 2, 3, 1], [0, 0, 0, 2, 3, 1]],
    ['D', 'dom7', [X, X, 0, 2, 1, 2], [0, 0, 0, 2, 1, 3]],
    ['D', 'min7', [X, X, 0, 2, 1, 1], [0, 0, 0, 2, 1, 1]],
    ['D', 'maj7', [X, X, 0, 2, 2, 2], [0, 0, 0, 1, 1, 1]],
    ['D', 'sus2', [X, X, 0, 2, 3, 0], [0, 0, 0, 1, 3, 0]],
    ['D', 'sus4', [X, X, 0, 2, 3, 3], [0, 0, 0, 1, 3, 4]],
    ['D', 'power', [X, X, 0, 2, 3, X], [0, 0, 0, 1, 3, 0]],
    ['E', 'maj', [0, 2, 2, 1, 0, 0], [0, 2, 3, 1, 0, 0]],
    ['E', 'min', [0, 2, 2, 0, 0, 0], [0, 2, 3, 0, 0, 0]],
    ['E', 'dom7', [0, 2, 0, 1, 0, 0], [0, 2, 0, 1, 0, 0]],
    ['E', 'min7', [0, 2, 0, 0, 0, 0], [0, 2, 0, 0, 0, 0]],
    ['E', 'maj7', [0, 2, 1, 1, 0, 0], [0, 3, 1, 2, 0, 0]],
    ['E', 'sus4', [0, 2, 2, 2, 0, 0], [0, 2, 3, 4, 0, 0]],
    ['E', 'power', [0, 2, 2, X, X, X], [0, 1, 2, 0, 0, 0]],
    ['F', 'maj', [X, X, 3, 2, 1, 1], [0, 0, 3, 2, 1, 1]],
    ['F', 'maj7', [X, X, 3, 2, 1, 0], [0, 0, 3, 2, 1, 0]],
    ['G', 'maj', [3, 2, 0, 0, 0, 3], [3, 2, 0, 0, 0, 4]],
    ['G', 'dom7', [3, 2, 0, 0, 0, 1], [3, 2, 0, 0, 0, 1]],
    ['G', 'maj7', [3, 2, 0, 0, 0, 2], [3, 2, 0, 0, 0, 1]],
    ['A', 'maj', [X, 0, 2, 2, 2, 0], [0, 0, 1, 2, 3, 0]],
    ['A', 'min', [X, 0, 2, 2, 1, 0], [0, 0, 2, 3, 1, 0]],
    ['A', 'dom7', [X, 0, 2, 0, 2, 0], [0, 0, 2, 0, 3, 0]],
    ['A', 'min7', [X, 0, 2, 0, 1, 0], [0, 0, 2, 0, 1, 0]],
    ['A', 'maj7', [X, 0, 2, 1, 2, 0], [0, 0, 2, 1, 3, 0]],
    ['A', 'sus2', [X, 0, 2, 2, 0, 0], [0, 0, 1, 2, 0, 0]],
    ['A', 'sus4', [X, 0, 2, 2, 3, 0], [0, 0, 1, 2, 3, 0]],
    ['A', 'power', [X, 0, 2, 2, X, X], [0, 0, 1, 2, 0, 0]],
    ['B', 'dom7', [X, 2, 1, 2, 0, 2], [0, 2, 1, 3, 0, 4]],
  ].map(([root, type, frets, fingers]) => ({ root: T.parseNote(root), type, frets, fingers, kind: 'open' }));

  // Moveable shapes: offsets from the root fret r (null = muted). fingers null = show dots only.
  const E_SHAPES = {
    maj: [[0, 2, 2, 1, 0, 0], [1, 3, 4, 2, 1, 1]],
    min: [[0, 2, 2, 0, 0, 0], [1, 3, 4, 1, 1, 1]],
    dom7: [[0, 2, 0, 1, 0, 0], [1, 3, 1, 2, 1, 1]],
    min7: [[0, 2, 0, 0, 0, 0], [1, 3, 1, 1, 1, 1]],
    sus4: [[0, 2, 2, 2, 0, 0], [1, 2, 3, 4, 1, 1]],
    maj7: [[0, null, 1, 1, 0, null], [1, 0, 3, 4, 2, 0]],
    dim: [[0, 1, 2, 0, null, null], null],
    power: [[0, 2, 2, null, null, null], [1, 3, 4, 0, 0, 0]],
  };
  const A_SHAPES = {
    maj: [[null, 0, 2, 2, 2, 0], [0, 1, 2, 3, 4, 1]],
    min: [[null, 0, 2, 2, 1, 0], [0, 1, 3, 4, 2, 1]],
    dom7: [[null, 0, 2, 0, 2, 0], [0, 1, 3, 1, 4, 1]],
    min7: [[null, 0, 2, 0, 1, 0], [0, 1, 3, 1, 2, 1]],
    sus2: [[null, 0, 2, 2, 0, 0], [0, 1, 3, 4, 1, 1]],
    sus4: [[null, 0, 2, 2, 3, 0], [0, 1, 2, 3, 4, 1]],
    maj7: [[null, 0, 2, 1, 2, 0], [0, 1, 3, 2, 4, 1]],
    dim: [[null, 0, 1, 2, 1, null], [0, 1, 2, 4, 3, 0]],
    m7b5: [[null, 0, 1, 0, 1, null], [0, 1, 3, 2, 4, 0]],
    dim7: [[null, 0, 1, -1, 1, null], [0, 2, 3, 1, 4, 0]],
    aug: [[null, 0, -1, -2, -2, null], [0, 3, 2, 1, 1, 0]],
    power: [[null, 0, 2, 2, null, null], [0, 1, 3, 4, 0, 0]],
  };

  function fromShape(root, type, shape, rootString) {
    const [offs, fing] = shape;
    let r = T.mod(T.notePc(root) - T.TUNING[rootString], 12);
    const minOff = Math.min.apply(null, offs.filter((o) => o !== null));
    if (r === 0 || r + minOff < 1) r += 12; // keep it a real barre shape (open versions live in OPEN)
    const frets = offs.map((o) => (o === null ? X : r + o));
    const fingers = fing ? fing.map((f, i) => (frets[i] <= 0 ? 0 : f)) : null;
    return { root, type, frets, fingers, kind: rootString === 6 ? 'E-shape' : 'A-shape', rootFret: r };
  }

  function voicingsFor(root, type) {
    const pc = T.notePc(root);
    const out = OPEN.filter((v) => T.notePc(v.root) === pc && v.type === type)
      .map((v) => Object.assign({}, v, { root }));
    const moveable = [];
    if (E_SHAPES[type]) moveable.push(fromShape(root, type, E_SHAPES[type], 6));
    if (A_SHAPES[type]) moveable.push(fromShape(root, type, A_SHAPES[type], 5));
    moveable.sort((a, b) => a.rootFret - b.rootFret);
    return out.concat(moveable);
  }
  function bestVoicing(root, type) { return voicingsFor(root, type)[0] || null; }

  function voicingNotes(v) {
    const out = [];
    v.frets.forEach((f, i) => {
      if (f < 0) return;
      const string = 6 - i;
      out.push({ string, fret: f, midi: T.midiAt(string, f) });
    });
    return out; // low to high
  }

  // A voicing is correct when every sounding note is a chord tone, the root is in the bass,
  // and the defining tones (3rd or suspension, 7th) are present. The 5th may be left out.
  function validate(v) {
    const tones = T.chordTones(v.root, v.type);
    const pcs = new Set(tones.map((t) => t.pc));
    const notes = voicingNotes(v);
    if (!notes.length) return 'no notes';
    for (const n of notes) if (!pcs.has(T.mod(n.midi, 12))) return 'non-chord tone on string ' + n.string;
    if (T.mod(notes[0].midi, 12) !== T.notePc(v.root)) return 'root not in bass';
    const have = new Set(notes.map((n) => T.mod(n.midi, 12)));
    for (const t of tones) if (t.degree !== 5 && !have.has(t.pc)) return 'missing ' + t.label;
    if (v.fingers) {
      for (let i = 0; i < 6; i++) {
        if (v.frets[i] > 0 && !v.fingers[i]) return 'missing finger on string ' + (6 - i);
        if (v.frets[i] <= 0 && v.fingers[i]) return 'finger on open/muted string ' + (6 - i);
      }
    }
    return null;
  }

  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }

  // Chord diagram as an SVG string. opts: { title, width, rootColor, highlightRoot }
  function diagramSVG(v, opts) {
    opts = opts || {};
    const s = (opts.width || 120) / 120;
    const W = 132 * s; // extra room on the right for the "3fr" position label
    const left = 22 * s, gap = 15 * s, top = (opts.title ? 40 : 18) * s, fh = 19 * s;
    const fretted = v.frets.filter((f) => f > 0);
    const maxF = fretted.length ? Math.max.apply(null, fretted) : 0;
    const minF = fretted.length ? Math.min.apply(null, fretted) : 0;
    const base = maxF <= 4 ? 1 : minF;
    const rows = Math.max(4, maxF - base + 1);
    const H = top + rows * fh + 14 * s;
    const rootPc = T.notePc(v.root);
    const parts = [];
    parts.push('<svg class="chord-diagram" viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" xmlns="http://www.w3.org/2000/svg">');
    if (opts.title) parts.push('<text x="' + (left + 2.5 * gap) + '" y="' + 22 * s + '" text-anchor="middle" class="cd-title" font-size="' + 19 * s + '">' + esc(opts.title) + '</text>');
    for (let i = 0; i < 6; i++) {
      const x = left + i * gap;
      parts.push('<line x1="' + x + '" y1="' + top + '" x2="' + x + '" y2="' + (top + rows * fh) + '" class="cd-string" stroke-width="' + (1 + (5 - i) * 0.18) * s + '"/>');
    }
    for (let r = 0; r <= rows; r++) {
      const y = top + r * fh;
      const nut = r === 0 && base === 1;
      parts.push('<line x1="' + left + '" y1="' + y + '" x2="' + (left + 5 * gap) + '" y2="' + y + '" class="' + (nut ? 'cd-nut' : 'cd-fret') + '" stroke-width="' + (nut ? 5 : 1.2) * s + '"/>');
    }
    if (base > 1) parts.push('<text x="' + (left + 5 * gap + 11 * s) + '" y="' + (top + fh * 0.65) + '" class="cd-base" font-size="' + 11 * s + '">' + base + 'fr</text>');
    // barre: finger 1 on the same fret across several strings
    if (v.fingers) {
      const ones = [];
      v.frets.forEach((f, i) => { if (f > 0 && v.fingers[i] === 1) ones.push({ i, f }); });
      const minOne = ones.length ? Math.min.apply(null, ones.map((o) => o.f)) : 0;
      const atMin = ones.filter((o) => o.f === minOne);
      if (atMin.length >= 2) {
        const i0 = Math.min.apply(null, atMin.map((o) => o.i)), i1 = Math.max.apply(null, atMin.map((o) => o.i));
        const y = top + (minOne - base + 0.5) * fh;
        parts.push('<rect x="' + (left + i0 * gap - 6 * s) + '" y="' + (y - 6 * s) + '" width="' + ((i1 - i0) * gap + 12 * s) + '" height="' + 12 * s + '" rx="' + 6 * s + '" class="cd-barre"/>');
      }
    }
    v.frets.forEach((f, i) => {
      const x = left + i * gap;
      if (f < 0) {
        const y = top - 9 * s, d = 4 * s;
        parts.push('<path d="M' + (x - d) + ',' + (y - d) + 'L' + (x + d) + ',' + (y + d) + 'M' + (x + d) + ',' + (y - d) + 'L' + (x - d) + ',' + (y + d) + '" class="cd-mute" stroke-width="' + 1.6 * s + '"/>');
        return;
      }
      const midi = T.midiAt(6 - i, f);
      const isRoot = T.mod(midi, 12) === rootPc;
      if (f === 0) {
        parts.push('<circle cx="' + x + '" cy="' + (top - 9 * s) + '" r="' + 4.5 * s + '" class="cd-open' + (isRoot && opts.highlightRoot ? ' root' : '') + '" stroke-width="' + 1.5 * s + '"/>');
        return;
      }
      const y = top + (f - base + 0.5) * fh;
      parts.push('<circle cx="' + x + '" cy="' + y + '" r="' + 7 * s + '" class="cd-dot' + (isRoot && opts.highlightRoot ? ' root' : '') + '"/>');
      if (v.fingers && v.fingers[i]) parts.push('<text x="' + x + '" y="' + (y + 4 * s) + '" text-anchor="middle" class="cd-finger" font-size="' + 10.5 * s + '">' + v.fingers[i] + '</text>');
    });
    parts.push('</svg>');
    return parts.join('');
  }

  GQ.Chords = { OPEN, E_SHAPES, A_SHAPES, X, voicingsFor, bestVoicing, voicingNotes, validate, diagramSVG };
})(typeof window !== 'undefined' ? (window.GQ = window.GQ || {}) : (globalThis.GQ = globalThis.GQ || {}));
