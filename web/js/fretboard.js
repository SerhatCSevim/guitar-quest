/* Guitar Quest - interactive fretboard (SVG). High e string on top, like tab. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory;
  const NS = 'http://www.w3.org/2000/svg';
  const INLAYS = [3, 5, 7, 9, 15, 17, 19, 21];

  function s(tag, attrs, parent) {
    const el = document.createElementNS(NS, tag);
    if (attrs) Object.keys(attrs).forEach((k) => el.setAttribute(k, attrs[k]));
    if (parent) parent.appendChild(el);
    return el;
  }

  class Fretboard {
    constructor(container, opts) {
      this.opts = Object.assign({ maxFret: 15, showNumbers: true, interactive: true, compact: false, onSelect: null }, opts || {});
      this.container = container;
      this.wrap = document.createElement('div');
      this.wrap.className = 'fb-wrap' + (this.opts.compact ? ' compact' : '');
      container.appendChild(this.wrap);
      this.marks = [];
      this.hlString = null;
      this.render();
    }

    setMaxFret(n) {
      n = Math.max(12, Math.min(22, n));
      if (n === this.opts.maxFret) return;
      this.opts.maxFret = n;
      this.render();
    }

    geometry() {
      const W = 1000, labelW = 26, openW = 48;
      const nutX = labelW + openW, endX = W - 14;
      const mf = this.opts.maxFret;
      const L = (endX - nutX) / (1 - Math.pow(2, -mf / 12));
      const xs = [];
      for (let n = 0; n <= mf; n++) xs.push(nutX + L * (1 - Math.pow(2, -n / 12)));
      const gap = this.opts.compact ? 21 : 26, top = 18;
      const boardBottom = top + 5 * gap + top;
      const H = boardBottom + (this.opts.showNumbers ? 22 : 4);
      return { W, H, labelW, openW, nutX, endX, xs, gap, top, boardBottom };
    }
    cx(fret) {
      const g = this.g;
      return fret === 0 ? g.nutX - g.openW / 2 : (g.xs[fret - 1] + g.xs[fret]) / 2;
    }
    cy(string) { return this.g.top + (string - 1) * this.g.gap; }

    render() {
      const g = this.g = this.geometry();
      this.wrap.innerHTML = '';
      const svg = this.svg = s('svg', { viewBox: '0 0 ' + g.W + ' ' + g.H, class: 'fretboard', role: 'img', 'aria-label': 'Guitar fretboard' });
      svg.style.minWidth = this.opts.compact ? '620px' : '760px';
      const defs = s('defs', null, svg);
      const grad = s('linearGradient', { id: 'fbWood', x1: '0', y1: '0', x2: '0', y2: '1' }, defs);
      s('stop', { offset: '0', 'stop-color': '#6b4423' }, grad);
      s('stop', { offset: '0.5', 'stop-color': '#5a371b' }, grad);
      s('stop', { offset: '1', 'stop-color': '#4a2c15' }, grad);
      const boardTop = g.top - g.gap * 0.55, boardH = 5 * g.gap + g.gap * 1.1;
      // open-string area and board
      s('rect', { x: g.labelW, y: boardTop, width: g.openW, height: boardH, rx: 6, class: 'fb-open' }, svg);
      s('rect', { x: g.nutX, y: boardTop, width: g.endX - g.nutX, height: boardH, fill: 'url(#fbWood)' }, svg);
      // inlays
      INLAYS.concat([12]).forEach((f) => {
        if (f > this.opts.maxFret) return;
        const x = this.cx(f);
        if (f === 12) {
          s('circle', { cx: x, cy: this.cy(2) + g.gap / 2, r: 5.5, class: 'fb-inlay' }, svg);
          s('circle', { cx: x, cy: this.cy(4) + g.gap / 2, r: 5.5, class: 'fb-inlay' }, svg);
        } else {
          s('circle', { cx: x, cy: this.cy(3) + g.gap / 2, r: 5.5, class: 'fb-inlay' }, svg);
        }
      });
      // frets and nut
      for (let n = 1; n <= this.opts.maxFret; n++) {
        s('rect', { x: g.xs[n] - 1.6, y: boardTop, width: 3.2, height: boardH, class: 'fb-fret' }, svg);
      }
      s('rect', { x: g.nutX - 5, y: boardTop - 1, width: 7, height: boardH + 2, rx: 1.5, class: 'fb-nut' }, svg);
      // highlighted string band (behind strings)
      this.band = s('rect', { x: g.labelW, y: 0, width: g.endX - g.labelW, height: g.gap * 0.86, rx: g.gap * 0.43, class: 'fb-band', visibility: 'hidden' }, svg);
      // strings
      this.stringEls = [];
      for (let st = 1; st <= 6; st++) {
        const y = this.cy(st);
        const w = 0.9 + (st - 1) * 0.42;
        this.stringEls[st] = s('line', { x1: g.labelW + 4, y1: y, x2: g.endX, y2: y, 'stroke-width': w, class: 'fb-string' + (st >= 4 ? ' wound' : '') }, svg);
        const lbl = s('text', { x: g.labelW / 2, y: y + 4.5, 'text-anchor': 'middle', class: 'fb-strlabel' }, svg);
        lbl.textContent = T.OPEN_NAMES[st];
      }
      if (this.opts.showNumbers) {
        for (let n = 0; n <= this.opts.maxFret; n++) {
          const t = s('text', { x: this.cx(n), y: g.H - 6, 'text-anchor': 'middle', class: 'fb-num' + (INLAYS.indexOf(n) >= 0 || n === 12 ? ' dot' : '') }, svg);
          t.textContent = n === 0 ? 'open' : n;
        }
      }
      // click cells
      this.cells = s('g', { class: 'fb-cells' }, svg);
      if (this.opts.interactive) {
        for (let st = 1; st <= 6; st++) {
          for (let f = 0; f <= this.opts.maxFret; f++) {
            const x0 = f === 0 ? g.labelW : g.xs[f - 1], x1 = f === 0 ? g.nutX - 4 : g.xs[f];
            s('rect', { x: x0, y: this.cy(st) - g.gap / 2, width: x1 - x0, height: g.gap, class: 'fb-cell', 'data-s': st, 'data-f': f }, this.cells);
          }
        }
        svg.addEventListener('click', (e) => {
          const cell = e.target.closest('[data-s]');
          if (cell && this.opts.onSelect) this.opts.onSelect(Number(cell.dataset.s), Number(cell.dataset.f), e);
        });
      }
      this.markLayer = s('g', { class: 'fb-marks' }, svg);
      this.fxLayer = s('g', { class: 'fb-fx' }, svg);
      this.wrap.appendChild(svg);
      this.drawMarks();
      this.highlightString(this.hlString);
    }

    // marks: [{string, fret, label, color, kind: 'note'|'root'|'ghost'|'ring'|'target', id}]
    setMarks(marks) { this.marks = marks || []; this.drawMarks(); }
    clearMarks() { this.setMarks([]); }

    drawMarks() {
      if (!this.markLayer) return;
      this.markLayer.innerHTML = '';
      this.marks.forEach((m) => {
        if (m.fret > this.opts.maxFret) return;
        const x = this.cx(m.fret), y = this.cy(m.string);
        const grp = s('g', { class: 'fb-mark ' + (m.kind || 'note') + (m.cls ? ' ' + m.cls : '') }, this.markLayer);
        const color = m.color || '#333';
        const r = this.opts.compact ? 9.5 : 11.5;
        if (m.kind === 'ring' || m.kind === 'target') {
          s('circle', { cx: x, cy: y, r: r + 1, fill: 'none', stroke: color, 'stroke-width': 3 }, grp);
        } else {
          if (m.kind === 'root') s('circle', { cx: x, cy: y, r: r + 3, fill: 'none', stroke: '#fff', 'stroke-width': 2.4, class: 'fb-rootring' }, grp);
          s('circle', { cx: x, cy: y, r, fill: color, class: 'fb-dot' }, grp);
        }
        if (m.label) {
          const small = String(m.label).length > 2;
          const t = s('text', {
            x, y: y + (small ? 3.4 : 4.3), 'text-anchor': 'middle', class: 'fb-mlabel',
            'font-size': small ? (String(m.label).length > 4 ? 7 : 9) : 12, fill: m.kind === 'ring' || m.kind === 'target' ? color : (m.textColor || '#fff'),
          }, grp);
          t.textContent = m.label;
        }
      });
    }

    flash(string, fret, kind) {
      const x = this.cx(fret), y = this.cy(string);
      const c = s('circle', { cx: x, cy: y, r: 13, class: 'fb-flash ' + (kind || '') }, this.fxLayer);
      setTimeout(() => c.remove(), 700);
    }

    highlightString(st) {
      this.hlString = st;
      if (!this.band) return;
      for (let i = 1; i <= 6; i++) if (this.stringEls[i]) this.stringEls[i].classList.toggle('hl', i === st);
      if (st) {
        this.band.setAttribute('y', this.cy(st) - this.g.gap * 0.43);
        this.band.setAttribute('visibility', 'visible');
      } else this.band.setAttribute('visibility', 'hidden');
    }
  }

  // Helper: a mark for a fretboard position, coloured by note.
  function noteMark(string, fret, opts) {
    opts = opts || {};
    const settings = GQ.Store.settings();
    const midi = T.midiAt(string, fret);
    const pc = T.mod(midi, 12);
    const spelled = opts.spelled;
    const color = settings.colors ? (spelled ? GQ.UI.spelledColor(spelled) : GQ.UI.pcColor(pc)) : '#37474F';
    let label = opts.label;
    if (label === undefined) label = spelled ? T.noteLabel(spelled, settings.naming === 'both' ? 'letters' : settings.naming) : T.pcLabel(pc, settings.naming === 'both' ? 'letters' : settings.naming, settings.accidentals);
    return { string, fret, label, color, textColor: GQ.UI.inkOn(color), kind: opts.kind || 'note', cls: opts.cls };
  }

  GQ.Fretboard = Fretboard;
  GQ.noteMark = noteMark;
})(window.GQ = window.GQ || {});
