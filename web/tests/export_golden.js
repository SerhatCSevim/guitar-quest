/* Guitar Quest - writes "golden" reference data from the JavaScript engine, so a port (e.g. Swift)
   can be checked result-for-result.   Usage: node tests/export_golden.js <output folder> */
'use strict';
const path = require('path');
const fs = require('fs');
const out = path.resolve(process.argv[2] || path.join(__dirname, 'golden'));
fs.mkdirSync(out, { recursive: true });

const js = path.join(__dirname, '..', 'js');
['theory.js', 'chords.js', 'songs.js', 'exercises.js', 'notation.js'].forEach((f) => require(path.join(js, f)));
// The view modules only need these names to load; they are not used here.
globalThis.window = globalThis;
const GQ = globalThis.GQ;
GQ.UI = { h() {}, clear() {}, segmented() {}, select() {}, field() {}, icon() {} };
require(path.join(js, 'views', 'quest.js'));
require(path.join(js, 'views', 'harmony.js'));

const T = GQ.Theory, C = GQ.Chords, E = GQ.Exercises, N = GQ.Notation;
const nm = (n) => T.noteAscii(n);
const write = (name, data) => {
  const file = path.join(out, name);
  fs.writeFileSync(file, JSON.stringify(data));
  console.log(name + '  ' + (fs.statSync(file).size / 1024).toFixed(0) + ' KB');
};
const ROOTS = Array.from(new Set(T.MAJOR_KEYS.concat(T.MINOR_KEYS)));

/* ---- theory ---- */
const theory = { scales: {}, stepPatterns: {}, keySignatures: {}, relatives: {}, chordTones: {}, chordFormulas: {}, harmonize: {}, staffPositions: [] };
Object.keys(T.SCALES).forEach((sid) => {
  theory.stepPatterns[sid] = T.stepPattern(sid);
  T.keyNames(T.SCALES[sid].family).forEach((k) => {
    theory.scales[sid + ':' + k] = T.scaleNotes(T.parseNote(k), sid).map((n) => ({ note: nm(n), degree: n.degree, semis: n.semis, label: n.label, pc: n.pc }));
  });
});
['major', 'minor'].forEach((fam) => T.keyNames(fam).forEach((k) => {
  const ks = T.keySignature(T.parseNote(k), fam);
  theory.keySignatures[fam + ':' + k] = { fifths: ks.fifths, list: ks.list.map(nm), alters: ks.alters, majorTonic: nm(ks.majorTonic) };
  theory.relatives[fam + ':' + k] = nm(fam === 'major' ? T.relativeMinorOf(T.parseNote(k)) : T.relativeMajorOf(T.parseNote(k)));
  [false, true].forEach((sev) => {
    theory.harmonize[fam + ':' + k + ':' + (sev ? '7' : '3')] = T.harmonize(T.parseNote(k), fam, sev).map((c) => ({ degree: c.degree, root: nm(c.root), type: c.type, roman: c.roman, symbol: T.chordSymbol(c.root, c.type) }));
  });
}));
ROOTS.forEach((r) => Object.keys(T.CHORD_TYPES).forEach((t) => {
  theory.chordTones[r + ':' + t] = T.chordTones(T.parseNote(r), t).map((n) => ({ note: nm(n), degree: n.degree, semis: n.semis, label: n.label }));
}));
Object.keys(T.CHORD_TYPES).forEach((t) => { theory.chordFormulas[t] = T.chordFormula(t); });
for (let s = 1; s <= 6; s++) for (let f = 0; f <= 15; f++) {
  const midi = T.midiAt(s, f);
  [T.spellPc(midi % 12, 'sharp'), T.spellPc(midi % 12, 'flat')].forEach((sp) => {
    const oct = T.octaveOf(midi, sp);
    theory.staffPositions.push({ string: s, fret: f, midi, note: nm(sp), soundingOctave: oct, writtenStaffPos: T.staffPos(sp.l, oct + 1) });
  });
}
write('theory.json', theory);

/* ---- shapes and patterns ---- */
const shapes = { shapes: {}, rootToRoot: {}, patterns: {} };
Object.keys(T.SCALES).forEach((sid) => T.keyNames(T.SCALES[sid].family).forEach((k) => T.shapeOptions(sid).forEach((o) => {
  const sh = T.buildShape(T.parseNote(k), sid, o.id, 15);
  const enc = (n) => n.string + '/' + n.fret + ' ' + nm(n.spelled) + ' ' + n.label + (n.isRoot ? ' R' : '');
  shapes.shapes[sid + ':' + k + ':' + o.id] = { name: o.name, minFret: sh.minFret, maxFret: sh.maxFret, notes: sh.notes.map(enc) };
  if (o.id !== 'neck') shapes.rootToRoot[sid + ':' + k + ':' + o.id] = T.rootToRoot(sh.notes).map(enc);
})));
Object.keys(E.PATTERNS).forEach((p) => { shapes.patterns[p] = {}; for (let n = 1; n <= 24; n++) shapes.patterns[p][n] = T.patternIndices(n, p); });
write('shapes.json', shapes);

