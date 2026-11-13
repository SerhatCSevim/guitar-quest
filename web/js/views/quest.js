/* Guitar Quest - Note Quest: games that connect tab numbers, staff notes and note names to the fretboard. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory, UI = GQ.UI;
  const { h, clear, segmented, icon } = UI;
  GQ.Views = GQ.Views || {};

  const natural = (s, f) => T.isNaturalPc(T.mod(T.midiAt(s, f), 12));
  const LEVELS = [
    { id: 's12', name: 'Strings 1 & 2', hint: 'E F G on string 1 · B C D on string 2', maxFret: 3, test: (s, f) => (s === 1 || s === 2) && [0, 1, 3].indexOf(f) >= 0 },
    { id: 's34', name: 'Strings 3 & 4', hint: 'G A on string 3 · D E F on string 4', maxFret: 3, test: (s, f) => (s === 3 && [0, 2].indexOf(f) >= 0) || (s === 4 && [0, 2, 3].indexOf(f) >= 0) },
    { id: 's56', name: 'Strings 5 & 6', hint: 'A B C on string 5 · E F G on string 6', maxFret: 3, test: (s, f) => (s === 5 && [0, 2, 3].indexOf(f) >= 0) || (s === 6 && [0, 1, 3].indexOf(f) >= 0) },
    { id: 'first', name: 'First position', hint: 'Every natural note, frets 0-3, all strings', maxFret: 3, test: (s, f) => f <= 3 && natural(s, f) },
    { id: 'sharps', name: 'Sharps and flats', hint: 'Every note, frets 0-4', maxFret: 4, acc: true, test: (s, f) => f <= 4 },
    { id: 'bass', name: 'Bass strings up the neck', hint: 'Strings 6 and 5, natural notes, frets 0-12', maxFret: 12, test: (s, f) => s >= 5 && f <= 12 && natural(s, f) },
    { id: 'neck', name: 'Whole neck', hint: 'Natural notes on all strings, frets 0-12', maxFret: 12, test: (s, f) => f <= 12 && natural(s, f) },
    { id: 'master', name: 'Fretboard master', hint: 'Every note, frets 0-12', maxFret: 12, acc: true, test: (s, f) => f <= 12 },
  ];
  const GAMES = [
    { id: 'tab', name: 'Tab → Note', desc: 'A number on a tab line: which note is it?' },
    { id: 'staff', name: 'Staff → Fretboard', desc: 'A note on the staff: tap where it is on the guitar.' },
    { id: 'hunt', name: 'Note Hunt', desc: 'Find a note on the highlighted string.' },
  ];

  const lobby = { game: 'tab', mode: 'round', staffToo: false };
  let root = null, st = null, fb = null, timers = [], keyHandler = null, blitzTimer = null, scoreView = null;

  function nm() { const n = GQ.Store.settings().naming; return n === 'both' ? 'letters' : n; }
  function later(fn, ms) { timers.push(setTimeout(fn, ms)); }
  function clearTimers() { timers.forEach(clearTimeout); timers = []; clearInterval(blitzTimer); blitzTimer = null; }

  function mount(el) {
    root = h('section', { class: 'quest' });
    el.appendChild(root);
    showLobby();
  }
  function unmount() {
    clearTimers();
    if (keyHandler) document.removeEventListener('keydown', keyHandler);
    keyHandler = null;
    if (scoreView) { scoreView.destroy(); scoreView = null; }
    GQ.PracticeClock.stop('quest');
  }

  /* ---------------- lobby ---------------- */
  function showLobby() {
    unmount();
    clear(root);
    root.appendChild(h('div', { class: 'view-head' },
      h('h1', null, 'Note Quest'),
      h('p', { class: 'lead' }, 'Learn where every note lives. Pick a game, then a level. Three stars unlock bragging rights!')));
    const gameRow = h('div', { class: 'game-cards' });
    GAMES.forEach((g) => {
      gameRow.appendChild(h('button', {
        type: 'button', class: 'game-card' + (lobby.game === g.id ? ' on' : ''),
        onclick: () => { lobby.game = g.id; showLobby(); },
      }, gameArt(g.id), h('strong', null, g.name), h('span', null, g.desc)));
    });
    root.appendChild(gameRow);
    const opts = h('div', { class: 'toolbar card' },
      UI.field('Round', segmented([{ value: 'round', label: '10 questions' }, { value: 'blitz', label: '60-second blitz' }], lobby.mode, (v) => { lobby.mode = v; })),
      lobby.game === 'tab' ? UI.field('Also show the staff', segmented([{ value: 'no', label: 'No' }, { value: 'yes', label: 'Yes' }], lobby.staffToo ? 'yes' : 'no', (v) => { lobby.staffToo = v === 'yes'; })) : null);
    root.appendChild(opts);
    const grid = h('div', { class: 'level-grid' });
    LEVELS.forEach((lv, i) => {
      const info = GQ.Store.levelInfo(lobby.game, lv.id);
      grid.appendChild(h('div', { class: 'level-card' },
        h('div', { class: 'level-num' }, String(i + 1)),
        h('div', { class: 'level-body' }, h('strong', null, lv.name), h('span', { class: 'small muted' }, lv.hint),
          h('div', { class: 'stars' }, [0, 1, 2].map((k) => h('span', { class: 'star' + (k < info.stars ? ' on' : '') }, icon('star')))),
          info.plays ? h('span', { class: 'small muted' }, 'Best score ' + info.best) : null),
        h('button', { type: 'button', class: 'btn primary', onclick: () => startGame(i) }, 'Play')));
    });
    root.appendChild(grid);
  }

  function gameArt(id) {
    if (id === 'tab') return h('span', { class: 'game-art', html: '<svg viewBox="0 0 120 60"><g stroke="#9aa0ad" stroke-width="1.4">' + [10, 18, 26, 34, 42, 50].map((y) => '<line x1="6" x2="114" y1="' + y + '" y2="' + y + '"/>').join('') + '</g><rect x="52" y="19" width="16" height="14" fill="#fff"/><text x="60" y="31" text-anchor="middle" font-size="14" font-weight="800" fill="#1e2230">2</text><text x="96" y="31" font-size="14" font-weight="800" fill="#E0672B">= ?</text></svg>' });
    if (id === 'staff') return h('span', { class: 'game-art', html: '<svg viewBox="0 0 120 60"><g stroke="#9aa0ad" stroke-width="1.2">' + [14, 22, 30, 38, 46].map((y) => '<line x1="6" x2="114" y1="' + y + '" y2="' + y + '"/>').join('') + '</g><ellipse cx="60" cy="26" rx="6" ry="4.4" transform="rotate(-22 60 26)" fill="#5E35B1"/><line x1="65.5" x2="65.5" y1="26" y2="2" stroke="#1e2230" stroke-width="1.4"/></svg>' });
    return h('span', { class: 'game-art', html: '<svg viewBox="0 0 120 60"><rect x="6" y="8" width="108" height="44" rx="4" fill="#5a371b"/>' + [14, 21, 28, 35, 42, 49].map((y, k) => '<line x1="6" x2="114" y1="' + y + '" y2="' + y + '" stroke="' + (k === 2 ? '#ffd27a' : '#d9d2c3') + '" stroke-width="' + (k === 2 ? 2.4 : 1.1) + '"/>').join('') + [30, 52, 72, 90, 106].map((x) => '<line x1="' + x + '" x2="' + x + '" y1="8" y2="52" stroke="#c9c9c9" stroke-width="1.6"/>').join('') + '<circle cx="62" cy="28" r="6.5" fill="#0097A7"/></svg>' });
  }

  /* ---------------- game ---------------- */
  function buildPool(level) {
    const out = [];
    for (let s = 1; s <= 6; s++) for (let f = 0; f <= 15; f++) if (level.test(s, f)) out.push({ string: s, fret: f });
    return out;
  }

  function startGame(levelIdx) {
    unmount();
    const level = LEVELS[levelIdx];
    st = {
      game: lobby.game, mode: lobby.mode, staffToo: lobby.staffToo, level, levelIdx, pool: buildPool(level),
      total: lobby.mode === 'round' ? 10 : Infinity, q: 0, score: 0, streak: 0, bestStreak: 0, correct: 0, answered: 0,
      misses: {}, timeLeft: 60, last: null, locked: false, hint: false, cur: null,
    };
    clear(root);
    const g = GAMES.find((x) => x.id === st.game);
    const hud = h('div', { class: 'hud card' },
      h('button', { type: 'button', class: 'btn ghost', onclick: showLobby }, icon('back'), 'Levels'),
      h('div', { class: 'hud-title' }, h('strong', null, g.name), h('span', { class: 'muted' }, ' · ' + level.name)),
      h('div', { class: 'hud-progress', id: 'qProgress' }),
      h('div', { class: 'hud-stat' }, icon('star'), h('span', { id: 'qScore' }, '0')),
      h('div', { class: 'hud-stat flame' }, icon('flame'), h('span', { id: 'qStreak' }, '0')));
    root.appendChild(hud);
    const stage = h('div', { class: 'stage' });
    stage.appendChild(h('div', { class: 'card q-card', id: 'qCard' }));
    stage.appendChild(h('div', { class: 'answer-pad', id: 'qPad' }));
    stage.appendChild(h('div', { class: 'feedback', id: 'qFeedback', 'aria-live': 'polite' }));
    stage.appendChild(h('div', { class: 'q-actions' },
      h('button', { type: 'button', class: 'btn ghost', id: 'qHint', onclick: useHint }, icon('bulb'), 'Hint'),
      h('button', { type: 'button', class: 'btn primary', id: 'qNext', hidden: true, onclick: nextQuestion }, 'Next')));
    root.appendChild(stage);
    const fbCard = h('div', { class: 'card fb-card' });
    root.appendChild(fbCard);
    fb = new GQ.Fretboard(fbCard, {
      maxFret: level.maxFret > 4 ? 15 : 12,
      interactive: st.game !== 'tab',
      onSelect: (s, f) => answerPosition(s, f),
    });
    keyHandler = (e) => {
      if (e.target && /INPUT|SELECT|TEXTAREA/.test(e.target.tagName)) return;
      const nextBtn = document.getElementById('qNext');
      if ((e.key === 'Enter' || e.key === ' ') && nextBtn && !nextBtn.hidden) { e.preventDefault(); nextQuestion(); return; }
      if (st && st.game === 'tab' && !st.locked && /^[a-gA-G]$/.test(e.key) && !st.level.acc) {
        answerPc(T.LETTER_PC[T.LETTERS.indexOf(e.key.toUpperCase())]);
      }
    };
    document.addEventListener('keydown', keyHandler);
    GQ.PracticeClock.start('quest');
    if (st.mode === 'blitz') {
      blitzTimer = setInterval(() => {
        st.timeLeft--;
        updateHud();
        if (st.timeLeft <= 0) finish();
      }, 1000);
    }
    nextQuestion();
  }

  function weightOf(p) {
    const info = GQ.Store.positionInfo(p.string, p.fret);
    if (!info || !info.recent || !info.recent.length) return 2;
    const acc = info.recent.reduce((a, b) => a + b, 0) / info.recent.length;
    return 1 + 3 * (1 - acc);
  }
  function pickPosition() {
    const cands = st.pool.filter((p) => !st.last || p.string !== st.last.string || p.fret !== st.last.fret);
    const weights = cands.map(weightOf);
    let r = Math.random() * weights.reduce((a, b) => a + b, 0);
    for (let i = 0; i < cands.length; i++) { r -= weights[i]; if (r <= 0) return cands[i]; }
    return cands[cands.length - 1];
  }

  function nextQuestion() {
    clearTimers();
    if (st.mode === 'blitz' && st.timeLeft > 0) {
      blitzTimer = setInterval(() => { st.timeLeft--; updateHud(); if (st.timeLeft <= 0) finish(); }, 1000);
    }
    if (st.q >= st.total) { finish(); return; }
    st.q++;
    st.locked = false; st.hint = false;
    const pos = pickPosition();
    st.last = pos;
    const midi = T.midiAt(pos.string, pos.fret), pc = T.mod(midi, 12);
    let spelled;
    if (T.isNaturalPc(pc)) spelled = T.spellPc(pc);
    else if (st.game === 'staff') spelled = T.spellPc(pc, Math.random() < 0.5 ? 'sharp' : 'flat');
    else spelled = T.spellPc(pc, GQ.Store.settings().accidentals === 'flat' ? 'flat' : 'sharp');
    st.cur = { pos, midi, pc, spelled };
    document.getElementById('qNext').hidden = true;
    document.getElementById('qHint').disabled = false;
    setFeedback('', '');
    fb.setMarks([]);
    fb.highlightString(st.game === 'hunt' ? pos.string : null);
    renderQuestion();
    renderPad();
    updateHud();
  }

  function renderQuestion() {
    const card = document.getElementById('qCard');
    clear(card);
    if (scoreView) { scoreView.destroy(); scoreView = null; }
    const c = st.cur;
    if (st.game === 'tab') {
      card.appendChild(h('div', { class: 'q-prompt' }, 'Which note is this?'));
      const row = h('div', { class: 'q-row' }, bigTab(c.pos.string, c.pos.fret));
      if (st.staffToo) row.appendChild(staffBox(c));
      card.appendChild(row);
    } else if (st.game === 'staff') {
      card.appendChild(h('div', { class: 'q-prompt' }, 'Find this note on the fretboard'));
      card.appendChild(h('div', { class: 'q-row' }, staffBox(c, true)));
      card.appendChild(h('div', { class: 'q-sub', id: 'qReveal' }, 'Any place that plays exactly this sound counts.'));
    } else {
      const label = T.noteLabel(c.spelled, nm());
      const col = UI.spelledColor(c.spelled);
      card.appendChild(h('div', { class: 'q-prompt' }, 'Find'));
      card.appendChild(h('div', { class: 'q-row hunt' },
        h('span', { class: 'big-note', style: { background: col, color: UI.inkOn(col) } }, label),
        h('span', { class: 'hunt-on' }, 'on string ' + c.pos.string + ' (' + T.OPEN_NAMES[c.pos.string].toUpperCase() + ')')));
      card.appendChild(h('div', { class: 'q-sub' }, 'The string is highlighted on the fretboard below.'));
    }
  }

  function bigTab(string, fret) {
    const W = 340, top = 22, gap = 22;
    let svg = '<svg class="big-tab" viewBox="0 0 ' + W + ' ' + (top * 2 + gap * 5) + '">';
    for (let s = 1; s <= 6; s++) {
      const y = top + (s - 1) * gap;
      svg += '<text x="14" y="' + (y + 5) + '" class="bt-lbl" text-anchor="middle">' + T.OPEN_NAMES[s] + '</text>';
      svg += '<line x1="30" x2="' + (W - 10) + '" y1="' + y + '" y2="' + y + '" class="bt-line' + (s === string ? ' on' : '') + '"/>';
    }
    svg += '<text x="52" y="' + (top + gap * 1.5 + 2) + '" class="bt-clef" text-anchor="middle">T</text>';
    svg += '<text x="52" y="' + (top + gap * 2.6 + 2) + '" class="bt-clef" text-anchor="middle">A</text>';
    svg += '<text x="52" y="' + (top + gap * 3.7 + 2) + '" class="bt-clef" text-anchor="middle">B</text>';
    const y = top + (string - 1) * gap, x = 200, w = 16 * String(fret).length + 12;
    svg += '<rect x="' + (x - w / 2) + '" y="' + (y - 14) + '" width="' + w + '" height="28" rx="6" class="bt-bg"/>';
    svg += '<text x="' + x + '" y="' + (y + 9) + '" class="bt-num" text-anchor="middle">' + fret + '</text>';
    svg += '</svg>';
    return h('div', { class: 'big-tab-wrap', html: svg });
  }

  function staffBox(c, big) {
    const host = h('div', { class: 'mini-score q-staff' + (big ? ' big' : '') });
    const score = GQ.Exercises.finalize([{ dur: 48, tuplet: 0, notes: [{ string: c.pos.string, fret: c.pos.fret, midi: c.midi, spelled: c.spelled }] }],
      { keySig: T.keySignature({ l: 0, a: 0 }, 'major'), tempo: 60, title: '' });
    // render after it is in the document so it can measure its width
    later(() => {
      scoreView = new GQ.Notation.ScoreView(host, { showStaff: true, showTab: false, showNames: false, colors: false, minWidth: 200, autoScroll: false });
      scoreView.setScore(score);
    }, 0);
    return host;
  }

  function renderPad() {
    const pad = document.getElementById('qPad');
    clear(pad);
    if (st.game !== 'tab') { pad.hidden = true; return; }
    pad.hidden = false;
    const pcs = st.level.acc ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] : [0, 2, 4, 5, 7, 9, 11];
    pcs.forEach((pc) => {
      const col = UI.pcColor(pc);
      const label = T.pcLabel(pc, nm(), 'both'); // black-key notes show both names, e.g. C♯/D♭
      pad.appendChild(h('button', {
        type: 'button', class: 'pad-btn' + (T.isNaturalPc(pc) ? '' : ' sharp'), dataset: { pc: String(pc) },
        style: { '--c': col, '--on': UI.inkOn(col) }, onclick: () => answerPc(pc),
      }, label));
    });
  }

  /* ---------------- answers ---------------- */
  function answerPc(pc) {
    if (st.locked) return;
    const btn = document.querySelector('.pad-btn[data-pc="' + pc + '"]');
    result(pc === st.cur.pc, { btn, pc });
  }

  function answerPosition(s, f) {
    if (st.locked || st.game === 'tab') return;
    const c = st.cur;
    if (st.game === 'hunt') {
      if (s !== c.pos.string) { UI.toast('Use string ' + c.pos.string + ' (' + T.OPEN_NAMES[c.pos.string].toUpperCase() + ') - the highlighted one.'); return; }
      result(T.mod(T.midiAt(s, f), 12) === c.pc, { s, f });
    } else {
      result(T.midiAt(s, f) === c.midi, { s, f });
    }
  }

  function result(correct, ans) {
    st.locked = true;
    clearInterval(blitzTimer);
    const c = st.cur;
    st.answered++;
    GQ.Store.recordAnswer(c.pos.string, c.pos.fret, correct);
    const nmode = nm();
    const name = T.noteLabel(c.spelled, nmode);
    document.getElementById('qHint').disabled = true;
    if (correct) {
      st.correct++; st.streak++;
      st.bestStreak = Math.max(st.bestStreak, st.streak);
      GQ.Store.recordStreak(st.streak);
      const pts = st.hint ? 5 : 10 + (st.streak >= 3 ? 5 : 0);
      st.score += pts;
      if (ans.btn) ans.btn.classList.add('good');
      const s = ans.s || c.pos.string, f = ans.f !== undefined ? ans.f : c.pos.fret;
      fb.setMarks([GQ.noteMark(s, f, { spelled: c.spelled, kind: 'root', cls: 'pop' })]);
      fb.flash(s, f, 'good');
      GQ.Audio.pluck(T.midiAt(s, f), 0, { duration: 1.2 });
      const cheers = ['Great!', 'Yes!', 'Correct!', 'Nice one!', 'Super!', 'You got it!'];
      setFeedback(UI.pick(cheers) + ' ' + explainCorrect(c, s, f) + '  +' + pts + (st.streak >= 3 ? ' (streak bonus!)' : ''), 'good');
      updateHud();
      later(nextQuestion, st.mode === 'blitz' ? 650 : 1300);
    } else {
      st.streak = 0;
      const key = c.pos.string + ':' + c.pos.fret;
      st.misses[key] = (st.misses[key] || 0) + 1;
      if (ans.btn) ans.btn.classList.add('bad');
      const right = document.querySelector('.pad-btn[data-pc="' + c.pc + '"]');
      if (right) right.classList.add('good');
      const marks = [];
      if (st.game === 'staff') T.positionsOfMidi(c.midi, fb.opts.maxFret).forEach((p) => marks.push(GQ.noteMark(p.string, p.fret, { spelled: c.spelled, kind: 'root', cls: 'pop' })));
      else if (st.game === 'hunt') {
        for (let f = 0; f <= fb.opts.maxFret; f++) if (T.mod(T.midiAt(c.pos.string, f), 12) === c.pc) marks.push(GQ.noteMark(c.pos.string, f, { spelled: c.spelled, kind: 'root', cls: 'pop' }));
      } else marks.push(GQ.noteMark(c.pos.string, c.pos.fret, { spelled: c.spelled, kind: 'root', cls: 'pop' }));
      if (ans.s) { marks.push(Object.assign(GQ.noteMark(ans.s, ans.f), { kind: 'ghost', cls: 'wrong' })); fb.flash(ans.s, ans.f, 'bad'); }
      fb.setMarks(marks);
      GQ.Audio.pluck(c.midi, GQ.Audio.now() + 0.15, { duration: 1.2 });
      setFeedback(explainWrong(c, ans), 'bad');
      updateHud();
      if (st.mode === 'blitz') later(nextQuestion, 1600);
      else document.getElementById('qNext').hidden = false;
    }
  }

  function ladderText(string, fret) {
    const open = T.TUNING[string];
    const pref = GQ.Store.settings().accidentals === 'flat' ? 'flat' : 'sharp';
    if (fret === 0) return '0 means the string is played open (no finger), and string ' + string + ' open is ' + T.OPEN_NAMES[string].toUpperCase() + '.';
    if (fret <= 7) {
      const steps = [];
      for (let f = 1; f <= fret; f++) steps.push(T.pcLabel(T.mod(open + f, 12), nm(), pref));
      return 'String ' + string + ' is ' + T.OPEN_NAMES[string].toUpperCase() + '. Count up ' + fret + (fret === 1 ? ' fret: ' : ' frets: ') + steps.join(', ') + '.';
    }
    const steps = [];
    if (fret <= 12) for (let f = 11; f >= fret; f--) steps.push(T.pcLabel(T.mod(open + f, 12), nm(), pref));
    else for (let f = 13; f <= fret; f++) steps.push(T.pcLabel(T.mod(open + f, 12), nm(), pref));
    return 'Fret 12 is ' + T.OPEN_NAMES[string].toUpperCase() + ' again.' + (steps.length ? ' Then ' + (fret < 12 ? 'back' : 'up') + ': ' + steps.join(', ') + '.' : '');
  }

  function explainCorrect(c, s, f) {
    if (st.game === 'tab') return 'Fret ' + c.pos.fret + ' on string ' + c.pos.string + ' is ' + T.noteLabel(c.spelled, nm()) + '.';
    return T.noteLabel(c.spelled, nm()) + ' = string ' + s + ', fret ' + f + '.';
  }
  function explainWrong(c, ans) {
    const name = T.noteLabel(c.spelled, nm());
    if (st.game === 'tab') {
      const picked = T.pcLabel(ans.pc, nm(), 'both');
      return 'Not ' + picked + '. ' + ladderText(c.pos.string, c.pos.fret) + ' So it is ' + name + '.';
    }
    if (st.game === 'staff') {
      const got = T.midiAt(ans.s, ans.f);
      if (T.mod(got, 12) === c.pc) return 'Right letter, wrong octave! ' + name + ' on the staff is a ' + (got > c.midi ? 'lower' : 'higher') + ' ' + name + '. The marked places are correct.';
      return 'That was ' + T.pcLabel(T.mod(got, 12), nm(), 'both') + '. This note is ' + name + ' - it lives at the marked places.';
    }
    return 'That was ' + T.pcLabel(T.mod(T.midiAt(ans.s, ans.f), 12), nm(), 'both') + '. ' + name + ' on string ' + c.pos.string + ' is at the marked fret.';
  }

  function useHint() {
    if (st.locked || st.hint) return;
    st.hint = true;
    const c = st.cur;
    if (st.game === 'tab') {
      const marks = [];
      const from = c.pos.fret <= 7 ? 0 : 12;
      const lo = Math.min(from, c.pos.fret), hi = Math.max(from, c.pos.fret);
      for (let f = lo; f <= hi; f++) {
        if (f === c.pos.fret) marks.push({ string: c.pos.string, fret: f, label: '?', color: '#1e2230', kind: 'target' });
        else marks.push(Object.assign(GQ.noteMark(c.pos.string, f), { cls: 'soft' }));
      }
      fb.setMarks(marks);
      fb.highlightString(c.pos.string);
      setFeedback('Hint: count fret by fret from ' + (from === 0 ? 'the open string' : 'fret 12') + '. (Hints give 5 points.)', 'hint');
    } else if (st.game === 'staff') {
      const rev = document.getElementById('qReveal');
      if (rev) rev.textContent = 'Hint: this note is ' + T.noteLabel(c.spelled, nm()) + '. (Hints give 5 points.)';
    } else {
      const marks = [];
      for (let f = 0; f <= fb.opts.maxFret; f++) {
        const pc = T.mod(T.midiAt(c.pos.string, f), 12);
        if (T.isNaturalPc(pc) && pc !== c.pc) marks.push(Object.assign(GQ.noteMark(c.pos.string, f), { cls: 'soft' }));
      }
      fb.setMarks(marks);
      setFeedback('Hint: the other natural notes on this string are shown. Your note is in one of the gaps or empty frets. (Hints give 5 points.)', 'hint');
    }
  }

  function setFeedback(text, kind) {
    const el = document.getElementById('qFeedback');
    if (!el) return;
    el.textContent = text;
    el.className = 'feedback ' + (kind || '');
  }

  function updateHud() {
    const prog = document.getElementById('qProgress');
    if (!prog) return;
    clear(prog);
    if (st.mode === 'blitz') {
      prog.appendChild(h('div', { class: 'timer' + (st.timeLeft <= 10 ? ' low' : '') }, st.timeLeft + 's'));
    } else {
      const bar = h('div', { class: 'qbar' });
      for (let i = 0; i < st.total; i++) bar.appendChild(h('span', { class: i < st.answered ? 'done' : (i === st.q - 1 ? 'now' : '') }));
      prog.appendChild(bar);
      prog.appendChild(h('span', { class: 'small muted' }, 'Question ' + Math.min(st.q, st.total) + ' of ' + st.total));
    }
    document.getElementById('qScore').textContent = String(st.score);
    document.getElementById('qStreak').textContent = String(st.streak);
  }

  function finish() {
    clearTimers();
    if (!st) return;
    const acc = st.answered ? st.correct / st.answered : 0;
    let stars;
    if (st.mode === 'blitz') stars = st.correct >= 20 ? 3 : st.correct >= 12 ? 2 : st.correct >= 6 ? 1 : 0;
    else stars = acc >= 0.9 ? 3 : acc >= 0.7 ? 2 : acc >= 0.5 ? 1 : 0;
    GQ.Store.recordLevel(st.game, st.level.id, stars, st.score);
    GQ.PracticeClock.stop('quest');
    if (keyHandler) document.removeEventListener('keydown', keyHandler);
    keyHandler = null;
    clear(root);
    const missList = Object.keys(st.misses).sort((a, b) => st.misses[b] - st.misses[a]).slice(0, 4);
    const msg = stars === 3 ? 'Amazing - three stars!' : stars === 2 ? 'Well done!' : stars === 1 ? 'Good start - keep going!' : 'Practice makes perfect. Try again!';
    const card = h('div', { class: 'card result' },
      h('div', { class: 'big-stars' }, [0, 1, 2].map((k) => h('span', { class: 'star' + (k < stars ? ' on' : ''), style: { animationDelay: (k * 0.25) + 's' } }, icon('star')))),
      h('h2', null, msg),
      h('div', { class: 'result-stats' },
        stat('Score', st.score), stat('Correct', st.correct + ' / ' + st.answered), stat('Best streak', st.bestStreak)),
      missList.length ? h('div', { class: 'miss-list' }, h('h3', null, 'Notes to practise'),
        h('div', { class: 'chips' }, missList.map((k) => {
          const [s, f] = k.split(':').map(Number);
          const pc = T.mod(T.midiAt(s, f), 12);
          return h('span', { class: 'chip' }, UI.noteBadge(pc, { size: 'sm' }), ' string ' + s + ', fret ' + f);
        }))) : null,
      h('div', { class: 'result-actions' },
        h('button', { type: 'button', class: 'btn primary', onclick: () => startGame(st.levelIdx) }, 'Play again'),
        st.levelIdx < LEVELS.length - 1 ? h('button', { type: 'button', class: 'btn', onclick: () => startGame(st.levelIdx + 1) }, 'Next level') : null,
        h('button', { type: 'button', class: 'btn ghost', onclick: showLobby }, 'All levels')));
    root.appendChild(card);
    if (stars) GQ.Audio.chime(true);
  }
  function stat(label, value) { return h('div', { class: 'stat' }, h('span', { class: 'stat-v' }, String(value)), h('span', { class: 'stat-l' }, label)); }

  function onSettings() {
    if (!st || !document.getElementById('qCard')) { showLobby(); return; }
    renderQuestion(); renderPad();
  }

  GQ.Views.quest = { mount, unmount, onSettings, LEVELS, GAMES };
})(window.GQ = window.GQ || {});
