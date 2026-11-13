/* Guitar Quest - My Progress: practice time, accuracy, fretboard mastery map and level stars. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory, UI = GQ.UI;
  const { h, clear, icon } = UI;
  GQ.Views = GQ.Views || {};
  let root;

  function dayKey(d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }

  function mount(el) {
    root = h('section', { class: 'progress' });
    el.appendChild(root);
    render();
  }
  function unmount() {}

  function render() {
    clear(root);
    const data = GQ.Store.get();
    const q = data.quest, p = data.practice;
    root.appendChild(h('div', { class: 'view-head' }, h('h1', null, 'My Progress'),
      h('p', { class: 'lead' }, 'Little and often wins: 15 minutes a day is better than one long session a week.')));
    // day streak
    let streak = 0;
    const d = new Date();
    if (!(p[dayKey(d)] >= 60)) d.setDate(d.getDate() - 1); // today not practised yet: count up to yesterday
    while (p[dayKey(d)] >= 60) { streak++; d.setDate(d.getDate() - 1); }
    const todayMin = Math.round((p[GQ.Store.today()] || 0) / 60);
    const weekSec = (() => { let s = 0; const x = new Date(); for (let i = 0; i < 7; i++) { s += p[dayKey(x)] || 0; x.setDate(x.getDate() - 1); } return s; })();
    const acc = q.answered ? Math.round(100 * q.correct / q.answered) : 0;
    root.appendChild(h('div', { class: 'stat-grid' },
      bigStat(todayMin + ' min', 'practised today'),
      bigStat(Math.round(weekSec / 60) + ' min', 'this week'),
      bigStat(streak + (streak === 1 ? ' day' : ' days'), 'practice streak', 'flame'),
      bigStat(String(q.answered), 'notes answered'),
      bigStat(acc + '%', 'correct'),
      bigStat(String(q.bestStreak), 'best answer streak', 'star')));

    // last 14 days
    const chart = h('div', { class: 'card' }, h('h3', null, 'Practice minutes - last 14 days'));
    const bars = h('div', { class: 'day-bars' });
    const days = [];
    const x = new Date();
    for (let i = 13; i >= 0; i--) { const t = new Date(x); t.setDate(x.getDate() - i); days.push(t); }
    const mins = days.map((t) => (p[dayKey(t)] || 0) / 60);
    const max = Math.max(15, Math.max.apply(null, mins));
    days.forEach((t, i) => {
      const m = mins[i];
      bars.appendChild(h('div', { class: 'day-bar', title: Math.round(m) + ' min' },
        h('span', { class: 'db-val' }, m >= 1 ? String(Math.round(m)) : ''),
        h('span', { class: 'db-fill' + (m >= 15 ? ' goal' : ''), style: { height: Math.max(2, (m / max) * 100) + '%' } }),
        h('span', { class: 'db-day' }, ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'][t.getDay()])));
    });
    chart.appendChild(bars);
    chart.appendChild(h('p', { class: 'small muted' }, 'Green bars reached the 15-minute goal. Time counts while a Note Quest round, the Studio or the Jam is running.'));
    root.appendChild(chart);

    // fretboard mastery map
    const mapCard = h('div', { class: 'card' }, h('h3', null, 'Fretboard map'),
      h('p', { class: 'small muted' }, 'Every Note Quest answer colours its fret: green = you know it, orange = getting there, red = needs practice, grey = not tried yet.'));
    const host = h('div');
    mapCard.appendChild(host);
    root.appendChild(mapCard);
    const fb = new GQ.Fretboard(host, { maxFret: 12, interactive: false, compact: true });
    const marks = [];
    for (let s = 1; s <= 6; s++) for (let f = 0; f <= 12; f++) {
      const info = q.positions[s + ':' + f];
      const pc = T.mod(T.midiAt(s, f), 12);
      const label = T.pcLabel(pc, 'letters', 'sharp');
      if (!info || !info.seen) { marks.push({ string: s, fret: f, label: '', color: 'rgba(255,255,255,.18)', kind: 'note' }); continue; }
      const r = info.recent && info.recent.length ? info.recent.reduce((a, b) => a + b, 0) / info.recent.length : info.correct / info.seen;
      const color = r >= 0.8 ? '#2E9E5B' : r >= 0.5 ? '#F29B30' : '#D64545';
      marks.push({ string: s, fret: f, label, color, textColor: '#fff', kind: 'note' });
    }
    fb.setMarks(marks);

    // level stars
    const lv = h('div', { class: 'card' }, h('h3', null, 'Note Quest stars'));
    const table = h('table', { class: 'stars-table' });
    const games = GQ.Views.quest.GAMES, levels = GQ.Views.quest.LEVELS;
    table.appendChild(h('tr', null, h('th', null, 'Level'), games.map((g) => h('th', null, g.name))));
    let total = 0;
    levels.forEach((l) => {
      table.appendChild(h('tr', null, h('td', null, l.name), games.map((g) => {
        const info = GQ.Store.levelInfo(g.id, l.id);
        total += info.stars;
        return h('td', null, h('span', { class: 'stars' }, [0, 1, 2].map((k) => h('span', { class: 'star' + (k < info.stars ? ' on' : '') }, icon('star')))));
      })));
    });
    lv.appendChild(h('p', { class: 'small' }, total + ' of ' + levels.length * games.length * 3 + ' stars collected.'));
    lv.appendChild(table);
    root.appendChild(lv);

    const th = data.theory;
    root.appendChild(h('div', { class: 'card' }, h('h3', null, 'Theory games'),
      h('p', null, th.answered ? th.correct + ' of ' + th.answered + ' theory questions correct (' + Math.round(100 * th.correct / th.answered) + '%).' : 'No theory games played yet - try them in Chords & Harmony.')));

    root.appendChild(h('div', { class: 'danger-zone' },
      h('button', { type: 'button', class: 'btn ghost small', onclick: () => {
        if (window.confirm('Delete all progress, stars and practice time on this computer?')) { GQ.Store.reset(); GQ.Store.load(); render(); }
      } }, 'Reset all progress')));
  }

  function bigStat(value, label, ic) {
    return h('div', { class: 'card big-stat' }, ic ? h('span', { class: 'bs-icon ' + ic }, icon(ic)) : null, h('span', { class: 'bs-v' }, value), h('span', { class: 'bs-l' }, label));
  }

  GQ.Views.progress = { mount, unmount, onSettings: render };
})(window.GQ = window.GQ || {});
