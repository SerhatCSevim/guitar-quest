/* Guitar Quest - small DOM helpers and shared visual constants. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory;

  // One colour per note letter (C..B), used on the fretboard, staff and tab.
  const LETTER_COLORS = ['#E53935', '#F57C00', '#E8B100', '#43A047', '#0097A7', '#5E35B1', '#D81B60'];
  const ACC_COLOR = '#546E7A';

  function letterColor(l) { return LETTER_COLORS[l]; }
  function pcColor(pc) {
    return T.isNaturalPc(pc) ? LETTER_COLORS[T.spellPc(pc).l] : ACC_COLOR;
  }
  function spelledColor(n) { return n.a === 0 ? LETTER_COLORS[n.l] : ACC_COLOR; }
  function inkOn(color) { return color === LETTER_COLORS[2] ? '#2a2100' : '#fff'; }

  function h(tag, attrs) {
    const el = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach((k) => {
        const v = attrs[k];
        if (v === null || v === undefined || v === false) return;
        if (k === 'class') el.className = v;
        else if (k === 'style' && typeof v === 'object') {
          // custom properties (--name) only work through setProperty
          Object.keys(v).forEach((p) => { if (p.slice(0, 2) === '--') el.style.setProperty(p, v[p]); else el.style[p] = v[p]; });
        }
        else if (k === 'html') el.innerHTML = v;
        else if (k === 'text') el.textContent = v;
        else if (k.slice(0, 2) === 'on' && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
        else if (k === 'dataset') Object.assign(el.dataset, v);
        else if (v === true) el.setAttribute(k, '');
        else el.setAttribute(k, v);
      });
    }
    for (let i = 2; i < arguments.length; i++) append(el, arguments[i]);
    return el;
  }
  function append(el, child) {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) { child.forEach((c) => append(el, c)); return; }
    el.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); return el; }

  // Segmented control: options [{value, label, title?}]
  function segmented(options, value, onChange, cls) {
    const wrap = h('div', { class: 'seg ' + (cls || ''), role: 'radiogroup' });
    const set = (v) => {
      value = v;
      Array.from(wrap.children).forEach((b) => {
        b.classList.toggle('on', b.dataset.value === String(v));
        b.setAttribute('aria-checked', b.dataset.value === String(v) ? 'true' : 'false');
      });
    };
    options.forEach((o) => {
      wrap.appendChild(h('button', {
        type: 'button', role: 'radio', class: 'seg-btn', dataset: { value: String(o.value) }, title: o.title || null,
        onclick: () => { set(o.value); onChange(o.value); },
      }, o.label));
    });
    set(value);
    wrap.setValue = set;
    return wrap;
  }

  function select(options, value, onChange, attrs) {
    const el = h('select', Object.assign({ class: 'sel' }, attrs || {}));
    options.forEach((o) => {
      const opt = h('option', { value: String(o.value) }, o.label);
      if (String(o.value) === String(value)) opt.selected = true;
      el.appendChild(opt);
    });
    el.addEventListener('change', () => onChange(el.value));
    return el;
  }

  function field(label, control) {
    return h('label', { class: 'field' }, h('span', { class: 'field-label' }, label), control);
  }

  let toastTimer = null;
  function toast(msg, kind) {
    let el = document.getElementById('toast');
    if (!el) { el = h('div', { id: 'toast' }); document.body.appendChild(el); }
    el.textContent = msg;
    el.className = 'show ' + (kind || '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.className = ''; }, 2200);
  }

  function shuffle(arr) {
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); const t = a[i]; a[i] = a[j]; a[j] = t; }
    return a;
  }
  function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

  const ICONS = {
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5v13l11-6.5z" fill="currentColor"/></svg>',
    pause: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h4v14H7zM13 5h4v14h-4z" fill="currentColor"/></svg>',
    stop: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6.5" y="6.5" width="11" height="11" rx="1.5" fill="currentColor"/></svg>',
    loop: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7h9.5l-2-2M17 17H7.5l2 2M5 13V9.5A2.5 2.5 0 0 1 7.5 7M19 11v3.5a2.5 2.5 0 0 1-2.5 2.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    metro: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9.5 3h5l4 18h-13zM12 15l5-9" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/><path d="M7.6 17h8.8" stroke="currentColor" stroke-width="1.8"/></svg>',
    speaker: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    gear: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M19.4 13.5l1.6 1.2-1.8 3.1-1.9-.7a7 7 0 0 1-1.8 1l-.3 2h-3.6l-.3-2a7 7 0 0 1-1.8-1l-1.9.7L5.8 14.7l1.6-1.2a7 7 0 0 1 0-2.1L5.8 10.2 7.6 7l1.9.7a7 7 0 0 1 1.8-1l.3-2h3.6l.3 2a7 7 0 0 1 1.8 1l1.9-.7 1.8 3.1-1.6 1.2a7 7 0 0 1 0 2.1z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
    star: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3.2l2.6 5.6 6.1.7-4.5 4.2 1.2 6-5.4-3.1-5.4 3.1 1.2-6L3.3 9.5l6.1-.7z" fill="currentColor"/></svg>',
    flame: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5c.5 3.2 4.8 5.6 4.8 10.4a4.8 4.8 0 0 1-9.6 0c0-2.2 1.1-3.6 2.2-4.6-.1 1.6.6 2.8 1.7 3.2-.6-3.7.3-6.6.9-9z" fill="currentColor"/></svg>',
    bulb: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 18h6M10 21h4M12 3a6 6 0 0 0-3.6 10.8c.7.6 1.1 1.4 1.1 2.2h5c0-.8.4-1.6 1.1-2.2A6 6 0 0 0 12 3z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14.5 6l-6 6 6 6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    strum: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4l12 16M9 4l10 13" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M5 9c2 0 3 1 3 3s-1 3-3 3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  };
  function icon(name) { return h('span', { class: 'ic', html: ICONS[name] }); }

  function noteBadge(spelledOrPc, opts) {
    opts = opts || {};
    const settings = GQ.Store.settings();
    let label, color;
    if (typeof spelledOrPc === 'number') {
      label = T.pcLabel(spelledOrPc, settings.naming, settings.accidentals);
      color = pcColor(spelledOrPc);
    } else {
      label = T.noteLabel(spelledOrPc, settings.naming);
      color = spelledColor(spelledOrPc);
    }
    return h('span', { class: 'note-badge ' + (opts.size || ''), style: { background: color, color: inkOn(color) } }, label);
  }

  GQ.UI = {
    LETTER_COLORS, ACC_COLOR, letterColor, pcColor, spelledColor, inkOn,
    h, append, clear, segmented, select, field, toast, shuffle, pick, icon, ICONS, noteBadge,
  };
})(window.GQ = window.GQ || {});
