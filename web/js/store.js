/* Guitar Quest - progress and settings, kept in this browser's localStorage. */
(function (GQ) {
  'use strict';
  const KEY = 'guitarQuest.v1';
  const DEFAULTS = {
    settings: { naming: 'letters', accidentals: 'sharp', colors: true, volume: 0.8 },
    quest: { levels: {}, positions: {}, answered: 0, correct: 0, bestStreak: 0 },
    theory: { answered: 0, correct: 0, best: {} },
    practice: {}, // 'YYYY-MM-DD' -> seconds
  };
  let data = null;
  let saveTimer = null;

  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function merge(base, extra) {
    Object.keys(extra || {}).forEach((k) => {
      if (base[k] && typeof base[k] === 'object' && !Array.isArray(base[k]) && extra[k] && typeof extra[k] === 'object') merge(base[k], extra[k]);
      else base[k] = extra[k];
    });
    return base;
  }
  function load() {
    data = clone(DEFAULTS);
    try {
      const raw = window.localStorage.getItem(KEY);
      if (raw) merge(data, JSON.parse(raw));
    } catch (e) { /* storage unavailable: run without saving */ }
    return data;
  }
  function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      try { window.localStorage.setItem(KEY, JSON.stringify(data)); } catch (e) { /* ignore */ }
    }, 250);
  }
  function flush() {
    clearTimeout(saveTimer);
    try { window.localStorage.setItem(KEY, JSON.stringify(data)); } catch (e) { /* ignore */ }
  }
  function get() { return data || load(); }
  function settings() { return get().settings; }
  function setSetting(k, v) { get().settings[k] = v; save(); document.dispatchEvent(new CustomEvent('gq-settings', { detail: { key: k, value: v } })); }

  function today() {
    const d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  function recordAnswer(string, fret, correct) {
    const q = get().quest;
    const k = string + ':' + fret;
    const p = q.positions[k] || (q.positions[k] = { seen: 0, correct: 0, recent: [] });
    p.seen++;
    if (correct) p.correct++;
    p.recent = (p.recent || []).concat([correct ? 1 : 0]).slice(-5);
    q.answered++;
    if (correct) q.correct++;
    save();
  }
  function recordStreak(n) { const q = get().quest; if (n > q.bestStreak) { q.bestStreak = n; save(); } }
  function recordLevel(game, level, stars, score) {
    const q = get().quest;
    const k = game + ':' + level;
    const cur = q.levels[k] || { stars: 0, best: 0, plays: 0 };
    cur.stars = Math.max(cur.stars, stars);
    cur.best = Math.max(cur.best, score);
    cur.plays++;
    q.levels[k] = cur;
    save();
  }
  function levelInfo(game, level) { return get().quest.levels[game + ':' + level] || { stars: 0, best: 0, plays: 0 }; }
  function positionInfo(string, fret) { return get().quest.positions[string + ':' + fret] || null; }

  function recordTheory(game, correct) {
    const t = get().theory;
    t.answered++;
    if (correct) t.correct++;
    save();
  }
  function recordTheoryBest(game, streak) {
    const t = get().theory;
    if (!t.best[game] || streak > t.best[game]) { t.best[game] = streak; save(); }
  }

  function addPractice(seconds) {
    if (!(seconds > 0)) return;
    const p = get().practice;
    const d = today();
    p[d] = Math.round((p[d] || 0) + seconds);
    save();
  }

  function reset() {
    data = clone(DEFAULTS);
    data.settings = Object.assign({}, data.settings);
    try { window.localStorage.removeItem(KEY); } catch (e) { /* ignore */ }
  }

  GQ.Store = { load, save, flush, get, settings, setSetting, today, recordAnswer, recordStreak, recordLevel, levelInfo, positionInfo, recordTheory, recordTheoryBest, addPractice, reset };
})(window.GQ = window.GQ || {});
