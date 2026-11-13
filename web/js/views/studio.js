/* Guitar Quest - Practice Studio: Guitar-Pro-style player with staff + tab, tempo, metronome, loop and speed trainer. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory, UI = GQ.UI, E = GQ.Exercises;
  const { h, clear, segmented, select, field, icon } = UI;
  GQ.Views = GQ.Views || {};

  const state = {
    source: 'scale', tonic: 'A', scaleId: 'minorPent', shapeId: 'box1', pattern: 'updown', rhythm: 'e', range: 'full',
    songId: 'mary', bpm: 80, loop: true, metronome: true, countIn: true, sound: true,
    trainer: false, trainerStep: 5, trainerTarget: 120, view: 'both', names: true,
  };
  let root, scoreView, transport, fb, els = {}, score = null, keyHandler = null;

  function nm() { const n = GQ.Store.settings().naming; return n === 'both' ? 'letters' : n; }

  function mount(el, params) {
    if (params) {
      Object.assign(state, params);
      if (params.source === 'scale') state.range = T.SCALES[state.scaleId].pent ? 'full' : 'root';
    }
    root = h('section', { class: 'studio' });
    el.appendChild(root);
    root.appendChild(h('div', { class: 'view-head' },
      h('h1', null, 'Practice Studio'),
      h('p', { class: 'lead' }, 'Pick an exercise, press play and follow the moving cursor. Start slow, then let the speed trainer push the tempo up.')));
    els.source = h('div', { class: 'card source-card' });
    root.appendChild(els.source);
    els.bar = h('div', { class: 'transport card' });
    root.appendChild(els.bar);
    els.title = h('div', { class: 'score-title' });
    root.appendChild(els.title);
    els.scoreWrap = h('div', { class: 'card score-card' });
    els.countdown = h('div', { class: 'countdown', hidden: true });
    els.scoreWrap.appendChild(els.countdown);
    const scoreHost = h('div', { class: 'score-host' });
    els.scoreWrap.appendChild(scoreHost);
    root.appendChild(els.scoreWrap);
    const fbCard = h('div', { class: 'card fb-card' });
    root.appendChild(fbCard);
    fb = new GQ.Fretboard(fbCard, { maxFret: 15, compact: true, onSelect: (s, f) => GQ.Audio.pluck(T.midiAt(s, f), 0, { duration: 1 }) });
    scoreView = new GQ.Notation.ScoreView(scoreHost, {
      showStaff: state.view !== 'tab', showTab: state.view !== 'staff', showNames: state.names,
      colors: GQ.Store.settings().colors, naming: nm(), onSeek: (i) => transport.seek(i),
    });
    transport = new GQ.Transport({
      onPosition: onPosition,
      onState: onState,
      onLoop: (bpm) => { state.bpm = bpm; syncTempo(); UI.toast('Speed trainer: ' + bpm + ' BPM'); },
    });
    keyHandler = (e) => {
      if (e.target && /INPUT|SELECT|TEXTAREA|BUTTON/.test(e.target.tagName) && e.key === ' ') return;
      if (e.key === ' ') { e.preventDefault(); togglePlay(); }
      else if (e.key === 'Escape') transport.stop();
    };
    document.addEventListener('keydown', keyHandler);
    renderSource();
    renderBar();
    build();
  }

  function unmount() {
    if (transport) transport.stop();
    if (scoreView) scoreView.destroy();
    if (keyHandler) document.removeEventListener('keydown', keyHandler);
    keyHandler = null;
    GQ.PracticeClock.stop('studio');
  }

  /* ---------- exercise picker ---------- */
  function renderSource() {
    clear(els.source);
    els.source.appendChild(field('Practise', segmented([{ value: 'scale', label: 'Scale exercise' }, { value: 'song', label: 'Song' }], state.source, (v) => { state.source = v; renderSource(); build(); })));
    if (state.source === 'scale') {
      const sc = T.SCALES[state.scaleId];
      const keys = T.keyNames(sc.family);
      if (keys.indexOf(state.tonic) < 0) state.tonic = keys[0];
      const shapes = T.shapeOptions(state.scaleId).filter((o) => o.id !== 'neck');
      if (!shapes.some((o) => o.id === state.shapeId)) state.shapeId = shapes[0].id;
      const grid = h('div', { class: 'source-grid' },
        field('Scale', select(Object.keys(T.SCALES).map((id) => ({ value: id, label: T.SCALES[id].name })), state.scaleId, (v) => {
          const pc = T.notePc(T.parseNote(state.tonic));
          state.scaleId = v;
          const ks = T.keyNames(T.SCALES[v].family);
          state.tonic = ks.find((k) => T.notePc(T.parseNote(k)) === pc) || ks[0];
          state.range = T.SCALES[v].pent ? 'full' : 'root';
          renderSource(); build();
        })),
        field('Key', select(keys.map((k) => ({ value: k, label: T.noteLabel(T.parseNote(k), nm()) + (sc.family === 'minor' ? ' minor' : ' major') })), state.tonic, (v) => { state.tonic = v; build(); })),
        field('Shape', select(shapes.map((o) => ({ value: o.id, label: o.name })), state.shapeId, (v) => { state.shapeId = v; build(); })),
        field('Pattern', select(Object.keys(E.PATTERNS).map((p) => ({ value: p, label: E.PATTERNS[p] })), state.pattern, (v) => { state.pattern = v; build(); })),
        field('Rhythm', select(Object.keys(E.RHYTHMS).map((r) => ({ value: r, label: E.RHYTHMS[r].name })), state.rhythm, (v) => { state.rhythm = v; build(); })),
        field('Range', segmented([{ value: 'root', label: 'Root to root' }, { value: 'full', label: 'Whole shape' }], state.range, (v) => { state.range = v; build(); })));
      els.source.appendChild(grid);
    } else {
      const list = h('div', { class: 'song-list' });
      GQ.SONGS.forEach((s) => {
        list.appendChild(h('button', { type: 'button', class: 'song-card' + (s.id === state.songId ? ' on' : ''), onclick: () => { state.songId = s.id; renderSource(); build(); } },
          h('strong', null, s.title), h('span', { class: 'small muted' }, s.origin), h('span', { class: 'tag' }, s.strings)));
      });
      els.source.appendChild(list);
    }
  }

  function build() {
    transport.stop();
    try {
      if (state.source === 'scale') {
        score = E.buildScaleScore({ tonic: state.tonic, scaleId: state.scaleId, shapeId: state.shapeId, pattern: state.pattern, rhythm: state.rhythm, range: state.range, tempo: state.bpm });
      } else {
        const song = GQ.SONGS.find((s) => s.id === state.songId) || GQ.SONGS[0];
        score = E.buildSongScore(song);
        state.bpm = Math.min(state.bpm, song.tempo);
        syncTempo();
      }
    } catch (e) {
      score = null;
      els.title.textContent = 'Could not build this exercise: ' + e.message;
      return;
    }
    clear(els.title);
    els.title.appendChild(h('h2', null, score.title));
    els.title.appendChild(h('span', { class: 'muted' }, score.subtitle));
    scoreView.setOptions({ colors: GQ.Store.settings().colors, naming: nm() });
    scoreView.setScore(score);
    const tl = E.timeline(score);
    transport.load(tl, score.totalTicks / E.TPB, 4);
    applyTransportFlags();
    // fretboard: the whole exercise shape stays visible in the background
    const maxF = Math.max.apply(null, score.events.map((ev) => (ev.notes.length ? ev.notes[0].fret : 0)));
    fb.setMaxFret(Math.max(15, maxF + 1));
    els.baseMarks = [];
    const seen = new Set();
    score.events.forEach((ev) => ev.notes.forEach((n) => {
      const k = n.string + ':' + n.fret;
      if (seen.has(k)) return;
      seen.add(k);
      els.baseMarks.push(Object.assign(GQ.noteMark(n.string, n.fret, { spelled: n.spelled }), { kind: 'ghost' }));
    }));
    fb.setMarks(els.baseMarks);
  }

  /* ---------- transport bar ---------- */
  function renderBar() {
    clear(els.bar);
    els.playBtn = h('button', { type: 'button', class: 'tbtn play', title: 'Play / pause (space)', onclick: togglePlay }, icon('play'));
    const stopBtn = h('button', { type: 'button', class: 'tbtn', title: 'Stop (Esc)', onclick: () => transport.stop() }, icon('stop'));
    const toggle = (key, label, ic, title) => {
      const b = h('button', { type: 'button', class: 'tbtn toggle' + (state[key] ? ' on' : ''), title, 'aria-pressed': state[key] ? 'true' : 'false' }, ic ? icon(ic) : null, h('span', null, label));
      b.addEventListener('click', () => {
        state[key] = !state[key];
        b.classList.toggle('on', state[key]);
        b.setAttribute('aria-pressed', state[key] ? 'true' : 'false');
        applyTransportFlags();
        if (key === 'trainer') els.trainerBox.classList.toggle('dim', !state.trainer);
      });
      return b;
    };
    els.tempoVal = h('span', { class: 'tempo-val' });
    els.tempoRange = h('input', { type: 'range', min: '30', max: '220', step: '1', class: 'tempo-range', 'aria-label': 'Tempo' });
    els.tempoRange.addEventListener('input', () => { state.bpm = Number(els.tempoRange.value); transport.setTempo(state.bpm); syncTempo(); });
    const minus = h('button', { type: 'button', class: 'tbtn small', title: 'Slower', onclick: () => bump(-5) }, '−5');
    const plus = h('button', { type: 'button', class: 'tbtn small', title: 'Faster', onclick: () => bump(5) }, '+5');
    const stepSel = select([2, 5, 10].map((v) => ({ value: v, label: '+' + v })), state.trainerStep, (v) => { state.trainerStep = Number(v); applyTransportFlags(); }, { 'aria-label': 'Tempo step per loop' });
    const targetIn = h('input', { type: 'number', min: '40', max: '220', value: String(state.trainerTarget), class: 'num', 'aria-label': 'Target tempo' });
    targetIn.addEventListener('change', () => { state.trainerTarget = Math.max(40, Math.min(220, Number(targetIn.value) || 120)); targetIn.value = state.trainerTarget; applyTransportFlags(); });
    els.trainerBox = h('div', { class: 'trainer' + (state.trainer ? '' : ' dim') }, toggle('trainer', 'Speed trainer', null, 'Raise the tempo after every loop'),
      h('span', { class: 'small' }, 'each loop'), stepSel, h('span', { class: 'small' }, 'up to'), targetIn, h('span', { class: 'small' }, 'BPM'));
    els.bar.append(
      h('div', { class: 'tgroup' }, els.playBtn, stopBtn, toggle('loop', 'Loop', 'loop', 'Repeat from the start')),
      h('div', { class: 'tgroup tempo' }, h('span', { class: 'small muted' }, 'Tempo'), minus, els.tempoRange, plus, els.tempoVal),
      h('div', { class: 'tgroup' }, toggle('metronome', 'Click', 'metro', 'Metronome'), toggle('countIn', 'Count-in', null, 'One bar of clicks before starting'), toggle('sound', 'Guitar', 'speaker', 'Hear the guitar part (turn off to play it yourself)')),
      els.trainerBox,
      h('div', { class: 'tgroup' },
        segmented([{ value: 'both', label: 'Staff + Tab' }, { value: 'tab', label: 'Tab' }, { value: 'staff', label: 'Staff' }], state.view, (v) => {
          state.view = v; scoreView.setOptions({ showStaff: v !== 'tab', showTab: v !== 'staff' });
        }),
        toggleNames()));
    syncTempo();
  }
  function toggleNames() {
    const b = h('button', { type: 'button', class: 'tbtn toggle' + (state.names ? ' on' : ''), title: 'Show note names under the tab' }, h('span', null, 'Note names'));
    b.addEventListener('click', () => { state.names = !state.names; b.classList.toggle('on', state.names); scoreView.setOptions({ showNames: state.names }); });
    return b;
  }
  function bump(d) { state.bpm = Math.max(30, Math.min(220, state.bpm + d)); transport.setTempo(state.bpm); syncTempo(); }
  function syncTempo() {
    if (!els.tempoVal) return;
    els.tempoVal.textContent = state.bpm + ' BPM';
    els.tempoRange.value = String(state.bpm);
  }
  function applyTransportFlags() {
    transport.loop = state.loop;
    transport.metronome = state.metronome;
    transport.countIn = state.countIn;
    transport.sound = state.sound;
    transport.bpm = state.bpm;
    transport.trainer = { on: state.trainer && state.loop, step: state.trainerStep, target: state.trainerTarget };
  }

  function togglePlay() {
    if (!score) return;
    if (transport.playing) transport.pause();
    else { applyTransportFlags(); transport.play(); }
  }

  function onState(playing) {
    clear(els.playBtn).appendChild(icon(playing ? 'pause' : 'play'));
    els.playBtn.classList.toggle('on', playing);
    if (playing) GQ.PracticeClock.start('studio'); else GQ.PracticeClock.stop('studio');
    if (!playing) els.countdown.hidden = true;
  }

  function onPosition(i, countdown, beat, seeking) {
    els.countdown.hidden = !(countdown > 0 && transport.playing);
    if (countdown > 0) els.countdown.textContent = String(countdown);
    const evs = score ? score.events : [];
    let next = -1;
    if (i >= 0) { for (let k = i + 1; k < evs.length; k++) if (!evs[k].rest) { next = k; break; } }
    scoreView.setActive(i, next);
    const marks = els.baseMarks ? els.baseMarks.slice() : [];
    if (i >= 0 && evs[i]) {
      if (next >= 0) evs[next].notes.forEach((n) => marks.push(Object.assign(GQ.noteMark(n.string, n.fret, { spelled: n.spelled }), { kind: 'ring', label: '' })));
      evs[i].notes.forEach((n) => marks.push(GQ.noteMark(n.string, n.fret, { spelled: n.spelled, kind: 'root', cls: seeking ? '' : 'pop' })));
    }
    fb.setMarks(marks);
  }

  function onSettings() {
    if (!scoreView) return;
    scoreView.setOptions({ colors: GQ.Store.settings().colors, naming: nm() });
    renderSource();
    build();
  }

  GQ.Views.studio = { mount, unmount, onSettings };
})(window.GQ = window.GQ || {});
