/* Guitar Quest - Scales: major, minor, pentatonic and blues shapes on the neck. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory, UI = GQ.UI;
  const { h, clear, segmented, select, field, icon } = UI;
  GQ.Views = GQ.Views || {};

  const state = { scaleId: 'minorPent', key: 'A', shape: 'box1', labels: 'names' };
  let root, fb, scoreView, transport, els = {};

  const SCALE_TABS = [
    { value: 'major', label: 'Major' }, { value: 'minor', label: 'Minor' },
    { value: 'majorPent', label: 'Major pentatonic' }, { value: 'minorPent', label: 'Minor pentatonic' }, { value: 'blues', label: 'Blues' },
  ];
  function nm() { const n = GQ.Store.settings().naming; return n === 'both' ? 'letters' : n; }

  function fixState() {
    const keys = T.keyNames(T.SCALES[state.scaleId].family);
    if (keys.indexOf(state.key) < 0) {
      // keep the same sound when switching between e.g. Db major and C# minor
      const pc = T.notePc(T.parseNote(state.key));
      state.key = keys.find((k) => T.notePc(T.parseNote(k)) === pc) || keys[0];
    }
    const shapes = T.shapeOptions(state.scaleId).map((o) => o.id);
    if (shapes.indexOf(state.shape) < 0) state.shape = T.SCALES[state.scaleId].pent ? 'box1' : 'open';
  }

  function mount(el, params) {
    if (params) Object.assign(state, params);
    fixState();
    root = h('section', { class: 'scales' });
    el.appendChild(root);
    root.appendChild(h('div', { class: 'view-head' },
      h('h1', null, 'Scales'),
      h('p', { class: 'lead' }, 'Choose a scale and a key. Bright dots are the shape to learn, faint dots show the same scale everywhere else on the neck.')));
    els.controls = h('div', { class: 'toolbar card' });
    root.appendChild(els.controls);
    const fbCard = h('div', { class: 'card fb-card' });
    root.appendChild(fbCard);
    fb = new GQ.Fretboard(fbCard, { maxFret: 15, onSelect: (s, f) => GQ.Audio.pluck(T.midiAt(s, f), 0, { duration: 1.2 }) });
    els.info = h('div', { class: 'grid2' });
    root.appendChild(els.info);
    transport = new GQ.Transport({
      onPosition: (i) => highlight(i),
      onState: (playing) => { if (els.playBtn) { clear(els.playBtn).appendChild(icon(playing ? 'stop' : 'play')); els.playBtn.appendChild(document.createTextNode(playing ? ' Stop' : ' Hear it')); } },
    });
    transport.metronome = false; transport.countIn = false;
    render();
  }
  function unmount() {
    if (transport) transport.stop();
    if (scoreView) scoreView.destroy();
  }

  function render() {
    fixState();
    transport.stop();
    clear(els.controls);
    const sc = T.SCALES[state.scaleId];
    els.controls.appendChild(field('Scale', segmented(SCALE_TABS, state.scaleId, (v) => { state.scaleId = v; render(); })));
    const keyRow = h('div', { class: 'key-row' });
    T.keyNames(sc.family).forEach((k) => {
      keyRow.appendChild(h('button', { type: 'button', class: 'key-btn' + (k === state.key ? ' on' : ''), onclick: () => { state.key = k; render(); } },
        T.noteLabel(T.parseNote(k), nm()) + (sc.family === 'minor' ? 'm' : '')));
    });
    els.controls.appendChild(field('Key', keyRow));
    els.controls.appendChild(field('Shape', select(T.shapeOptions(state.scaleId).map((o) => ({ value: o.id, label: o.name })), state.shape, (v) => { state.shape = v; render(); })));
    els.controls.appendChild(field('Dots show', segmented([{ value: 'names', label: 'Note names' }, { value: 'degrees', label: 'Scale steps' }, { value: 'none', label: 'Nothing' }], state.labels, (v) => { state.labels = v; drawBoard(); })));
    els.playBtn = h('button', { type: 'button', class: 'btn primary', onclick: togglePlay }, icon('play'), ' Hear it');
    els.controls.appendChild(h('div', { class: 'toolbar-actions' }, els.playBtn,
      h('button', { type: 'button', class: 'btn', disabled: state.shape === 'neck' ? true : null, title: state.shape === 'neck' ? 'Pick a shape first' : '',
        onclick: () => GQ.App.go('studio', { source: 'scale', tonic: state.key, scaleId: state.scaleId, shapeId: state.shape }) }, 'Practise in the Studio →')));
    drawBoard();
    drawInfo();
  }

  function currentShape() {
    const tonic = T.parseNote(state.key);
    return T.buildShape(tonic, state.scaleId, state.shape, 15);
  }

  function markFor(n, extra) {
    const settings = GQ.Store.settings();
    const color = settings.colors ? UI.spelledColor(n.spelled) : '#37474F';
    let label = '';
    if (state.labels === 'names') label = T.noteLabel(n.spelled, nm());
    else if (state.labels === 'degrees') label = n.label;
    return Object.assign({ string: n.string, fret: n.fret, label, color, textColor: UI.inkOn(color), kind: n.isRoot ? 'root' : 'note' }, extra || {});
  }

  function drawBoard(activeIdx) {
    const shape = currentShape();
    fb.setMaxFret(Math.max(15, shape.maxFret + 1));
    const tonic = T.parseNote(state.key);
    const marks = [];
    if (state.shape !== 'neck') {
      const inShape = new Set(shape.notes.map((n) => n.string + ':' + n.fret));
      T.buildShape(tonic, state.scaleId, 'neck', fb.opts.maxFret).notes.forEach((n) => {
        if (!inShape.has(n.string + ':' + n.fret)) marks.push(Object.assign(markFor(n), { kind: 'ghost', label: '' }));
      });
    }
    shape.notes.forEach((n, i) => marks.push(markFor(n, i === activeIdx ? { cls: 'playing' } : null)));
    fb.setMarks(marks);
    els.shapeNotes = shape.notes;
  }

  function drawInfo() {
    clear(els.info);
    const sc = T.SCALES[state.scaleId];
    const tonic = T.parseNote(state.key);
    const notes = T.scaleNotes(tonic, state.scaleId);
    // notes and steps
    const card1 = h('div', { class: 'card' }, h('h3', null, T.noteLabel(tonic, nm()) + ' ' + sc.name.toLowerCase() + ' - the notes'));
    const row = h('div', { class: 'scale-row' });
    const steps = T.stepPattern(state.scaleId);
    notes.concat([Object.assign({}, notes[0], { label: '8' })]).forEach((n, i) => {
      row.appendChild(h('div', { class: 'scale-note' }, UI.noteBadge({ l: n.l, a: n.a }), h('span', { class: 'deg' }, n.label)));
      if (i < notes.length) row.appendChild(h('span', { class: 'step ' + (steps[i] === 'H' ? 'half' : steps[i] === 'W+H' ? 'wide' : '') }, steps[i]));
    });
    card1.appendChild(row);
    card1.appendChild(h('p', { class: 'small muted' }, 'W = whole step (2 frets) · H = half step (1 fret)' + (sc.pent ? ' · W+H = 3 frets' : '')));
    card1.appendChild(h('div', { class: 'mini-score scale-score' }));
    els.info.appendChild(card1);
    // facts
    const card2 = h('div', { class: 'card facts' }, h('h3', null, 'Good to know'));
    const ks = T.keySignature(tonic, sc.family);
    const ksText = ks.fifths === 0 ? 'no sharps or flats' : Math.abs(ks.fifths) + (ks.fifths > 0 ? ' sharp' : ' flat') + (Math.abs(ks.fifths) > 1 ? 's' : '') + ': ' + ks.list.map((n) => T.noteLabel(n, nm())).join(' ');
    const facts = [];
    if (sc.family === 'major') {
      const rel = T.relativeMinorOf(tonic);
      facts.push('Key signature of ' + T.noteLabel(tonic, nm()) + ' major: ' + ksText + '.');
      facts.push('Its relative minor is ' + T.noteLabel(rel, nm()) + ' minor - same notes, different home note (step 6).');
    } else {
      const rel = T.relativeMajorOf(tonic);
      facts.push('Key signature of ' + T.noteLabel(tonic, nm()) + ' minor: ' + ksText + '.');
      facts.push('Its relative major is ' + T.noteLabel(rel, nm()) + ' major - same notes, different home note.');
    }
    if (state.scaleId === 'major') facts.push('Every major scale follows the same step pattern: W W H W W W H.');
    if (state.scaleId === 'minor') facts.push('The natural minor pattern is W H W W H W W. It sounds darker because of the ♭3, ♭6 and ♭7.');
    if (state.scaleId === 'majorPent') facts.push('Major pentatonic = the major scale without steps 4 and 7 (1 2 3 5 6). No half steps, so it is hard to hit a "wrong" note!');
    if (state.scaleId === 'minorPent') facts.push('Minor pentatonic = 1 ♭3 4 5 ♭7. It is the most used scale for rock and blues solos.');
    if (state.scaleId === 'blues') facts.push('The blues scale is the minor pentatonic plus one extra "blue note", the ♭5.');
    if (sc.pent) facts.push('The 5 shapes link together up the neck like puzzle pieces. Shape 1 starts on the minor root on the 6th string. Major and minor pentatonic share the same shapes - only the home note moves.');
    if (/^3nps/.test(state.shape)) facts.push('3-notes-per-string forms stretch across the neck. They are great for speed but need a wider hand - go slowly!');
    if (state.shape === 'open') facts.push('Open position uses open strings and the first frets - the best place to start.');
    if (state.shape === 'r6' || state.shape === 'r5') facts.push('Root on the ' + (state.shape === 'r6' ? '6th' : '5th') + ' string: move this shape up or down the neck to play the scale in any key.');
    card2.appendChild(h('ul', null, facts.map((f) => h('li', null, f))));
    els.info.appendChild(card2);
    // written scale (one octave, staff + tab)
    const host = card1.querySelector('.scale-score');
    if (scoreView) scoreView.destroy();
    scoreView = new GQ.Notation.ScoreView(host, { showStaff: true, showTab: true, showNames: false, colors: GQ.Store.settings().colors, naming: nm(), minWidth: 360, autoScroll: false });
    const shapeId = state.shape === 'neck' ? (sc.pent ? 'box1' : 'open') : state.shape;
    try {
      const score = GQ.Exercises.buildScaleScore({ tonic: state.key, scaleId: state.scaleId, shapeId, pattern: 'up', rhythm: 'e', range: 'root' });
      requestAnimationFrame(() => scoreView.setScore(score));
    } catch (e) { host.textContent = ''; }
  }

  function togglePlay() {
    if (transport.playing) { transport.stop(); return; }
    if (state.shape === 'neck') { UI.toast('Pick a shape to hear it.'); return; }
    const shape = currentShape();
    const notes = shape.notes;
    const idx = T.patternIndices(notes.length, 'updown');
    const items = idx.map((k, i) => ({ i, beat: i * 0.5, beats: i === idx.length - 1 ? 1.5 : 0.5, rest: false, midis: [notes[k].midi], shapeIdx: k }));
    els.playOrder = idx;
    transport.load(items, items.length * 0.5 + 1);
    transport.bpm = 110;
    transport.play(0, true);
  }

  function highlight(i) {
    if (i < 0 || !els.playOrder) { drawBoard(); return; }
    drawBoard(els.playOrder[i]);
  }

  function onSettings() { render(); }

  GQ.Views.scales = { mount, unmount, onSettings };
})(window.GQ = window.GQ || {});
