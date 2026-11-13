/* Guitar Quest - score renderer: standard notation (treble clef, guitar written an octave up) + tablature.
   Produces SVG strings; ScoreView adds layout, highlighting and click-to-seek in the browser. */
(function (GQ) {
  'use strict';
  const T = GQ.Theory;
  const SP = 10;              // staff space
  const HRX = 6.3, HRY = 4.6; // note head radii
  const TS = 13;              // tab line spacing
  const STEM = 34;

  const fmt = (n) => Math.round(n * 10) / 10;

  /* ---------- glyph paths (drawn, so no music font is needed) ---------- */
  function sharpPath(x, y) {
    return '<g class="acc"><path d="M' + fmt(x - 2) + ',' + fmt(y - 10) + 'V' + fmt(y + 9) + 'M' + fmt(x + 2) + ',' + fmt(y - 9) + 'V' + fmt(y + 10) + '" stroke-width="1.2"/>' +
      '<path d="M' + fmt(x - 4.6) + ',' + fmt(y - 1.6) + 'L' + fmt(x + 4.6) + ',' + fmt(y - 4.6) + 'V' + fmt(y - 2.2) + 'L' + fmt(x - 4.6) + ',' + fmt(y + 0.8) + 'Z' +
      'M' + fmt(x - 4.6) + ',' + fmt(y + 4.6) + 'L' + fmt(x + 4.6) + ',' + fmt(y + 1.6) + 'V' + fmt(y + 4) + 'L' + fmt(x - 4.6) + ',' + fmt(y + 7) + 'Z" class="fill"/></g>';
  }
  function flatPath(x, y) {
    return '<g class="acc"><path d="M' + fmt(x - 3) + ',' + fmt(y - 13) + 'V' + fmt(y + 4.5) + '" stroke-width="1.3"/>' +
      '<path d="M' + fmt(x - 3) + ',' + fmt(y + 4.5) + 'C' + fmt(x + 6.5) + ',' + fmt(y - 0.5) + ' ' + fmt(x + 4.5) + ',' + fmt(y - 7.5) + ' ' + fmt(x - 3) + ',' + fmt(y - 2) +
      'V' + fmt(y - 0.4) + 'C' + fmt(x + 2.8) + ',' + fmt(y - 4.2) + ' ' + fmt(x + 3.2) + ',' + fmt(y + 0.2) + ' ' + fmt(x - 3) + ',' + fmt(y + 4.5) + 'Z" class="fill"/></g>';
  }
  function naturalPath(x, y) {
    return '<g class="acc"><path d="M' + fmt(x - 2.6) + ',' + fmt(y - 10) + 'V' + fmt(y + 4) + 'M' + fmt(x + 2.6) + ',' + fmt(y - 4) + 'V' + fmt(y + 10) + '" stroke-width="1.2"/>' +
      '<path d="M' + fmt(x - 2.6) + ',' + fmt(y - 2.4) + 'L' + fmt(x + 2.6) + ',' + fmt(y - 4.6) + 'V' + fmt(y - 2.2) + 'L' + fmt(x - 2.6) + ',' + fmt(y) + 'Z' +
      'M' + fmt(x - 2.6) + ',' + fmt(y + 4) + 'L' + fmt(x + 2.6) + ',' + fmt(y + 1.8) + 'V' + fmt(y + 4.2) + 'L' + fmt(x - 2.6) + ',' + fmt(y + 6.4) + 'Z" class="fill"/></g>';
  }
  function accGlyph(a, x, y) {
    if (a === 1) return sharpPath(x, y);
    if (a === -1) return flatPath(x, y);
    if (a === 0) return naturalPath(x, y);
    if (a === 2) return '<text x="' + fmt(x) + '" y="' + fmt(y + 4) + '" class="acc-text" text-anchor="middle">x</text>';
    if (a === -2) return flatPath(x - 4, y) + flatPath(x + 3, y);
    return '';
  }
  function clefGlyph(x, yG) {
    // Treble clef from the Segoe UI Symbol music block, anchored on the G line.
    return '<text x="' + fmt(x) + '" y="' + fmt(yG + 13) + '" class="clef">𝄞</text>';
  }

  /* ---------- layout ---------- */
  function noteValue(ev) {
    const d = ev.tuplet === 3 ? ev.dur * 1.5 : ev.dur;
    switch (d) {
      case 48: return { head: 'whole', flags: 0, dots: 0 };
      case 36: return { head: 'half', flags: 0, dots: 1 };
      case 24: return { head: 'half', flags: 0, dots: 0 };
      case 18: return { head: 'black', flags: 0, dots: 1 };
      case 12: return { head: 'black', flags: 0, dots: 0 };
      case 9: return { head: 'black', flags: 1, dots: 1 };
      case 6: return { head: 'black', flags: 1, dots: 0 };
      case 3: return { head: 'black', flags: 2, dots: 0 };
      default: throw new Error('No glyph for duration ' + ev.dur);
    }
  }

  // Works out written pitch, staff position and which accidentals must be printed (bar-by-bar).
  function prepare(score) {
    const ks = score.keySig;
    const out = [];
    let accState = null, bar = -1;
    score.events.forEach((ev) => {
      if (ev.measure !== bar) { bar = ev.measure; accState = {}; }
      const nv = noteValue(ev);
      const heads = ev.notes.map((n) => {
        const oct = T.octaveOf(n.midi, n.spelled) + 1; // guitar music is written an octave higher
        const pos = T.staffPos(n.spelled.l, oct);
        const key = n.spelled.l + ':' + oct;
        const current = key in accState ? accState[key] : ks.alters[n.spelled.l];
        let show = null;
        if (current !== n.spelled.a) { show = n.spelled.a; accState[key] = n.spelled.a; }
        return { pos, acc: show, spelled: n.spelled, string: n.string, fret: n.fret, midi: n.midi };
      });
      out.push({ ev, nv, heads, hasAcc: heads.some((hd) => hd.acc !== null) });
    });
    return out;
  }

  function evWidth(p) {
    const w = 16 + 32 * Math.pow(p.ev.dur / 12, 0.55);
    return w + (p.hasAcc ? 9 : 0) + (p.nv.dots ? 4 : 0);
  }

  function beamGroups(prep, score) {
    // Group eighths/sixteenths inside the same beat (triplets: the three of a beat).
    const groups = [];
    let cur = null;
    prep.forEach((p, i) => {
      const ev = p.ev;
      const beamable = !ev.rest && p.nv.flags > 0;
      const beat = ev.measure * 4 + Math.floor((ev.tick % score.bar) / score.tpb);
      if (beamable && cur && cur.beat === beat && cur.tuplet === ev.tuplet && cur.last === i - 1) {
        cur.items.push(i); cur.last = i;
      } else {
        if (cur) groups.push(cur);
        cur = beamable ? { beat, tuplet: ev.tuplet, items: [i], last: i } : null;
      }
    });
    if (cur) groups.push(cur);
    const byEvent = {};
    groups.forEach((g) => { if (g.items.length > 1) g.items.forEach((i) => { byEvent[i] = g; }); });
    // tuplet groups also need their bracket number even when not beamed
    return { groups: groups.filter((g) => g.items.length > 1), byEvent, all: groups };
  }

  /* opts: { width, showStaff, showTab, showNames, colors, naming, firstSystemTime } */
  function layout(score, opts) {
    const prep = prepare(score);
    const beams = beamGroups(prep, score);
    const ksCount = Math.abs(score.keySig.fifths);
    const marginL = 6, marginR = 8;
    const clefW = opts.showStaff ? 38 : 30;
    const headerW = (first) => clefW + (opts.showStaff && ksCount ? ksCount * 9.5 + 6 : 0) + (first && opts.showStaff ? 26 : 0) + 6;
    const mWidths = score.measures.map((ids) => 12 + ids.reduce((s, i) => s + evWidth(prep[i]), 0) + 4);
    const systems = [];
    let cur = null;
    score.measures.forEach((ids, m) => {
      const first = systems.length === 0 && !cur;
      if (!cur) cur = { measures: [], width: 0, header: headerW(first), first };
      const avail = opts.width - marginL - marginR - cur.header;
      if (cur.measures.length && cur.width + mWidths[m] > avail) {
        systems.push(cur);
        cur = { measures: [], width: 0, header: headerW(false), first: false };
      }
      cur.measures.push(m); cur.width += mWidths[m];
    });
    if (cur) systems.push(cur);

    // vertical layout
    const staffTop = opts.showStaff ? 52 : 0;
    const staffBottom = staffTop + 4 * SP;
    const tabTop = opts.showStaff ? (opts.showTab ? staffBottom + 64 : 0) : 30;
    const tabBottom = tabTop + 5 * TS;
    let bottom = opts.showTab ? tabBottom : staffBottom + 50;
    const namesY = opts.showNames ? bottom + 22 : null;
    if (opts.showNames) bottom = namesY;
    const rhythmTop = !opts.showStaff && opts.showTab ? bottom + 8 : null;
    if (rhythmTop !== null) bottom = rhythmTop + 30;
    const height = bottom + 16;

    systems.forEach((sys, si) => {
      const avail = opts.width - marginL - marginR - sys.header;
      let scale = avail / sys.width;
      if (si === systems.length - 1 && systems.length > 1) scale = Math.min(scale, 1.35);
      if (systems.length === 1) scale = Math.min(scale, 1.6);
      sys.scale = scale;
      let x = marginL + sys.header;
      sys.bars = [];
      sys.events = [];
      sys.measures.forEach((m) => {
        const mx = x;
        let ex = x + 12 * scale;
        score.measures[m].forEach((i) => {
          const p = prep[i];
          const w = evWidth(p) * scale;
          p.x = ex + 6 + (p.hasAcc ? 9 : 0);
          p.slot = [ex, ex + w];
          p.system = si;
          sys.events.push(i);
          ex += w;
        });
        x = mx + mWidths[m] * scale;
        sys.bars.push({ m, x0: mx, x1: x });
      });
      sys.right = x;
    });
    return { score, opts, prep, beams, systems, staffTop, staffBottom, tabTop, tabBottom, namesY, rhythmTop, height };
  }

  /* ---------- drawing ---------- */
  function yOf(L, pos) { return L.staffTop + (8 - pos) * SP / 2; }

  function stemDir(heads) {
    const avg = heads.reduce((s, h) => s + h.pos, 0) / heads.length;
    return avg >= 4 ? 'down' : 'up';
  }

  function headColor(L, hd) {
    return L.opts.colors ? GQ.UI_COLORS.spelled(hd.spelled) : null;
  }

  function drawSystem(L, si) {
    const sys = L.systems[si];
    const o = L.opts;
    // a single short line is drawn only as wide as it needs, so small examples can be centred
    const W = L.systems.length === 1 ? Math.min(o.width, Math.ceil(sys.right + 10)) : o.width;
    const out = [];
    const ks = L.score.keySig;
    out.push('<svg class="score-sys" data-sys="' + si + '" viewBox="0 0 ' + W + ' ' + L.height + '" width="' + W + '" height="' + L.height + '" xmlns="http://www.w3.org/2000/svg">');
    out.push('<rect class="cursor" visibility="hidden" x="0" y="' + (o.showStaff ? L.staffTop - 30 : L.tabTop - 16) + '" width="30" height="' + ((L.namesY || L.tabBottom || L.staffBottom) - (o.showStaff ? L.staffTop - 30 : L.tabTop - 16) + 12) + '" rx="6"/>');
    const xL = 6, xR = sys.right;
    // ---- staff
    if (o.showStaff) {
      for (let p = 0; p <= 8; p += 2) out.push('<line class="staff-line" x1="' + xL + '" x2="' + fmt(xR) + '" y1="' + yOf(L, p) + '" y2="' + yOf(L, p) + '"/>');
      out.push(clefGlyph(xL + 3, yOf(L, 2)));
      let x = xL + 38;
      const SH = [8, 5, 9, 6, 3, 7, 4], FL = [4, 7, 3, 6, 2, 5, 1];
      ks.list.forEach((n, k) => {
        const pos = ks.fifths > 0 ? SH[k] : FL[k];
        out.push(accGlyph(ks.fifths > 0 ? 1 : -1, x + 4, yOf(L, pos)));
        x += 9.5;
      });
      if (sys.first) {
        x += ks.list.length ? 6 : 0;
        out.push('<text class="timesig" x="' + fmt(x + 9) + '" y="' + fmt(yOf(L, 6) + 7.5) + '" text-anchor="middle">4</text>');
        out.push('<text class="timesig" x="' + fmt(x + 9) + '" y="' + fmt(yOf(L, 2) + 7.5) + '" text-anchor="middle">4</text>');
      }
    }
    // ---- tab
    if (o.showTab) {
      for (let st = 1; st <= 6; st++) {
        const y = L.tabTop + (st - 1) * TS;
        out.push('<line class="tab-line" x1="' + xL + '" x2="' + fmt(xR) + '" y1="' + y + '" y2="' + y + '"/>');
      }
      ['T', 'A', 'B'].forEach((c, k) => out.push('<text class="tab-clef" x="' + (xL + 12) + '" y="' + fmt(L.tabTop + 14 + k * 17) + '" text-anchor="middle">' + c + '</text>'));
    }
    // ---- bar lines
    const barTop = o.showStaff ? L.staffTop : L.tabTop;
    const barBot = o.showTab ? L.tabBottom : L.staffBottom;
    const lastSys = si === L.systems.length - 1;
    out.push('<line class="bar" x1="' + xL + '" x2="' + xL + '" y1="' + barTop + '" y2="' + barBot + '"/>');
    sys.bars.forEach((b, k) => {
      const isEnd = lastSys && k === sys.bars.length - 1;
      if (isEnd) {
        out.push('<line class="bar" x1="' + fmt(b.x1 - 5) + '" x2="' + fmt(b.x1 - 5) + '" y1="' + barTop + '" y2="' + barBot + '"/>');
        out.push('<rect class="bar-end" x="' + fmt(b.x1 - 3) + '" y="' + barTop + '" width="3.4" height="' + (barBot - barTop) + '"/>');
      } else {
        out.push('<line class="bar" x1="' + fmt(b.x1) + '" x2="' + fmt(b.x1) + '" y1="' + barTop + '" y2="' + barBot + '"/>');
      }
      if (L.score.measures.length > 1) out.push('<text class="bar-num" x="' + fmt(b.x0 + 3) + '" y="' + (barTop - (o.showStaff ? 26 : 8)) + '">' + (b.m + 1) + '</text>');
    });
    // ---- events
    sys.events.forEach((i) => out.push(drawEvent(L, i)));
    // beams and tuplets for groups in this system
    L.beams.all.forEach((g) => {
      if (L.prep[g.items[0]].system !== si) return;
      if (g.items.length > 1 && o.showStaff) out.push(drawBeam(L, g));
      if (g.items.length > 1 && !o.showStaff && o.showTab) out.push(drawTabBeam(L, g));
      if (g.tuplet === 3) out.push(drawTupletMark(L, g));
    });
    out.push('</svg>');
    return out.join('');
  }

  function drawEvent(L, i) {
    const o = L.opts;
    const p = L.prep[i];
    const ev = p.ev;
    const out = ['<g class="ev" data-ev="' + i + '">'];
    const x = p.x;
    const top = o.showStaff ? L.staffTop - 30 : L.tabTop - 16;
    const bot = (L.rhythmTop !== null ? L.rhythmTop + 30 : (L.namesY || L.tabBottom || L.staffBottom)) + 8;
    out.push('<rect class="hit" x="' + fmt(p.slot[0]) + '" y="' + top + '" width="' + fmt(p.slot[1] - p.slot[0]) + '" height="' + (bot - top) + '"/>');
    if (o.showStaff) {
      if (ev.rest) out.push(drawRest(L, p));
      else out.push(drawNotes(L, i));
    }
    if (o.showTab && !ev.rest) {
      ev.notes.forEach((n) => {
        const y = L.tabTop + (n.string - 1) * TS;
        const txt = String(n.fret);
        const w = 7.5 * txt.length + 3;
        out.push('<rect class="tab-bg" x="' + fmt(x - w / 2) + '" y="' + fmt(y - 7) + '" width="' + fmt(w) + '" height="14"/>');
        out.push('<text class="tab-num" x="' + fmt(x) + '" y="' + fmt(y + 4.4) + '" text-anchor="middle">' + txt + '</text>');
      });
    }
    if (o.showNames && !ev.rest) {
      const names = ev.notes.map((n) => {
        const c = o.colors ? GQ.UI_COLORS.spelled(n.spelled) : '#455A64';
        return '<tspan fill="' + c + '">' + T.noteLabel(n.spelled, o.naming === 'both' ? 'letters' : o.naming) + '</tspan>';
      }).join(' ');
      out.push('<text class="note-name" x="' + fmt(x) + '" y="' + fmt(L.namesY) + '" text-anchor="middle">' + names + '</text>');
    }
    if (!o.showStaff && o.showTab && !ev.rest) out.push(drawTabRhythm(L, i));
    out.push('</g>');
    return out.join('');
  }

  function drawNotes(L, i) {
    const p = L.prep[i];
    const out = [];
    const x = p.x;
    const group = L.beams.byEvent[i];
    const dir = group ? group.dir || (group.dir = stemDir([].concat.apply([], group.items.map((k) => L.prep[k].heads)))) : stemDir(p.heads);
    const sorted = p.heads.slice().sort((a, b) => a.pos - b.pos);
    // ledger lines
    const minPos = sorted[0].pos, maxPos = sorted[sorted.length - 1].pos;
    for (let lp = -2; lp >= minPos; lp -= 2) out.push('<line class="ledger" x1="' + fmt(x - 10) + '" x2="' + fmt(x + 10) + '" y1="' + yOf(L, lp) + '" y2="' + yOf(L, lp) + '"/>');
    for (let lp = 10; lp <= maxPos; lp += 2) out.push('<line class="ledger" x1="' + fmt(x - 10) + '" x2="' + fmt(x + 10) + '" y1="' + yOf(L, lp) + '" y2="' + yOf(L, lp) + '"/>');
    // heads (seconds inside a chord are pushed to the side)
    sorted.forEach((hd, k) => {
      const y = yOf(L, hd.pos);
      const shift = k > 0 && hd.pos - sorted[k - 1].pos === 1 && !sorted[k - 1].shifted ? (dir === 'up' ? 2 * HRX - 0.5 : -(2 * HRX - 0.5)) : 0;
      hd.shifted = shift !== 0;
      const hx = x + shift;
      if (hd.acc !== null) out.push(accGlyph(hd.acc, x - 15, y));
      const col = headColor(L, hd);
      const fill = col ? ' style="--hc:' + col + '"' : '';
      if (p.nv.head === 'whole') {
        out.push('<ellipse class="head open whole"' + fill + ' cx="' + fmt(hx) + '" cy="' + fmt(y) + '" rx="' + (HRX + 1.3) + '" ry="' + HRY + '" stroke-width="2.6"/>');
      } else if (p.nv.head === 'half') {
        out.push('<ellipse class="head open"' + fill + ' cx="' + fmt(hx) + '" cy="' + fmt(y) + '" rx="' + HRX + '" ry="' + (HRY - 0.4) + '" transform="rotate(-22 ' + fmt(hx) + ' ' + fmt(y) + ')" stroke-width="2"/>');
      } else {
        out.push('<ellipse class="head"' + fill + ' cx="' + fmt(hx) + '" cy="' + fmt(y) + '" rx="' + HRX + '" ry="' + HRY + '" transform="rotate(-22 ' + fmt(hx) + ' ' + fmt(y) + ')"/>');
      }
      if (p.nv.dots) {
        const dy = hd.pos % 2 === 0 ? -SP / 2 : 0;
        out.push('<circle class="dot" cx="' + fmt(hx + HRX + 5) + '" cy="' + fmt(y + dy) + '" r="1.9"/>');
      }
    });
    if (p.nv.head === 'whole') return out.join('');
    // stem
    const yLow = yOf(L, minPos), yHigh = yOf(L, maxPos), yMid = yOf(L, 4);
    let sx, y0, y1;
    if (dir === 'up') {
      sx = x + HRX - 0.7; y0 = yLow;
      y1 = Math.min(yHigh - STEM, yMid);
    } else {
      sx = x - HRX + 0.7; y0 = yHigh;
      y1 = Math.max(yLow + STEM, yMid);
    }
    if (group && group.stemEnd) y1 = group.stemEnd(sx);
    p.stem = { x: sx, y0, y1, dir };
    out.push('<line class="stem" x1="' + fmt(sx) + '" x2="' + fmt(sx) + '" y1="' + fmt(y0) + '" y2="' + fmt(y1) + '"/>');
    if (!group && p.nv.flags) {
      for (let k = 0; k < p.nv.flags; k++) out.push(flagPath(sx, y1 + (dir === 'up' ? k * 7 : -k * 7), dir));
    }
    return out.join('');
  }

  function flagPath(x, y, dir) {
    if (dir === 'up') {
      return '<path class="flag" d="M' + fmt(x) + ',' + fmt(y) + 'C' + fmt(x + 1) + ',' + fmt(y + 7) + ' ' + fmt(x + 10.5) + ',' + fmt(y + 9) + ' ' + fmt(x + 7.5) + ',' + fmt(y + 21) +
        'C' + fmt(x + 8.5) + ',' + fmt(y + 12.5) + ' ' + fmt(x + 3) + ',' + fmt(y + 10.5) + ' ' + fmt(x) + ',' + fmt(y + 9.5) + 'Z"/>';
    }
    return '<path class="flag" d="M' + fmt(x) + ',' + fmt(y) + 'C' + fmt(x + 1) + ',' + fmt(y - 7) + ' ' + fmt(x + 10.5) + ',' + fmt(y - 9) + ' ' + fmt(x + 7.5) + ',' + fmt(y - 21) +
      'C' + fmt(x + 8.5) + ',' + fmt(y - 12.5) + ' ' + fmt(x + 3) + ',' + fmt(y - 10.5) + ' ' + fmt(x) + ',' + fmt(y - 9.5) + 'Z"/>';
  }

  // Beam stems are computed before the notes are drawn (see prepareBeams in render()).
  function prepareBeams(L) {
    L.beams.groups.forEach((g) => {
      const items = g.items.map((k) => L.prep[k]);
      g.dir = stemDir([].concat.apply([], items.map((p) => p.heads)));
      const up = g.dir === 'up';
      const pts = items.map((p) => {
        const ps = p.heads.map((h) => h.pos);
        const lo = Math.min.apply(null, ps), hi = Math.max.apply(null, ps);
        const x = up ? p.x + HRX - 0.7 : p.x - HRX + 0.7;
        const tipRef = up ? yOf(L, hi) : yOf(L, lo);
        return { x, tipRef };
      });
      const first = pts[0], last = pts[pts.length - 1];
      const want0 = first.tipRef + (up ? -STEM : STEM), want1 = last.tipRef + (up ? -STEM : STEM);
      const dx = Math.max(1, last.x - first.x);
      let slope = (want1 - want0) / dx;
      const maxRise = 9 / dx;
      slope = Math.max(-maxRise, Math.min(maxRise, slope));
      let base = want0;
      const MIN = 27;
      pts.forEach((pt) => {
        const yb = base + slope * (pt.x - first.x);
        if (up && yb > pt.tipRef - MIN) base -= yb - (pt.tipRef - MIN);
        if (!up && yb < pt.tipRef + MIN) base += (pt.tipRef + MIN) - yb;
      });
      // keep beams from floating far from the staff middle
      g.stemEnd = (x) => base + slope * (x - first.x);
      g.x0 = first.x; g.x1 = last.x;
    });
  }

  function drawBeam(L, g) {
    const up = g.dir === 'up';
    const items = g.items.map((k) => L.prep[k]);
    const out = [];
    const th = 4.6;
    const seg = (xa, xb, off) => {
      const ya = g.stemEnd(xa) + (up ? off : -off), yb = g.stemEnd(xb) + (up ? off : -off);
      const t = up ? th : -th;
      return '<path class="beam" d="M' + fmt(xa) + ',' + fmt(ya) + 'L' + fmt(xb) + ',' + fmt(yb) + 'L' + fmt(xb) + ',' + fmt(yb + t) + 'L' + fmt(xa) + ',' + fmt(ya + t) + 'Z"/>';
    };
    out.push(seg(g.x0 - 0.6, g.x1 + 0.6, 0));
    // secondary beams for sixteenths
    for (let k = 0; k < items.length; k++) {
      if (items[k].nv.flags < 2) continue;
      let j = k;
      while (j + 1 < items.length && items[j + 1].nv.flags >= 2) j++;
      const xa = items[k].stem ? items[k].stem.x : stemX(items[k], up);
      const xb = items[j].stem ? items[j].stem.x : stemX(items[j], up);
      if (j > k) out.push(seg(xa - 0.6, xb + 0.6, 7.2));
      else out.push(seg(k === items.length - 1 ? xa - 8 : xa, k === items.length - 1 ? xa : xa + 8, 7.2));
      k = j;
    }
    return out.join('');
  }
  function stemX(p, up) { return up ? p.x + HRX - 0.7 : p.x - HRX + 0.7; }

  function drawTupletMark(L, g) {
    const items = g.items.map((k) => L.prep[k]);
    const xm = (items[0].x + items[items.length - 1].x) / 2;
    if (L.opts.showStaff && g.items.length > 1) {
      const up = g.dir === 'up';
      const y = g.stemEnd(xm) + (up ? -7 : 16);
      return '<text class="tuplet" x="' + fmt(xm) + '" y="' + fmt(y) + '" text-anchor="middle">3</text>';
    }
    const y = L.opts.showStaff ? L.staffTop - 10 : (L.rhythmTop !== null ? L.rhythmTop + 42 : L.tabTop - 6);
    return '<text class="tuplet" x="' + fmt(xm) + '" y="' + fmt(y) + '" text-anchor="middle">3</text>';
  }

  function drawRest(L, p) {
    const x = p.x;
    const d = p.ev.tuplet === 3 ? p.ev.dur * 1.5 : p.ev.dur;
    const y = (pos) => yOf(L, pos);
    if (d >= 48) return '<rect class="rest" x="' + fmt(x - 6) + '" y="' + fmt(y(6)) + '" width="12" height="5"/>';
    if (d >= 24) return '<rect class="rest" x="' + fmt(x - 6) + '" y="' + fmt(y(4) - 5) + '" width="12" height="5"/>';
    if (d >= 12) {
      return '<path class="rest-q" d="M' + fmt(x - 2.5) + ',' + fmt(y(7.6)) + 'L' + fmt(x + 3.5) + ',' + fmt(y(5.8)) + 'L' + fmt(x - 1.8) + ',' + fmt(y(4.2)) +
        'L' + fmt(x + 3.4) + ',' + fmt(y(2.6)) + 'Q' + fmt(x - 4.5) + ',' + fmt(y(2.3)) + ' ' + fmt(x + 0.8) + ',' + fmt(y(0.6)) + '"/>';
    }
    const flags = d >= 6 ? 1 : 2;
    let s = '';
    for (let k = 0; k < flags; k++) {
      const yy = y(5) + k * 8;
      s += '<circle class="rest" cx="' + fmt(x - 2 - k * 1.5) + '" cy="' + fmt(yy) + '" r="2.6"/>' +
        '<path class="rest-stroke" d="M' + fmt(x - 2 - k * 1.5) + ',' + fmt(yy + 1.6) + 'Q' + fmt(x + 1) + ',' + fmt(yy + 3) + ' ' + fmt(x + 3.6 - k * 1.5) + ',' + fmt(yy - 1.5) + '"/>';
    }
    s += '<path class="rest-stroke" d="M' + fmt(x + 3.6) + ',' + fmt(y(5) - 1.5) + 'L' + fmt(x - 1.2 - (flags - 1) * 2) + ',' + fmt(y(5) + 15 + (flags - 1) * 6) + '"/>';
    return s;
  }

  // Rhythm stems under the tab (used when the staff is hidden).
  function drawTabRhythm(L, i) {
    const p = L.prep[i];
    if (p.nv.head === 'whole') return '';
    const x = p.x, y0 = L.rhythmTop, len = p.nv.head === 'half' ? 14 : 24;
    let s = '<line class="stem" x1="' + fmt(x) + '" x2="' + fmt(x) + '" y1="' + y0 + '" y2="' + (y0 + len) + '"/>';
    if (p.nv.dots) s += '<circle class="dot" cx="' + fmt(x + 5) + '" cy="' + (y0 + len - 3) + '" r="1.8"/>';
    if (!L.beams.byEvent[i] && p.nv.flags) {
      for (let k = 0; k < p.nv.flags; k++) s += flagPath(x, y0 + len - k * 7, 'down');
    }
    return s;
  }
  function drawTabBeam(L, g) {
    const items = g.items.map((k) => L.prep[k]);
    const y = L.rhythmTop + 24;
    let s = '<rect class="beam" x="' + fmt(items[0].x - 0.6) + '" y="' + (y - 4) + '" width="' + fmt(items[items.length - 1].x - items[0].x + 1.2) + '" height="4"/>';
    if (items.every((p) => p.nv.flags >= 2)) s += '<rect class="beam" x="' + fmt(items[0].x - 0.6) + '" y="' + (y - 10) + '" width="' + fmt(items[items.length - 1].x - items[0].x + 1.2) + '" height="4"/>';
    return s;
  }

  /* ---------- browser view ---------- */
  class ScoreView {
    constructor(el, opts) {
      this.el = el;
      this.opts = Object.assign({ showStaff: true, showTab: true, showNames: false, colors: true, naming: 'letters', minWidth: 520, onSeek: null }, opts || {});
      this.score = null;
      this.active = -1;
      el.classList.add('score-view');
      el.addEventListener('click', (e) => {
        const g = e.target.closest('[data-ev]');
        if (g && this.opts.onSeek) this.opts.onSeek(Number(g.dataset.ev));
      });
      this._resize = () => { clearTimeout(this._rt); this._rt = setTimeout(() => this.render(), 120); };
      window.addEventListener('resize', this._resize);
    }
    destroy() { window.removeEventListener('resize', this._resize); }
    setScore(score) { this.score = score; this.active = -1; this.render(); }
    setOptions(o) { Object.assign(this.opts, o); this.render(); }
    render() {
      if (!this.score) { this.el.innerHTML = ''; return; }
      const width = Math.max(this.opts.minWidth, Math.floor(this.el.clientWidth - 4) || 900);
      const o = Object.assign({}, this.opts, { width });
      if (!o.showStaff && !o.showTab) o.showTab = true;
      const L = layout(this.score, o);
      prepareBeams(L);
      this.L = L;
      const parts = L.systems.map((s, i) => drawSystem(L, i));
      this.el.innerHTML = parts.join('');
      this.sysEls = Array.from(this.el.querySelectorAll('.score-sys'));
      const a = this.active; this.active = -1;
      if (a >= 0) this.setActive(a, this.next);
    }
    setActive(i, next) {
      if (!this.L) return;
      this.el.querySelectorAll('.ev.active, .ev.next').forEach((g) => g.classList.remove('active', 'next'));
      this.sysEls.forEach((s) => { const c = s.querySelector('.cursor'); if (c) c.setAttribute('visibility', 'hidden'); });
      this.active = i; this.next = next;
      if (i === null || i === undefined || i < 0) return;
      const g = this.el.querySelector('.ev[data-ev="' + i + '"]');
      if (g) g.classList.add('active');
      if (next !== undefined && next !== null && next >= 0) {
        const gn = this.el.querySelector('.ev[data-ev="' + next + '"]');
        if (gn) gn.classList.add('next');
      }
      const p = this.L.prep[i];
      const sys = this.sysEls[p.system];
      if (sys) {
        const c = sys.querySelector('.cursor');
        c.setAttribute('x', fmt(p.x - 15));
        c.setAttribute('visibility', 'visible');
        if (this.opts.autoScroll !== false) this.scrollTo(sys);
      }
    }
    scrollTo(sys) {
      const box = this.el.getBoundingClientRect();
      const r = sys.getBoundingClientRect();
      if (r.top < box.top + 4 || r.bottom > box.bottom - 4) {
        this.el.scrollTo({ top: sys.offsetTop - this.el.offsetTop - 8, behavior: 'smooth' });
      }
    }
  }

  GQ.Notation = { layout, prepare, prepareBeams, drawSystem, noteValue, ScoreView };
  // colour lookup that works with or without the UI module (for tests)
  GQ.UI_COLORS = {
    spelled: (n) => (GQ.UI ? GQ.UI.spelledColor(n) : '#000'),
  };
})(typeof window !== 'undefined' ? (window.GQ = window.GQ || {}) : (globalThis.GQ = globalThis.GQ || {}));
