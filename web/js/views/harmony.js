/* Guitar Quest - Chords & Harmony: chord library, chord building, chord families, jam-along strumming, theory games. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory, UI = GQ.UI, C = GQ.Chords;
  const { h, clear, segmented, select, field, icon } = UI;
  GQ.Views = GQ.Views || {};

  const TABS = [
    { value: 'library', label: 'Chord library' }, { value: 'build', label: 'Build a chord' },
    { value: 'families', label: 'Chord families' }, { value: 'jam', label: 'Jam along' }, { value: 'games', label: 'Theory games' },
  ];
  const state = {
    tab: 'library', lib: 'open', barreRoot: 'G', sel: null,
    build: { root: 'C', type: 'maj' },
    fam: { family: 'major', key: 'G', sevenths: false },
    jam: { prog: 'I-IV-V-I', family: 'major', key: 'G', strum: 'folk', bpm: 72, metronome: true, sound: true },
    game: { id: 'steps', level: 'easy' },
  };
  let root, body, jamTransport = null, views = [], gameState = null;

  function nm() { const n = GQ.Store.settings().naming; return n === 'both' ? 'letters' : n; }
  function sym(root, type) { return T.chordSymbol(root, type, nm()); }

  function mount(el, params) {
    if (params) Object.assign(state, params);
    root = h('section', { class: 'harmony' });
    el.appendChild(root);
    root.appendChild(h('div', { class: 'view-head' },
      h('h1', null, 'Chords & Harmony'),
      h('p', { class: 'lead' }, 'Harmony = notes played together. See how chords are built from scales, which chords belong together, and strum along.')));
    root.appendChild(h('div', { class: 'subtabs' }, segmented(TABS, state.tab, (v) => { state.tab = v; renderTab(); }, 'big')));
    body = h('div', { class: 'harmony-body' });
    root.appendChild(body);
    renderTab();
  }
  function unmount() {
    stopJam();
    views.forEach((v) => v.destroy && v.destroy());
    views = [];
    GQ.PracticeClock.stop('jam');
  }

  function renderTab() {
    unmount();
    clear(body);
    ({ library: renderLibrary, build: renderBuild, families: renderFamilies, jam: renderJam, games: renderGames })[state.tab]();
  }

  /* ---------------- shared: chord detail ---------------- */
  function strumVoicing(v, dir) {
    const notes = C.voicingNotes(v).map((n) => n.midi);
    GQ.Audio.strum(notes, GQ.Audio.now() + 0.02, { dir: dir || 'down', spread: dir === 'up' ? 0.012 : 0.022, duration: 2.2, velocity: 0.7 });
  }
  function arpeggio(v) {
    const t = GQ.Audio.now() + 0.05;
    C.voicingNotes(v).forEach((n, i) => GQ.Audio.pluck(n.midi, t + i * 0.28, { duration: 1.6 }));
  }

  function spelledFor(v, pc) {
    const tone = T.chordTones(v.root, v.type).find((t) => t.pc === pc);
    return tone ? { l: tone.l, a: tone.a } : T.spellPc(pc);
  }

  function chordDetail(v, extraTitle) {
    const card = h('div', { class: 'card chord-detail' });
    const tones = T.chordTones(v.root, v.type);
    const name = sym(v.root, v.type);
    const diag = h('div', { class: 'diag-big', html: C.diagramSVG(v, { title: name, width: 170, highlightRoot: true }) });
    const info = h('div', { class: 'chord-info' },
      h('h3', null, name, h('span', { class: 'muted' }, ' · ' + T.CHORD_TYPES[v.type].name.toLowerCase() + (extraTitle ? ' · ' + extraTitle : ''))),
      h('div', { class: 'tone-row' }, tones.map((t) => h('div', { class: 'tone' }, UI.noteBadge({ l: t.l, a: t.a }), h('span', { class: 'deg' }, t.degree === 1 ? 'root' : t.label)))),
      h('p', { class: 'small' }, 'Formula: ' + T.chordFormula(v.type).join(' - ') + ' (steps of the ' + T.noteLabel(v.root, nm()) + ' major scale)'),
      h('div', { class: 'btn-row' },
        h('button', { type: 'button', class: 'btn primary', onclick: () => strumVoicing(v, 'down') }, icon('strum'), ' Strum'),
        h('button', { type: 'button', class: 'btn', onclick: () => strumVoicing(v, 'up') }, 'Up-strum'),
        h('button', { type: 'button', class: 'btn', onclick: () => arpeggio(v) }, 'One string at a time')),
      h('p', { class: 'small muted' }, v.kind === 'open' ? 'Open chord: uses open strings.' : (v.kind + ': the root is on the ' + (v.kind === 'E-shape' ? '6th' : '5th') + ' string at fret ' + v.rootFret + '. Slide the whole shape to play other chords of this type.')),
      v.fingers ? h('p', { class: 'small muted' }, 'Numbers = fingers (1 index, 2 middle, 3 ring, 4 little). A bar across means one finger presses several strings. The red dot is the root.') : h('p', { class: 'small muted' }, 'The red dot is the root.'));
    const top = h('div', { class: 'chord-top' }, diag, info);
    card.appendChild(top);
    // staff + tab of exactly what you play
    const host = h('div', { class: 'mini-score' });
    card.appendChild(host);
    const notes = C.voicingNotes(v).map((n) => ({ string: n.string, fret: n.fret, midi: n.midi, spelled: spelledFor(v, T.mod(n.midi, 12)) }));
    const sv = new GQ.Notation.ScoreView(host, { showStaff: true, showTab: true, showNames: true, colors: GQ.Store.settings().colors, naming: nm(), minWidth: 260, autoScroll: false });
    views.push(sv);
    requestAnimationFrame(() => sv.setScore(GQ.Exercises.finalize([{ dur: 48, tuplet: 0, notes }], { keySig: T.keySignature({ l: 0, a: 0 }, 'major'), tempo: 60 })));
    return card;
  }

  function diagramButton(v, title, onPick, extraCls) {
    return h('button', { type: 'button', class: 'diag-btn ' + (extraCls || ''), title: 'Hear and see ' + title, onclick: () => { strumVoicing(v); onPick(v); },
      html: C.diagramSVG(v, { title, width: 112, highlightRoot: true }) });
  }

  /* ---------------- chord library ---------------- */
  function renderLibrary() {
    body.appendChild(h('div', { class: 'toolbar card' },
      UI.field('Show', segmented([{ value: 'open', label: 'Open chords' }, { value: 'barre', label: 'Barre chords' }, { value: 'power', label: 'Power chords' }], state.lib, (v) => { state.lib = v; state.sel = null; renderTab(); })),
      state.lib === 'barre' ? UI.field('Root note', keyChips(T.MAJOR_KEYS, state.barreRoot, (k) => { state.barreRoot = k; state.sel = null; renderTab(); })) : null));
    const layout = h('div', { class: 'lib-layout' });
    const list = h('div', { class: 'lib-list' });
    const detail = h('div', { class: 'lib-detail' });
    layout.append(list, detail);
    body.appendChild(layout);
    const pickIt = (v) => { state.sel = v; clear(detail); detail.appendChild(chordDetail(v)); };
    const groups = [];
    if (state.lib === 'open') {
      const order = [['maj', 'Major chords - happy, bright'], ['min', 'Minor chords - sad, dark'], ['dom7', 'Seventh chords - want to move on'], ['min7', 'Minor seventh'], ['maj7', 'Major seventh - dreamy'], ['sus2', 'Suspended 2nd'], ['sus4', 'Suspended 4th']];
      order.forEach(([type, title]) => {
        const vs = C.OPEN.filter((v) => v.type === type);
        if (vs.length) groups.push([title, vs]);
      });
      // the most common beginner minor chords that have no open shape in the table get their barre version
      groups[1][1] = groups[1][1].concat([C.bestVoicing(T.parseNote('B'), 'min')]);
    } else if (state.lib === 'barre') {
      const r = T.parseNote(state.barreRoot);
      ['maj', 'min', 'dom7', 'min7', 'sus4', 'maj7'].forEach((type) => {
        const vs = [];
        if (C.E_SHAPES[type]) vs.push(C.voicingsFor(r, type).find((v) => v.kind === 'E-shape'));
        if (C.A_SHAPES[type]) vs.push(C.voicingsFor(r, type).find((v) => v.kind === 'A-shape'));
        groups.push([T.CHORD_TYPES[type].name + ' - 6th-string root and 5th-string root', vs.filter(Boolean)]);
      });
    } else {
      groups.push(['Open power chords', C.OPEN.filter((v) => v.type === 'power')]);
      groups.push(['Moveable power chords (any root)', ['F', 'G', 'A', 'B', 'C', 'D'].map((k) => C.voicingsFor(T.parseNote(k), 'power').find((v) => v.kind !== 'open')).filter(Boolean)]);
    }
    groups.forEach(([title, vs]) => {
      list.appendChild(h('h3', { class: 'group-title' }, title));
      list.appendChild(h('div', { class: 'diag-grid' }, vs.map((v) => diagramButton(v, sym(v.root, v.type), pickIt))));
    });
    if (state.lib === 'barre') list.insertBefore(h('p', { class: 'tip' }, 'Barre chords are moveable: the same finger shape works for every root. Find the root note on the 6th or 5th string, put the shape there - done!'), list.firstChild);
    if (state.lib === 'power') list.insertBefore(h('p', { class: 'tip' }, 'A power chord is only the root and the 5th (1 - 5). It is neither major nor minor, which is why rock guitarists love it.'), list.firstChild);
    const first = state.sel || groups[0][1][0];
    if (first) pickIt(first);
  }

  function keyChips(keys, value, onPick, suffix) {
    const row = h('div', { class: 'key-row' });
    keys.forEach((k) => row.appendChild(h('button', { type: 'button', class: 'key-btn' + (k === value ? ' on' : ''), onclick: () => onPick(k) }, T.noteLabel(T.parseNote(k), nm()) + (suffix || ''))));
    return row;
  }

  /* ---------------- build a chord ---------------- */
  const BUILD_TYPES = ['maj', 'min', 'dim', 'aug', 'sus2', 'sus4', 'dom7', 'maj7', 'min7'];
  function renderBuild() {
    const b = state.build;
    body.appendChild(h('div', { class: 'toolbar card' },
      UI.field('Root', keyChips(T.MAJOR_KEYS, b.root, (k) => { b.root = k; renderTab(); })),
      UI.field('Chord type', segmented(BUILD_TYPES.map((t) => ({ value: t, label: T.CHORD_TYPES[t].name.replace('Suspended ', 'sus ').replace('Dominant ', '') })), b.type, (v) => { b.type = v; renderTab(); }))));
    const r = T.parseNote(b.root);
    const scale = T.scaleNotes(r, 'major');
    const tones = T.chordTones(r, b.type);
    const card = h('div', { class: 'card build-card' });
    card.appendChild(h('h3', null, 'Step 1: write out the ' + T.noteLabel(r, nm()) + ' major scale'));
    const row = h('div', { class: 'build-row' });
    scale.forEach((n, i) => {
      const deg = i + 1;
      const tone = tones.find((t) => t.degree === deg || (deg === 2 && t.degree === 9));
      const cell = h('div', { class: 'build-cell' + (tone ? ' on' : '') },
        h('span', { class: 'build-num' }, String(deg)),
        UI.noteBadge({ l: n.l, a: n.a }));
      if (tone && (tone.l !== n.l || tone.a !== n.a)) {
        cell.classList.add('altered');
        cell.appendChild(h('span', { class: 'build-arrow' }, tone.a < n.a ? 'lower 1 fret' : 'raise 1 fret'));
        cell.appendChild(UI.noteBadge({ l: tone.l, a: tone.a }));
        cell.appendChild(h('span', { class: 'deg' }, tone.label));
      }
      row.appendChild(cell);
    });
    card.appendChild(row);
    card.appendChild(h('h3', null, 'Step 2: take the steps of the formula'));
    card.appendChild(h('p', null, h('strong', null, T.CHORD_TYPES[b.type].name + ' = ' + T.chordFormula(b.type).join(' - ')), '  →  ', tones.map((t) => UI.noteBadge({ l: t.l, a: t.a }))));
    const why = {
      maj: 'Major chords use steps 1, 3 and 5 of the major scale.',
      min: 'Minor chords lower the 3rd by one fret: 1, ♭3, 5. That one note makes the chord sound sad.',
      dim: 'Diminished lowers both the 3rd and the 5th: 1, ♭3, ♭5. Tense and spooky.',
      aug: 'Augmented raises the 5th: 1, 3, ♯5. It sounds like a question.',
      sus2: 'Suspended chords have no 3rd. sus2 uses the 2nd instead: open and floating.',
      sus4: 'sus4 swaps the 3rd for the 4th. It likes to "resolve" back to the major chord.',
      dom7: 'A 7 chord adds the ♭7 to a major chord. It wants to move to the next chord.',
      maj7: 'maj7 adds the 7th (one fret below the root). Soft and dreamy.',
      min7: 'm7 is a minor chord plus the ♭7. Smooth and mellow.',
    }[b.type];
    card.appendChild(h('p', { class: 'tip' }, why));
    body.appendChild(card);
    const grid = h('div', { class: 'grid2' });
    const v = C.bestVoicing(r, b.type);
    if (v) grid.appendChild(chordDetail(v));
    const fbCard = h('div', { class: 'card' }, h('h3', null, 'Step 3: chord tones all over the neck'), h('p', { class: 'small muted' }, 'Any of these notes belongs to ' + sym(r, b.type) + '. R = root.'));
    const fbHost = h('div');
    fbCard.appendChild(fbHost);
    grid.appendChild(fbCard);
    body.appendChild(grid);
    const fb = new GQ.Fretboard(fbHost, { maxFret: 12, compact: true, onSelect: (s, f) => GQ.Audio.pluck(T.midiAt(s, f), 0, { duration: 1 }) });
    const marks = [];
    for (let s = 1; s <= 6; s++) for (let f = 0; f <= 12; f++) {
      const pc = T.mod(T.midiAt(s, f), 12);
      const t = tones.find((x) => x.pc === pc);
      if (t) {
        const m = GQ.noteMark(s, f, { spelled: { l: t.l, a: t.a }, kind: t.degree === 1 ? 'root' : 'note' });
        m.label = t.degree === 1 ? 'R' : t.label;
        marks.push(m);
      }
    }
    fb.setMarks(marks);
  }

  /* ---------------- chord families ---------------- */
  function renderFamilies() {
    const f = state.fam;
    const keys = f.family === 'minor' ? ['A', 'E', 'B', 'D', 'G', 'C', 'F#'] : ['C', 'G', 'D', 'A', 'E', 'F', 'Bb'];
    if (keys.indexOf(f.key) < 0) f.key = keys[0];
    body.appendChild(h('div', { class: 'toolbar card' },
      UI.field('Key type', segmented([{ value: 'major', label: 'Major keys' }, { value: 'minor', label: 'Minor keys' }], f.family, (v) => { f.family = v; renderTab(); })),
      UI.field('Key', keyChips(keys, f.key, (k) => { f.key = k; renderTab(); }, f.family === 'minor' ? 'm' : '')),
      UI.field('Chords', segmented([{ value: 'triads', label: '3-note chords' }, { value: 'sevenths', label: '7th chords' }], f.sevenths ? 'sevenths' : 'triads', (v) => { f.sevenths = v === 'sevenths'; renderTab(); }))));
    const tonic = T.parseNote(f.key);
    const chords = T.harmonize(tonic, f.family, f.sevenths);
    const intro = f.family === 'major'
      ? 'Build a chord on every note of the ' + T.noteLabel(tonic, nm()) + ' major scale (always skipping one note: 1-3-5, 2-4-6, 3-5-7 …). The pattern is the same in every major key: I, IV and V are major, ii, iii and vi are minor, vii° is diminished.'
      : 'In a minor key the pattern moves: i, iv and v are minor, III, VI and VII are major, ii° is diminished. Many songs borrow a major V chord to make the ending stronger.';
    body.appendChild(h('p', { class: 'tip wide' }, intro));
    const row = h('div', { class: 'family-row' });
    const detail = h('div');
    chords.forEach((ch) => {
      const v = C.bestVoicing(ch.root, ch.type);
      const quality = /^(maj|dom7|maj7)$/.test(ch.type) ? 'major' : /^(min|min7)$/.test(ch.type) ? 'minor' : 'dim';
      const card = h('button', { type: 'button', class: 'family-card ' + quality, onclick: () => { strumVoicing(v); clear(detail); detail.appendChild(chordDetail(v, ch.roman + ' in ' + T.noteLabel(tonic, nm()) + (f.family === 'minor' ? ' minor' : ' major'))); } },
        h('span', { class: 'roman' }, ch.roman),
        h('span', { class: 'fam-name' }, sym(ch.root, ch.type)),
        h('span', { class: 'fam-q' }, quality === 'dim' ? 'diminished' : quality),
        h('span', { class: 'fam-diag', html: C.diagramSVG(v, { width: 92, highlightRoot: true }) }));
      row.appendChild(card);
    });
    body.appendChild(row);
    const progs = PROGS.filter((p) => p.family === f.family);
    const pl = h('div', { class: 'card' }, h('h3', null, 'Famous chord progressions in this key'));
    progs.forEach((p) => {
      const names = progChords(p, f.key).map((c) => sym(c.root, c.type));
      const uniq = [];
      names.forEach((n, i) => { if (i === 0 || n !== names[i - 1]) uniq.push(n); });
      pl.appendChild(h('div', { class: 'prog-line' },
        h('span', { class: 'prog-roman' }, p.label), h('span', { class: 'prog-names' }, uniq.join(' → ')),
        h('button', { type: 'button', class: 'btn small', onclick: () => { Object.assign(state.jam, { prog: p.id, family: p.family, key: f.key }); state.tab = 'jam'; mountTabsAgain(); } }, 'Jam →')));
    });
    body.appendChild(pl);
    body.appendChild(detail);
    const first = chords[0];
    detail.appendChild(chordDetail(C.bestVoicing(first.root, first.type), first.roman));
  }
  function mountTabsAgain() {
    const el = root.parentNode;
    unmount();
    clear(el);
    mount(el);
  }

  /* ---------------- jam along ---------------- */
  const PROGS = [
    { id: 'I-IV-V-I', name: 'Three-chord song', label: 'I - IV - V - I', family: 'major', degrees: [1, 4, 5, 1] },
    { id: 'I-V-vi-IV', name: 'Pop song', label: 'I - V - vi - IV', family: 'major', degrees: [1, 5, 6, 4] },
    { id: 'I-vi-IV-V', name: '1950s song', label: 'I - vi - IV - V', family: 'major', degrees: [1, 6, 4, 5] },
    { id: 'ii-V-I', name: 'Jazz ii - V - I', label: 'ii7 - V7 - Imaj7', family: 'major', degrees: [2, 5, 1, 1], sevenths: true },
    { id: 'blues', name: '12-bar blues', label: 'I7 - IV7 - V7 (12 bars)', family: 'major', degrees: [1, 1, 1, 1, 4, 4, 1, 1, 5, 4, 1, 5], dom7: true },
    { id: 'i-iv-V-i', name: 'Minor song', label: 'i - iv - V - i', family: 'minor', degrees: [1, 4, 5, 1], majorV: true },
    { id: 'i-VI-III-VII', name: 'Epic minor', label: 'i - VI - III - VII', family: 'minor', degrees: [1, 6, 3, 7] },
  ];
  const STRUMS = [
    { id: 'whole', name: 'One strum per bar', slots: 'D-------' },
    { id: 'quarters', name: 'Four down-strums', slots: 'D-D-D-D-' },
    { id: 'folk', name: 'Down, down-up, up-down-up', slots: 'D-DU-UDU' },
    { id: 'eighths', name: 'Down-up all the way', slots: 'DUDUDUDU' },
    { id: 'rock', name: 'Rock: down, down, down-up-down-up', slots: 'D-D-DUDU' },
  ];
  function progChords(p, key) {
    const tonic = T.parseNote(key);
    const fam = T.harmonize(tonic, p.family, !!p.sevenths);
    return p.degrees.map((d) => {
      const ch = Object.assign({}, fam[d - 1]);
      if (p.dom7) ch.type = 'dom7';
      if (p.majorV && d === 5) { ch.type = 'maj'; ch.roman = 'V'; }
      if (p.dom7) ch.roman = T.romanFor(d - 1, 'dom7');
      return ch;
    });
  }

  function stopJam() { if (jamTransport) { jamTransport.stop(); jamTransport = null; } }

  function renderJam() {
    const j = state.jam;
    const prog = PROGS.find((p) => p.id === j.prog) || PROGS[0];
    j.family = prog.family;
    const keys = j.family === 'minor' ? ['A', 'E', 'D', 'B'] : ['C', 'G', 'D', 'A', 'E', 'F'];
    if (keys.indexOf(j.key) < 0) j.key = keys[0];
    body.appendChild(h('div', { class: 'toolbar card' },
      UI.field('Progression', select(PROGS.map((p) => ({ value: p.id, label: p.name + '  (' + p.label + ')' })), j.prog, (v) => { j.prog = v; renderTab(); })),
      UI.field('Key', keyChips(keys, j.key, (k) => { j.key = k; renderTab(); }, j.family === 'minor' ? 'm' : '')),
      UI.field('Strum pattern', select(STRUMS.map((s) => ({ value: s.id, label: s.name })), j.strum, (v) => { j.strum = v; renderTab(); }))));
    const chords = progChords(prog, j.key);
    const voicings = chords.map((c) => C.bestVoicing(c.root, c.type));
    const strum = STRUMS.find((s) => s.id === j.strum);
    // play controls
    const playBtn = h('button', { type: 'button', class: 'tbtn play', title: 'Play / stop' }, icon('play'));
    const tempoVal = h('span', { class: 'tempo-val' }, j.bpm + ' BPM');
    const tempo = h('input', { type: 'range', min: '40', max: '160', value: String(j.bpm), class: 'tempo-range', 'aria-label': 'Tempo' });
    const mkToggle = (key, label, ic) => {
      const b = h('button', { type: 'button', class: 'tbtn toggle' + (j[key] ? ' on' : '') }, ic ? icon(ic) : null, h('span', null, label));
      b.addEventListener('click', () => { j[key] = !j[key]; b.classList.toggle('on', j[key]); if (jamTransport) { jamTransport.metronome = j.metronome; jamTransport.sound = j.sound; } });
      return b;
    };
    body.appendChild(h('div', { class: 'transport card' },
      h('div', { class: 'tgroup' }, playBtn),
      h('div', { class: 'tgroup tempo' }, h('span', { class: 'small muted' }, 'Tempo'), tempo, tempoVal),
      h('div', { class: 'tgroup' }, mkToggle('metronome', 'Click', 'metro'), mkToggle('sound', 'Guitar', 'speaker')),
      h('span', { class: 'small muted' }, 'Turn the guitar off and strum the chords yourself!')));
    // stage: current + next chord, strum arrows
    const cur = h('div', { class: 'jam-current' });
    const next = h('div', { class: 'jam-next' });
    const arrows = h('div', { class: 'strum-row' });
    const counts = ['1', '&', '2', '&', '3', '&', '4', '&'];
    strum.slots.split('').forEach((c, k) => arrows.appendChild(h('div', { class: 'strum-slot' + (c === '-' ? ' rest' : ''), dataset: { k: String(k) } },
      h('span', { class: 'arrow' }, c === 'D' ? '↓' : c === 'U' ? '↑' : '·'), h('span', { class: 'count' }, counts[k]))));
    body.appendChild(h('div', { class: 'jam-stage card' }, h('div', { class: 'jam-chords' }, cur, next), h('div', { class: 'jam-strum' }, h('h3', null, 'Strum: ' + strum.name), arrows,
      h('p', { class: 'small muted' }, '↓ = strum down (towards the floor) · ↑ = strum up · keep your hand moving even on the dots!'))));
    // timeline
    const tl = h('div', { class: 'jam-timeline' });
    chords.forEach((c, b) => tl.appendChild(h('div', { class: 'jam-bar', dataset: { b: String(b) } }, h('span', { class: 'jb-name' }, sym(c.root, c.type)), h('span', { class: 'jb-roman' }, c.roman))));
    body.appendChild(h('div', { class: 'card' }, h('h3', null, prog.name + ' in ' + T.noteLabel(T.parseNote(j.key), nm()) + (j.family === 'minor' ? ' minor' : ' major')), tl));

    const showChord = (b) => {
      const v = voicings[b], vn = voicings[(b + 1) % voicings.length];
      clear(cur).appendChild(h('div', { class: 'jam-label' }, 'Now'));
      cur.appendChild(h('div', { html: C.diagramSVG(v, { title: sym(chords[b].root, chords[b].type), width: 190, highlightRoot: true }) }));
      clear(next).appendChild(h('div', { class: 'jam-label' }, 'Next'));
      next.appendChild(h('div', { html: C.diagramSVG(vn, { title: sym(chords[(b + 1) % chords.length].root, chords[(b + 1) % chords.length].type), width: 120, highlightRoot: true }) }));
      tl.querySelectorAll('.jam-bar').forEach((el) => el.classList.toggle('on', Number(el.dataset.b) === b));
    };
    showChord(0);

    // build strum events
    const items = [];
    const slotList = strum.slots.split('').map((c, k) => ({ c, k })).filter((s) => s.c !== '-');
    chords.forEach((c, b) => {
      const midis = C.voicingNotes(voicings[b]).map((n) => n.midi);
      slotList.forEach((s, si) => {
        const nextK = si + 1 < slotList.length ? slotList[si + 1].k : 8;
        items.push({ i: items.length, beat: b * 4 + s.k * 0.5, beats: (nextK - s.k) * 0.5, rest: false, midis, strum: true, dir: s.c === 'D' ? 'down' : 'up', velocity: s.k === 0 ? 0.75 : 0.55, bar: b, slot: s.k });
      });
    });
    const slotEls = Array.from(arrows.children);
    const setPos = (i) => {
      slotEls.forEach((el) => el.classList.remove('on'));
      if (i < 0) return;
      const it = items[i];
      showChord(it.bar);
      if (slotEls[it.slot]) slotEls[it.slot].classList.add('on');
    };
    const start = () => {
      stopJam();
      jamTransport = new GQ.Transport({
        onPosition: (i) => setPos(i),
        onState: (playing) => {
          clear(playBtn).appendChild(icon(playing ? 'stop' : 'play'));
          playBtn.classList.toggle('on', playing);
          if (playing) GQ.PracticeClock.start('jam'); else GQ.PracticeClock.stop('jam');
        },
      });
      jamTransport.load(items, chords.length * 4, 4);
      Object.assign(jamTransport, { bpm: j.bpm, loop: true, metronome: j.metronome, countIn: true, sound: j.sound });
      jamTransport.play(0);
    };
    playBtn.addEventListener('click', () => { if (jamTransport && jamTransport.playing) stopJam(); else start(); });
    tempo.addEventListener('input', () => { j.bpm = Number(tempo.value); tempoVal.textContent = j.bpm + ' BPM'; if (jamTransport) jamTransport.setTempo(j.bpm); });
  }

  /* ---------------- theory games ---------------- */
  const GAMES = [
    { id: 'steps', name: 'Half & whole steps', desc: '1 fret = half step, 2 frets = whole step.' },
    { id: 'scale', name: 'Scale steps', desc: 'Find a step of a major scale.' },
    { id: 'triad', name: 'Build the chord', desc: 'Spell a chord with its 3 notes.' },
    { id: 'family', name: 'Chord families', desc: 'Which chord is IV in G?' },
    { id: 'keysig', name: 'Key signatures', desc: 'How many sharps or flats?' },
  ];
  const LEVEL_KEYS = { easy: ['C', 'G', 'F', 'D'], medium: ['C', 'G', 'D', 'A', 'E', 'F', 'Bb', 'Eb'], hard: T.MAJOR_KEYS };

  function renderGames() {
    const g = state.game;
    const cards = h('div', { class: 'game-cards small' });
    GAMES.forEach((x) => cards.appendChild(h('button', { type: 'button', class: 'game-card' + (x.id === g.id ? ' on' : ''), onclick: () => { g.id = x.id; renderTab(); } },
      h('strong', null, x.name), h('span', null, x.desc))));
    body.appendChild(cards);
    body.appendChild(h('div', { class: 'toolbar card' }, UI.field('Level', segmented([{ value: 'easy', label: 'Easy' }, { value: 'medium', label: 'Medium' }, { value: 'hard', label: 'Hard' }], g.level, (v) => { g.level = v; renderTab(); })),
      h('div', { class: 'hud-stat' }, icon('star'), h('span', { id: 'tgScore' }, '0')),
      h('div', { class: 'hud-stat flame' }, icon('flame'), h('span', { id: 'tgStreak' }, '0')),
      h('span', { class: 'small muted' }, 'Best streak: ' + (GQ.Store.get().theory.best[g.id + ':' + g.level] || 0))));
    gameState = { score: 0, streak: 0, q: null, picked: [], acc: 0 };
    const card = h('div', { class: 'card tg-card' });
    card.appendChild(h('div', { class: 'q-prompt', id: 'tgQ' }));
    card.appendChild(h('div', { id: 'tgExtra' }));
    card.appendChild(h('div', { class: 'tg-pad', id: 'tgPad' }));
    card.appendChild(h('div', { class: 'feedback', id: 'tgFb', 'aria-live': 'polite' }));
    card.appendChild(h('div', { class: 'q-actions' }, h('button', { type: 'button', class: 'btn primary', id: 'tgNext', hidden: true, onclick: nextTheory }, 'Next')));
    body.appendChild(card);
    nextTheory();
  }

  function rnd(arr) { return UI.pick(arr); }

  function nextTheory() {
    const g = state.game;
    const keys = LEVEL_KEYS[g.level];
    gameState.picked = []; gameState.acc = 0; gameState.locked = false;
    document.getElementById('tgNext').hidden = true;
    setTg('', '');
    const extra = clear(document.getElementById('tgExtra'));
    let q;
    if (g.id === 'steps') {
      const pool = g.level === 'easy' ? ['C', 'D', 'E', 'F', 'G', 'A', 'B'] : T.MAJOR_KEYS.concat(['C#', 'D#', 'G#', 'A#']);
      const from = T.parseNote(rnd(pool));
      const size = rnd([1, 2]);
      const up = g.level === 'easy' ? true : Math.random() < 0.6;
      const pc = T.mod(T.notePc(from) + (up ? size : -size), 12);
      q = { kind: 'pc', answer: pc, text: 'What is a ' + (size === 1 ? 'half' : 'whole') + ' step ' + (up ? 'above' : 'below') + ' ' + T.noteLabel(from, nm()) + '?',
        explain: (size === 1 ? 'A half step is 1 fret' : 'A whole step is 2 frets') + (up ? ' up' : ' down') + ': ' + T.noteLabel(from, nm()) + ' → ' + T.pcLabel(pc, nm(), 'both') + '.' };
      extra.appendChild(stepStrip(from));
    } else if (g.id === 'scale') {
      const key = T.parseNote(rnd(keys));
      const deg = rnd(g.level === 'easy' ? [2, 3, 4, 5] : [2, 3, 4, 5, 6, 7]);
      const sc = T.scaleNotes(key, 'major');
      const ans = sc[deg - 1];
      q = { kind: 'spelled', answer: { l: ans.l, a: ans.a }, text: 'In ' + T.noteLabel(key, nm()) + ' major, what is note number ' + deg + '?',
        explain: T.noteLabel(key, nm()) + ' major: ' + sc.map((n, i) => (i + 1) + '=' + T.noteLabel(n, nm())).join('  ') };
    } else if (g.id === 'triad') {
      const key = T.parseNote(rnd(keys));
      const types = g.level === 'easy' ? ['maj', 'min'] : g.level === 'medium' ? ['maj', 'min', 'dim'] : ['maj', 'min', 'dim', 'aug'];
      const type = rnd(types);
      const tones = T.chordTones(key, type);
      q = { kind: 'multi', answer: tones.map((t) => ({ l: t.l, a: t.a })), text: 'Spell ' + sym(key, type) + ' (' + T.CHORD_TYPES[type].name.toLowerCase() + '): pick its 3 notes.',
        explain: sym(key, type) + ' = ' + T.chordFormula(type).join('-') + ' = ' + tones.map((t) => T.noteLabel(t, nm())).join(' ') };
    } else if (g.id === 'family') {
      const key = T.parseNote(rnd(keys));
      const fam = T.harmonize(key, 'major', false);
      const d = rnd(g.level === 'easy' ? [1, 4, 5] : g.level === 'medium' ? [1, 2, 4, 5, 6] : [1, 2, 3, 4, 5, 6, 7]);
      const right = fam[d - 1];
      if (Math.random() < 0.5 || g.level === 'easy') {
        const opts = UI.shuffle(fam.filter((c) => c.degree !== d)).slice(0, 3).concat([right]);
        q = { kind: 'choice', answer: sym(right.root, right.type), options: UI.shuffle(opts.map((c) => sym(c.root, c.type))),
          text: 'In the key of ' + T.noteLabel(key, nm()) + ' major, which chord is ' + right.roman + '?',
          explain: T.noteLabel(key, nm()) + ' major family: ' + fam.map((c) => c.roman + '=' + sym(c.root, c.type)).join('  ') };
      } else {
        const opts = UI.shuffle(fam.filter((c) => c.degree !== d)).slice(0, 3).concat([right]);
        q = { kind: 'choice', answer: right.roman, options: UI.shuffle(opts.map((c) => c.roman)),
          text: 'In the key of ' + T.noteLabel(key, nm()) + ' major, ' + sym(right.root, right.type) + ' is which chord?',
          explain: T.noteLabel(key, nm()) + ' major family: ' + fam.map((c) => c.roman + '=' + sym(c.root, c.type)).join('  ') };
      }
    } else {
      const key = T.parseNote(rnd(keys));
      const ks = T.keySignature(key, 'major');
      const label = (f) => (f === 0 ? 'none' : Math.abs(f) + (f > 0 ? ' ♯' : ' ♭'));
      if (Math.random() < 0.6 || g.level === 'easy') {
        const all = [0, 1, 2, 3, 4, 5, 6, -1, -2, -3, -4, -5, -6];
        const opts = UI.shuffle(all.filter((x) => x !== ks.fifths)).slice(0, 3).concat([ks.fifths]);
        q = { kind: 'choice', answer: label(ks.fifths), options: UI.shuffle(opts.map(label)),
          text: 'How many sharps or flats does ' + T.noteLabel(key, nm()) + ' major have?',
          explain: T.noteLabel(key, nm()) + ' major: ' + (ks.fifths ? ks.list.map((n) => T.noteLabel(n, nm())).join(' ') : 'no sharps or flats') };
      } else {
        const others = UI.shuffle(T.MAJOR_KEYS.filter((k) => T.keySignature(T.parseNote(k), 'major').fifths !== ks.fifths)).slice(0, 3);
        q = { kind: 'choice', answer: T.noteLabel(key, nm()) + ' major', options: UI.shuffle(others.concat([T.noteAscii(key)]).map((k) => T.noteLabel(T.parseNote(k), nm()) + ' major')),
          text: 'Which major key has ' + (ks.fifths === 0 ? 'no sharps or flats' : label(ks.fifths) + ' (' + ks.list.map((n) => T.noteLabel(n, nm())).join(' ') + ')') + '?',
          explain: 'Sharps come in the order F C G D A E B, flats in the order B E A D G C F.' };
      }
    }
    gameState.q = q;
    document.getElementById('tgQ').textContent = q.text;
    renderTheoryPad();
  }

  // Seven neighbouring frets around the start note, so the step can be counted.
  function stepStrip(from) {
    const wrap = h('div', { class: 'step-strip' });
    const base = T.notePc(from);
    for (let k = -3; k <= 3; k++) {
      const pc = T.mod(base + k, 12);
      wrap.appendChild(h('span', { class: 'ss-cell' + (T.isNaturalPc(pc) ? '' : ' black') + (k === 0 ? ' from' : '') },
        h('span', { class: 'ss-name' }, k === 0 ? T.noteLabel(from, nm()) : '?'),
        h('span', { class: 'ss-off' }, k === 0 ? 'start' : (k > 0 ? '+' : '') + k)));
    }
    return h('div', null, wrap, h('p', { class: 'small muted' }, 'Each box is one fret (one half step). Dark boxes are black-key notes.'));
  }

  function renderTheoryPad() {
    const pad = clear(document.getElementById('tgPad'));
    const q = gameState.q;
    if (q.kind === 'choice') {
      q.options.forEach((o) => pad.appendChild(h('button', { type: 'button', class: 'btn choice', onclick: (e) => checkTheory(o, e.currentTarget) }, o)));
      return;
    }
    if (q.kind === 'pc') {
      for (let pc = 0; pc < 12; pc++) {
        const col = UI.pcColor(pc);
        pad.appendChild(h('button', { type: 'button', class: 'pad-btn' + (T.isNaturalPc(pc) ? '' : ' sharp'), dataset: { pc: String(pc) }, style: { '--c': col, '--on': UI.inkOn(col) }, onclick: (e) => checkTheory(pc, e.currentTarget) }, T.pcLabel(pc, nm(), 'both')));
      }
      return;
    }
    // spelled input: accidental + letter
    const accRow = segmented([{ value: -1, label: '♭ flat' }, { value: 0, label: '♮ natural' }, { value: 1, label: '♯ sharp' }], gameState.acc, (v) => { gameState.acc = Number(v); });
    pad.appendChild(h('div', { class: 'acc-row' }, accRow));
    const letters = h('div', { class: 'letter-pad' });
    for (let l = 0; l < 7; l++) {
      const col = UI.letterColor(l);
      letters.appendChild(h('button', { type: 'button', class: 'pad-btn', style: { '--c': col, '--on': UI.inkOn(col) }, onclick: () => {
        const n = { l, a: gameState.acc };
        gameState.acc = 0; accRow.setValue(0);
        if (q.kind === 'spelled') checkTheory(n);
        else addPicked(n);
      } }, T.LETTERS[l]));
    }
    pad.appendChild(letters);
    if (q.kind === 'multi') {
      pad.appendChild(h('div', { class: 'picked', id: 'tgPicked' }));
      renderPicked();
    }
  }
  function addPicked(n) {
    if (gameState.locked) return;
    if (gameState.picked.some((p) => T.sameNote(p, n))) return;
    gameState.picked.push(n);
    renderPicked();
    if (gameState.picked.length === gameState.q.answer.length) checkTheory(gameState.picked);
  }
  function renderPicked() {
    const el = clear(document.getElementById('tgPicked'));
    for (let i = 0; i < gameState.q.answer.length; i++) {
      const n = gameState.picked[i];
      el.appendChild(n ? h('button', { type: 'button', class: 'picked-note', title: 'Remove', onclick: () => { if (!gameState.locked) { gameState.picked.splice(i, 1); renderPicked(); } } }, UI.noteBadge(n)) : h('span', { class: 'picked-empty' }, '?'));
    }
  }

  function checkTheory(ans, btn) {
    if (gameState.locked) return;
    const q = gameState.q;
    let ok;
    if (q.kind === 'pc') ok = ans === q.answer;
    else if (q.kind === 'spelled') ok = T.sameNote(ans, q.answer);
    else if (q.kind === 'multi') ok = ans.length === q.answer.length && q.answer.every((a) => ans.some((x) => T.sameNote(x, a)));
    else ok = ans === q.answer;
    gameState.locked = true;
    GQ.Store.recordTheory(state.game.id, ok);
    if (ok) {
      gameState.streak++; gameState.score += 10 + (gameState.streak >= 3 ? 5 : 0);
      GQ.Store.recordTheoryBest(state.game.id + ':' + state.game.level, gameState.streak);
      if (btn) btn.classList.add('good');
      GQ.Audio.chime(true);
      let shown = '';
      if (q.kind === 'spelled') shown = T.noteLabel(q.answer, nm()) + '. ';
      setTg('Correct! ' + shown + q.explain, 'good');
      setTimeout(() => { if (document.getElementById('tgQ')) nextTheory(); }, 1700);
    } else {
      gameState.streak = 0;
      if (btn) btn.classList.add('bad');
      GQ.Audio.chime(false);
      let right = '';
      if (q.kind === 'pc') right = T.pcLabel(q.answer, nm(), 'both');
      else if (q.kind === 'spelled') right = T.noteLabel(q.answer, nm());
      else if (q.kind === 'multi') right = q.answer.map((n) => T.noteLabel(n, nm())).join(' ');
      else right = q.answer;
      if (q.kind === 'choice' || q.kind === 'pc') document.querySelectorAll('#tgPad button').forEach((b) => { if (b.textContent === right || (q.kind === 'pc' && Number(b.dataset.pc) === q.answer)) b.classList.add('good'); });
      setTg('The answer is ' + right + '. ' + q.explain, 'bad');
      document.getElementById('tgNext').hidden = false;
    }
    document.getElementById('tgScore').textContent = String(gameState.score);
    document.getElementById('tgStreak').textContent = String(gameState.streak);
  }
  function setTg(t, k) { const el = document.getElementById('tgFb'); if (el) { el.textContent = t; el.className = 'feedback ' + (k || ''); } }

  function onSettings() { renderTab(); }

  GQ.Views.harmony = { mount, unmount, onSettings, PROGS, STRUMS, progChords };
})(window.GQ = window.GQ || {});
