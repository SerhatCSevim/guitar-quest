/* Guitar Quest - Fretboard Explorer: tap a fret, see the note name, the tab and the staff together. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory, UI = GQ.UI;
  const { h, clear, segmented, field } = UI;
  GQ.Views = GQ.Views || {};

  const state = { show: 'none', find: null, sel: null };
  let fb, scoreView, cards, walkTimers = [], els = {};

  function settings() { return GQ.Store.settings(); }
  function namingShort() { const n = settings().naming; return n === 'both' ? 'letters' : n; }

  function spellFor(pc) {
    const pref = settings().accidentals === 'flat' ? 'flat' : 'sharp';
    return T.spellPc(pc, pref);
  }

  function mount(el) {
    const root = h('section', { class: 'explore' });
    root.appendChild(h('div', { class: 'view-head' },
      h('h1', null, 'Fretboard Explorer'),
      h('p', { class: 'lead' }, 'Tap any fret. You will hear the note and see its name, its tab number and how it looks on the staff.')));

    const letters = h('div', { class: 'letter-row' });
    for (let l = 0; l < 7; l++) {
      const pc = T.LETTER_PC[l];
      const c = UI.letterColor(l);
      letters.appendChild(h('button', {
        type: 'button', class: 'letter-btn', dataset: { pc: String(pc) }, style: { '--c': c, '--on': UI.inkOn(c) },
        onclick: () => { state.find = state.find === pc ? null : pc; draw(); },
      }, T.noteLabel({ l, a: 0 }, namingShort())));
    }
    els.letters = letters;
    const walk = h('div', { class: 'walk-row' });
    for (let s = 6; s >= 1; s--) {
      walk.appendChild(h('button', { type: 'button', class: 'chip', title: 'Play string ' + s + ' from open to fret 12', onclick: () => walkString(s) },
        s + ' ' + T.OPEN_NAMES[s]));
    }
    root.appendChild(h('div', { class: 'toolbar card' },
      field('Show note names', segmented([
        { value: 'none', label: 'Hidden' }, { value: 'naturals', label: 'Natural notes' }, { value: 'all', label: 'All notes' },
      ], state.show, (v) => { state.show = v; draw(); })),
      field('Find every…', letters),
      field('Walk up a string', walk)));

    const fbCard = h('div', { class: 'card fb-card' });
    root.appendChild(fbCard);
    fb = new GQ.Fretboard(fbCard, { maxFret: 15, onSelect: (s, f) => select(s, f, true) });

    cards = h('div', { class: 'grid3 explore-info' });
    els.noteCard = h('div', { class: 'card note-card' });
    els.scoreCard = h('div', { class: 'card' }, h('h3', null, 'Tab and staff'));
    const scoreHost = h('div', { class: 'mini-score' });
    els.scoreCard.appendChild(scoreHost);
    els.scoreCard.appendChild(h('p', { class: 'small muted' }, 'Guitar music is written one octave higher than it sounds, so it fits on the treble staff.'));
    els.ladderCard = h('div', { class: 'card' });
    cards.append(els.noteCard, els.scoreCard, els.ladderCard);
    root.appendChild(cards);
    scoreView = new GQ.Notation.ScoreView(scoreHost, { showStaff: true, showTab: true, showNames: true, minWidth: 220, autoScroll: false });

    root.appendChild(alphabetCard());
    el.appendChild(root);
    if (!state.sel) state.sel = { string: 3, fret: 2 };
    select(state.sel.string, state.sel.fret, false);
  }

  function unmount() {
    stopWalk();
    if (scoreView) scoreView.destroy();
  }

  function select(string, fret, play) {
    stopWalk();
    state.sel = { string, fret };
    if (play) GQ.Audio.pluck(T.midiAt(string, fret), 0, { duration: 1.6 });
    draw();
    drawInfo();
  }

  function draw() {
    const marks = [];
    const sel = state.sel;
    const selMidi = sel ? T.midiAt(sel.string, sel.fret) : null;
    for (let s = 1; s <= 6; s++) {
      for (let f = 0; f <= 15; f++) {
        const midi = T.midiAt(s, f), pc = T.mod(midi, 12);
        if (sel && s === sel.string && f === sel.fret) continue;
        if (state.find !== null) {
          if (pc === state.find) marks.push(GQ.noteMark(s, f, { cls: 'pop' }));
          continue;
        }
        if (sel && midi === selMidi) { marks.push(Object.assign(GQ.noteMark(s, f), { kind: 'ring' })); continue; }
        if (state.show === 'all' || (state.show === 'naturals' && T.isNaturalPc(pc))) marks.push(Object.assign(GQ.noteMark(s, f), { cls: 'soft' }));
      }
    }
    if (sel) marks.push(GQ.noteMark(sel.string, sel.fret, { kind: 'root', cls: 'pop' }));
    fb.setMarks(marks);
    fb.highlightString(sel ? sel.string : null);
    Array.from(els.letters.children).forEach((b) => b.classList.toggle('on', Number(b.dataset.pc) === state.find));
    if (els.keys) Array.from(els.keys.querySelectorAll('[data-pc]')).forEach((k) => k.classList.toggle('on', sel && Number(k.dataset.pc) === T.mod(selMidi, 12)));
  }

  function drawInfo() {
    const sel = state.sel;
    const st = settings();
    const midi = T.midiAt(sel.string, sel.fret), pc = T.mod(midi, 12);
    const spelled = spellFor(pc);
    // note card
    clear(els.noteCard);
    const badgeLabel = T.pcLabel(pc, namingShort(), T.isNaturalPc(pc) ? st.accidentals : 'both');
    const color = UI.pcColor(pc);
    els.noteCard.appendChild(h('div', { class: 'big-note', style: { background: color, color: UI.inkOn(color) } }, badgeLabel));
    els.noteCard.appendChild(h('div', { class: 'note-facts' },
      h('div', null, h('strong', null, 'String ' + sel.string), ' (' + T.OPEN_NAMES[sel.string] + ' string) · ', h('strong', null, sel.fret === 0 ? 'open' : 'fret ' + sel.fret)),
      h('div', { class: 'muted' }, 'Tab number: ', h('span', { class: 'tab-chip' }, String(sel.fret)), ' on line ' + sel.string + ' from the top'),
      st.naming !== 'letters' ? h('div', { class: 'muted' }, 'Letter name: ' + T.pcLabel(pc, 'letters', 'both')) : null,
      !T.isNaturalPc(pc) ? h('div', { class: 'muted' }, 'A black-key note: it has two names.') : null));
    const others = T.positionsOfMidi(midi, 15).filter((p) => !(p.string === sel.string && p.fret === sel.fret));
    if (others.length) {
      const list = h('div', { class: 'chips' });
      others.forEach((p) => list.appendChild(h('button', { type: 'button', class: 'chip', onclick: () => select(p.string, p.fret, true) }, 'string ' + p.string + ', fret ' + p.fret)));
      els.noteCard.appendChild(h('div', { class: 'same-note' }, h('div', { class: 'small' }, 'The very same note (same sound) is also here:'), list));
    }
    // staff + tab
    const score = GQ.Exercises.finalize([{ dur: 48, tuplet: 0, notes: [{ string: sel.string, fret: sel.fret, midi, spelled }] }],
      { keySig: T.keySignature({ l: 0, a: 0 }, 'major'), tempo: 60, title: '' });
    scoreView.setOptions({ colors: st.colors, naming: namingShort() });
    scoreView.setScore(score);
    drawLadder(sel, pc);
  }

  // "How to find it": count frets from the open string (or back from fret 12).
  function drawLadder(sel, pc) {
    clear(els.ladderCard);
    els.ladderCard.appendChild(h('h3', null, 'How to find it'));
    const open = T.TUNING[sel.string];
    let frets = [];
    let intro;
    if (sel.fret <= 7) {
      for (let f = 0; f <= sel.fret; f++) frets.push(f);
      intro = 'Start from the open string (' + T.OPEN_NAMES[sel.string].toUpperCase() + ') and go up one fret at a time:';
    } else if (sel.fret <= 12) {
      for (let f = 12; f >= sel.fret; f--) frets.push(f);
      intro = 'Fret 12 is the open-string note again, one octave higher. Count back from there:';
    } else {
      for (let f = 12; f <= sel.fret; f++) frets.push(f);
      intro = 'Fret 12 is the open-string note again. Count up from there:';
    }
    els.ladderCard.appendChild(h('p', { class: 'small' }, intro));
    const row = h('div', { class: 'ladder' });
    const nm = namingShort(), pref = GQ.Store.settings().accidentals;
    frets.forEach((f, k) => {
      const p = T.mod(open + f, 12);
      const c = UI.pcColor(p);
      row.appendChild(h('div', { class: 'rung' + (f === sel.fret ? ' target' : '') },
        h('span', { class: 'rung-note', style: { background: c, color: UI.inkOn(c) } }, T.pcLabel(p, nm, pref)),
        h('span', { class: 'rung-fret' }, f === 0 ? 'open' : 'fret ' + f)));
      if (k < frets.length - 1) row.appendChild(h('span', { class: 'rung-arrow' }, '›'));
    });
    els.ladderCard.appendChild(row);
    const names = frets.map((f) => T.mod(open + f, 12));
    const crosses = names.some((p, k) => k > 0 && ((names[k - 1] === 4 && p === 5) || (names[k - 1] === 5 && p === 4) || (names[k - 1] === 11 && p === 0) || (names[k - 1] === 0 && p === 11)));
    if (crosses) els.ladderCard.appendChild(h('p', { class: 'tip' }, 'Remember: E → F and B → C are only one fret apart. There is no black key between them.'));
    else els.ladderCard.appendChild(h('p', { class: 'tip' }, 'One fret = one half step. Two frets = one whole step.'));
  }

  function alphabetCard() {
    const card = h('div', { class: 'card alphabet' });
    card.appendChild(h('h3', null, 'The musical alphabet'));
    card.appendChild(h('p', { class: 'small' }, 'Music uses only seven letters, then starts again. Most neighbours are 2 frets apart, but E–F and B–C are only 1 fret apart.'));
    const row = h('div', { class: 'alpha-row' });
    const seq = [0, 1, 2, 3, 4, 5, 6, 0];
    seq.forEach((l, k) => {
      const c = UI.letterColor(l);
      row.appendChild(h('button', { type: 'button', class: 'alpha-letter', style: { background: c, color: UI.inkOn(c) }, onclick: () => { state.find = T.LETTER_PC[l]; draw(); } }, T.noteLabel({ l, a: 0 }, namingShort())));
      if (k < seq.length - 1) {
        const half = l === 2 || l === 6;
        row.appendChild(h('span', { class: 'alpha-step' + (half ? ' half' : '') }, half ? '1 fret' : '2 frets'));
      }
    });
    card.appendChild(row);
    card.appendChild(pianoOctave());
    return card;
  }

  function pianoOctave() {
    const wrap = h('div', { class: 'piano' });
    const whites = [0, 2, 4, 5, 7, 9, 11], blacks = [[1, 0], [3, 1], [6, 3], [8, 4], [10, 5]];
    const nm = namingShort();
    whites.forEach((pc, k) => wrap.appendChild(h('button', {
      type: 'button', class: 'key white', dataset: { pc: String(pc) }, style: { left: (k * 14.2857) + '%' },
      onclick: () => { state.find = pc; GQ.Audio.pluck(60 + pc, 0, { duration: 1.2 }); draw(); },
    }, h('span', null, T.pcLabel(pc, nm, 'sharp')))));
    blacks.forEach(([pc, after]) => wrap.appendChild(h('button', {
      type: 'button', class: 'key black', dataset: { pc: String(pc) }, style: { left: ((after + 1) * 14.2857 - 4.2) + '%' }, title: T.pcLabel(pc, nm, 'both'),
      onclick: () => { state.find = pc; GQ.Audio.pluck(60 + pc, 0, { duration: 1.2 }); draw(); },
    })));
    els.keys = wrap;
    return h('div', { class: 'piano-wrap' }, wrap, h('p', { class: 'small muted' }, 'Piano view of the same notes. Tap a key to find it on the guitar.'));
  }

  function walkString(s) {
    stopWalk();
    state.find = null;
    const A = GQ.Audio;
    if (!A.ensure()) return;
    const t0 = A.now() + 0.1, step = 0.32;
    const marks = [];
    for (let f = 0; f <= 12; f++) {
      A.pluck(T.midiAt(s, f), t0 + f * step, { duration: step + 0.1 });
      walkTimers.push(setTimeout(() => {
        marks.push(GQ.noteMark(s, f, { cls: 'pop' }));
        fb.setMarks(marks.slice());
        fb.highlightString(s);
      }, (0.1 + f * step) * 1000));
    }
    walkTimers.push(setTimeout(() => { state.sel = { string: s, fret: 12 }; drawInfo(); }, (0.1 + 13 * step) * 1000));
  }
  function stopWalk() { walkTimers.forEach(clearTimeout); walkTimers = []; }

  function onSettings() {
    if (!fb) return;
    const el = document.getElementById('view');
    unmount(); clear(el); mount(el);
  }

  GQ.Views.explore = { mount, unmount, onSettings };
})(window.GQ = window.GQ || {});