/* ---- chord voicings ---- */
const chords = { open: C.OPEN.map((v) => ({ root: nm(v.root), type: v.type, frets: v.frets, fingers: v.fingers })), voicings: {} };
ROOTS.forEach((r) => Object.keys(T.CHORD_TYPES).forEach((t) => {
  chords.voicings[r + ':' + t] = C.voicingsFor(T.parseNote(r), t).map((v) => ({ kind: v.kind, frets: v.frets, fingers: v.fingers, rootFret: v.rootFret === undefined ? null : v.rootFret, validation: C.validate(v) }));
}));
write('chords.json', chords);

/* ---- exercises (every combination) and songs ---- */
const evText = (ev) => (ev.rest ? 'r' : ev.notes.map((n) => n.string + '/' + n.fret + '=' + nm(n.spelled)).join('+')) + ':' + ev.dur + (ev.tuplet ? 't' : '');
const exercises = { format: 'events: "string/fret=Note:ticks" (r = rest, trailing t = triplet); 12 ticks = 1 beat, 48 = one 4/4 bar', scores: {} };
let count = 0;
Object.keys(T.SCALES).forEach((sid) => T.keyNames(T.SCALES[sid].family).forEach((k) => T.shapeOptions(sid).filter((o) => o.id !== 'neck').forEach((o) => {
  Object.keys(E.PATTERNS).forEach((p) => Object.keys(E.RHYTHMS).forEach((r) => ['root', 'full'].forEach((range) => {
    const sc = E.buildScaleScore({ tonic: k, scaleId: sid, shapeId: o.id, pattern: p, rhythm: r, range });
    exercises.scores[[sid, k, o.id, p, r, range].join(':')] = { bars: sc.measures.length, fifths: sc.keySig.fifths, events: sc.events.map(evText).join(' ') };
    count++;
  })));
})));
console.log('exercise combinations: ' + count);
write('exercises.json', exercises);
const songs = GQ.SONGS.map((s) => {
  const sc = E.buildSongScore(s);
  return { id: s.id, title: s.title, source: s.notes, bars: sc.measures.length, fifths: sc.keySig.fifths, events: sc.events.map(evText) };
});
write('songs.json', songs);

/* ---- notation structure (pitch -> staff, accidentals, durations, beam groups) ---- */
const notation = {};
const sample = GQ.SONGS.map((s) => [s.id, E.buildSongScore(s)]).concat([
  ['Eb-major-3nps3-groups4-s', E.buildScaleScore({ tonic: 'Eb', scaleId: 'major', shapeId: '3nps3', pattern: 'groups4', rhythm: 's', range: 'full' })],
  ['A-blues-box1-groups3-t', E.buildScaleScore({ tonic: 'A', scaleId: 'blues', shapeId: 'box1', pattern: 'groups3', rhythm: 't', range: 'full' })],
  ['F#-minor-r6-thirds-e', E.buildScaleScore({ tonic: 'F#', scaleId: 'minor', shapeId: 'r6', pattern: 'thirds', rhythm: 'e', range: 'root' })],
  ['A-minorPent-box1-updown-e', E.buildScaleScore({ tonic: 'A', scaleId: 'minorPent', shapeId: 'box1', pattern: 'updown', rhythm: 'e', range: 'full' })],
]);
sample.forEach(([id, sc]) => {
  const L = N.layout(sc, { width: 1000, showStaff: true, showTab: true, showNames: false, colors: false, naming: 'letters' });
  N.prepareBeams(L);
  notation[id] = {
    events: L.prep.map((p) => ({ glyph: p.nv, rest: !!p.ev.rest, heads: p.heads.map((hd) => ({ pos: hd.pos, accidentalShown: hd.acc })) })),
    beamGroups: L.beams.all.map((g) => ({ events: g.items, tuplet: g.tuplet, dir: g.dir || null })),
    layoutAt1000px: { systems: L.systems.map((s) => ({ measures: s.measures, scale: +s.scale.toFixed(4) })), eventX: L.prep.map((p) => +p.x.toFixed(1)) },
  };
});
write('notation.json', notation);

/* ---- game data: Note Quest level pools, jam progressions ---- */
const Q = GQ.Views.quest, H = GQ.Views.harmony;
const game = { questLevels: {}, progressions: {}, strums: H.STRUMS };
Q.LEVELS.forEach((lv) => {
  const pool = [];
  for (let s = 1; s <= 6; s++) for (let f = 0; f <= 15; f++) if (lv.test(s, f)) pool.push(s + '/' + f);
  game.questLevels[lv.id] = { name: lv.name, hint: lv.hint, maxFret: lv.maxFret, accidentals: !!lv.acc, pool };
});
H.PROGS.forEach((p) => {
  const keys = p.family === 'minor' ? ['A', 'E', 'D', 'B'] : ['C', 'G', 'D', 'A', 'E', 'F'];
  game.progressions[p.id] = { name: p.name, label: p.label, family: p.family, degrees: p.degrees, byKey: {} };
  keys.forEach((k) => {
    game.progressions[p.id].byKey[k] = H.progChords(p, k).map((c) => ({ symbol: T.chordSymbol(c.root, c.type), roman: c.roman, frets: C.bestVoicing(c.root, c.type).frets }));
  });
});
write('game.json', game);
