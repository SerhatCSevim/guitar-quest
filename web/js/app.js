/* Guitar Quest - app shell: routing between views, settings panel, practice clock. */
(function (GQ) {
  'use strict';
  const { h, clear, segmented, icon } = GQ.UI;
  GQ.Store.load();

  let current = null;
  let pending = null;

  function go(name, params) {
    pending = params || null;
    if (location.hash === '#' + name) route();
    else location.hash = name;
  }

  function route() {
    const name = (location.hash.slice(1) || 'explore').split('?')[0];
    const viewName = GQ.Views[name] ? name : 'explore';
    if (current && current.unmount) current.unmount();
    GQ.PracticeClock.stopAll();
    const main = document.getElementById('view');
    clear(main);
    main.scrollTop = 0;
    window.scrollTo(0, 0);
    current = GQ.Views[viewName];
    document.querySelectorAll('#tabs a').forEach((a) => a.classList.toggle('on', a.dataset.view === viewName));
    const params = pending; pending = null;
    current.mount(main, params);
  }

  /* ---- practice clock: counts seconds while something is actively practised ---- */
  GQ.PracticeClock = (function () {
    const active = new Set();
    let last = 0, acc = 0, timer = null;
    function tick() {
      const t = Date.now();
      if (active.size && last) acc += (t - last) / 1000;
      last = t;
      if (acc >= 15) { GQ.Store.addPractice(acc); acc = 0; }
    }
    return {
      start(who) { tick(); active.add(who); last = Date.now(); if (!timer) timer = setInterval(tick, 5000); },
      stop(who) { tick(); active.delete(who); if (!active.size) { GQ.Store.addPractice(acc); acc = 0; clearInterval(timer); timer = null; } },
      stopAll() { tick(); active.clear(); GQ.Store.addPractice(acc); acc = 0; clearInterval(timer); timer = null; },
    };
  })();

  /* ---- settings ---- */
  function buildSettings() {
    const panel = document.getElementById('settingsPanel');
    clear(panel);
    const st = GQ.Store.settings();
    panel.appendChild(h('h3', null, 'Settings'));
    panel.appendChild(h('div', { class: 'set-row' }, h('span', null, 'Note names'),
      segmented([{ value: 'letters', label: 'C D E' }, { value: 'solfege', label: 'Do Re Mi' }, { value: 'both', label: 'Both' }], st.naming, (v) => GQ.Store.setSetting('naming', v))));
    panel.appendChild(h('div', { class: 'set-row' }, h('span', null, 'Black-key notes'),
      segmented([{ value: 'sharp', label: 'C♯' }, { value: 'flat', label: 'D♭' }, { value: 'both', label: 'C♯/D♭' }], st.accidentals, (v) => GQ.Store.setSetting('accidentals', v))));
    panel.appendChild(h('div', { class: 'set-row' }, h('span', null, 'Note colours'),
      segmented([{ value: 'on', label: 'On' }, { value: 'off', label: 'Off' }], st.colors ? 'on' : 'off', (v) => GQ.Store.setSetting('colors', v === 'on'))));
    const vol = h('input', { type: 'range', min: '0', max: '1', step: '0.05', value: String(st.volume) });
    vol.addEventListener('input', () => { GQ.Store.setSetting('volume', Number(vol.value)); GQ.Audio.setVolume(Number(vol.value)); });
    panel.appendChild(h('div', { class: 'set-row' }, h('span', null, 'Volume'), vol));
    panel.appendChild(h('p', { class: 'set-note' }, 'Progress is saved in this browser on this computer only.'));
  }

  function init() {
    const btn = document.getElementById('settingsBtn');
    btn.appendChild(icon('gear'));
    const panel = document.getElementById('settingsPanel');
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (panel.hidden) buildSettings();
      panel.hidden = !panel.hidden;
    });
    document.addEventListener('click', (e) => {
      if (!panel.hidden && !panel.contains(e.target) && e.target !== btn) panel.hidden = true;
    });
    document.addEventListener('gq-settings', () => { if (current && current.onSettings) current.onSettings(); });
    // Browsers only allow sound after the first click or key press.
    const unlock = () => { GQ.Audio.ensure(); window.removeEventListener('pointerdown', unlock); window.removeEventListener('keydown', unlock); };
    window.addEventListener('pointerdown', unlock);
    window.addEventListener('keydown', unlock);
    window.addEventListener('hashchange', route);
    window.addEventListener('beforeunload', () => { GQ.PracticeClock.stopAll(); GQ.Store.flush(); });
    route();
  }

  GQ.App = { go };
  init();
})(window.GQ = window.GQ || {});
