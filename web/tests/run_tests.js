/* Guitar Quest - Node test runner: node tests/run_tests.js */
'use strict';
const path = require('path');
const root = path.join(__dirname, '..', 'js');
require(path.join(root, 'theory.js'));
const fs = require('fs');
['chords.js', 'songs.js', 'exercises.js', 'pitch.js'].forEach((f) => {
  const p = path.join(root, f);
  if (fs.existsSync(p)) require(p);
});
const GQ = globalThis.GQ;
const T = GQ.Theory;

let pass = 0, fail = 0;
function ok(cond, msg) {
  if (cond) pass++;
  else { fail++; console.log('FAIL: ' + msg); }
}
function eq(a, b, msg) {
  const sa = JSON.stringify(a), sb = JSON.stringify(b);
  ok(sa === sb, msg + '\n   got:      ' + sa + '\n   expected: ' + sb);
}
const names = (list) => list.map((n) => T.noteAscii(n)).join(' ');
const N = T.parseNote;

/* ---- scales ---- */
eq(names(T.scaleNotes(N('C'), 'major')), 'C D E F G A B', 'C major');
eq(names(T.scaleNotes(N('D'), 'major')), 'D E F# G A B C#', 'D major');
eq(names(T.scaleNotes(N('F#'), 'major')), 'F# G# A# B C# D# E#', 'F# major');
eq(names(T.scaleNotes(N('Db'), 'major')), 'Db Eb F Gb Ab Bb C', 'Db major');
eq(names(T.scaleNotes(N('Bb'), 'minor')), 'Bb C Db Eb F Gb Ab', 'Bb minor');
eq(names(T.scaleNotes(N('G#'), 'minor')), 'G# A# B C# D# E F#', 'G# minor');
eq(names(T.scaleNotes(N('A'), 'minorPent')), 'A C D E G', 'A minor pentatonic');
eq(names(T.scaleNotes(N('G'), 'majorPent')), 'G A B D E', 'G major pentatonic');
eq(names(T.scaleNotes(N('A'), 'blues')), 'A C D Eb E G', 'A blues');
eq(names(T.scaleNotes(N('E'), 'blues')), 'E G A Bb B D', 'E blues');
eq(T.stepPattern('major'), ['W', 'W', 'H', 'W', 'W', 'W', 'H'], 'major step pattern');
eq(T.stepPattern('minor'), ['W', 'H', 'W', 'W', 'H', 'W', 'W'], 'minor step pattern');
eq(T.scaleNotes(N('A'), 'minor').map((n) => n.label), ['1', '2', '♭3', '4', '5', '♭6', '♭7'], 'minor degree labels');

// Every key in both lists: 7 different letters, single accidentals only, pcs follow the formula.
['major', 'minor'].forEach((fam) => {
  T.keyNames(fam).forEach((k) => {
    const sc = T.scaleNotes(N(k), fam);
    ok(new Set(sc.map((n) => n.l)).size === 7, fam + ' ' + k + ' letters unique');
    ok(sc.every((n) => Math.abs(n.a) <= 1), fam + ' ' + k + ' no double accidentals');
    const t = T.notePc(N(k));
    ok(sc.every((n) => T.mod(n.pc - t, 12) === n.semis), fam + ' ' + k + ' pcs');
    const ks = T.keySignature(N(k), fam);
    ok(Math.abs(ks.fifths) <= 6, fam + ' ' + k + ' key signature size ' + ks.fifths);
    // The key signature must reproduce the scale exactly.
    ok(sc.every((n) => ks.alters[n.l] === n.a), fam + ' ' + k + ' key signature matches scale');
  });
});

/* ---- key signatures ---- */
eq(T.keySignature(N('G'), 'major').fifths, 1, 'G major 1 sharp');
eq(names(T.keySignature(N('E'), 'major').list), 'F# C# G# D#', 'E major sharps in order');
eq(names(T.keySignature(N('Ab'), 'major').list), 'Bb Eb Ab Db', 'Ab major flats in order');
eq(T.keySignature(N('A'), 'minor').fifths, 0, 'A minor no accidentals');
eq(T.keySignature(N('Eb'), 'minor').fifths, -6, 'Eb minor 6 flats');
eq(T.keySignature(N('G#'), 'minor').fifths, 5, 'G# minor 5 sharps');
eq(T.keySignature(N('F#'), 'major').fifths, 6, 'F# major 6 sharps');
eq(T.noteAscii(T.relativeMinorOf(N('C'))), 'A', 'relative minor of C');
eq(T.noteAscii(T.relativeMinorOf(N('Eb'))), 'C', 'relative minor of Eb');
eq(T.noteAscii(T.relativeMajorOf(N('E'))), 'G', 'relative major of E minor');
eq(T.noteAscii(T.relativeMajorOf(N('F#'))), 'A', 'relative major of F# minor');

/* ---- chords ---- */
eq(names(T.chordTones(N('C'), 'maj')), 'C E G', 'C major triad');
eq(names(T.chordTones(N('F'), 'min')), 'F Ab C', 'F minor triad');
eq(names(T.chordTones(N('C'), 'dim')), 'C Eb Gb', 'C dim');
eq(names(T.chordTones(N('Bb'), 'aug')), 'Bb D F#', 'Bb aug');
eq(names(T.chordTones(N('E'), 'dim7')), 'E G Bb Db', 'E dim7');
eq(names(T.chordTones(N('Gb'), 'maj7')), 'Gb Bb Db F', 'Gbmaj7');
eq(names(T.chordTones(N('B'), 'm7b5')), 'B D F A', 'Bm7b5');
eq(T.chordFormula('dim7'), ['1', '♭3', '♭5', '♭♭7'], 'dim7 formula');
const hC = T.harmonize(N('C'), 'major', false);
eq(hC.map((c) => T.chordSymbol(c.root, c.type)).join(' '), 'C Dm Em F G Am Bdim', 'C harmonized');
eq(hC.map((c) => c.roman).join(' '), 'I ii iii IV V vi vii°', 'C romans');
const hC7 = T.harmonize(N('C'), 'major', true);
eq(hC7.map((c) => T.chordSymbol(c.root, c.type)).join(' '), 'Cmaj7 Dm7 Em7 Fmaj7 G7 Am7 Bm7♭5', 'C sevenths');
const hAm = T.harmonize(N('A'), 'minor', false);
eq(hAm.map((c) => T.chordSymbol(c.root, c.type)).join(' '), 'Am Bdim C Dm Em F G', 'A minor harmonized');
eq(hAm.map((c) => c.roman).join(' '), 'i ii° III iv v VI VII', 'A minor romans');
eq(T.harmonize(N('D'), 'major', false).map((c) => T.chordSymbol(c.root, c.type)).join(' '), 'D Em F♯m G A Bm C♯dim', 'D harmonized');

/* ---- octave / staff position ---- */
eq(T.octaveOf(40, N('E')), 2, 'low E octave');
eq(T.octaveOf(60, N('B#')), 3, 'B#3');
eq(T.octaveOf(59, N('Cb')), 4, 'Cb4');
eq(T.staffPos(2, T.octaveOf(40, N('E')) + 1), -7, 'low E written below 3 ledger lines');
eq(T.staffPos(3, 5), 8, 'F5 top line');

/* ---- fretboard positions ---- */
eq(T.lowestPosition(59), { string: 2, fret: 0 }, 'B3 -> open B');
eq(T.lowestPosition(55), { string: 3, fret: 0 }, 'G3 -> open G');
eq(T.lowestPosition(57), { string: 3, fret: 2 }, 'A3 -> G string fret 2');
eq(T.positionsOfMidi(64, 15).length, 4, 'E4 appears on 4 strings within 15 frets');

/* ---- shapes ---- */
const frets = (shape) => {
  const by = {};
  shape.notes.forEach((n) => { (by[n.string] = by[n.string] || []).push(n.fret); });
  return [6, 5, 4, 3, 2, 1].map((s) => (by[s] || []).sort((a, b) => a - b).join(',')).join(' | ');
};
eq(frets(T.buildShape(N('A'), 'minorPent', 'box1')), '5,8 | 5,7 | 5,7 | 5,7 | 5,8 | 5,8', 'Am pent shape 1');
eq(frets(T.buildShape(N('A'), 'minorPent', 'box2')), '8,10 | 7,10 | 7,10 | 7,9 | 8,10 | 8,10', 'Am pent shape 2');
eq(frets(T.buildShape(N('A'), 'minorPent', 'box3')), '10,12 | 10,12 | 10,12 | 9,12 | 10,13 | 10,12', 'Am pent shape 3');
eq(frets(T.buildShape(N('A'), 'minorPent', 'box4')), '12,15 | 12,15 | 12,14 | 12,14 | 13,15 | 12,15', 'Am pent shape 4');
eq(frets(T.buildShape(N('A'), 'minorPent', 'box5')), '3,5 | 3,5 | 2,5 | 2,5 | 3,5 | 3,5', 'Am pent shape 5');
eq(frets(T.buildShape(N('C'), 'majorPent', 'box1')), frets(T.buildShape(N('A'), 'minorPent', 'box1')), 'C major pent shape 1 = Am shape 1');
eq(frets(T.buildShape(N('E'), 'minorPent', 'box1')), '0,3 | 0,2 | 0,2 | 0,2 | 0,3 | 0,3', 'Em pent open shape');
eq(frets(T.buildShape(N('A'), 'blues', 'box1')), '5,8 | 5,6,7 | 5,7 | 5,7,8 | 5,8 | 5,8', 'A blues shape 1 adds Eb');
eq(frets(T.buildShape(N('C'), 'major', 'open')), '0,1,3 | 0,2,3 | 0,2,3 | 0,2 | 0,1,3 | 0,1,3', 'C major open position');
eq(frets(T.buildShape(N('A'), 'minor', 'r6')), '5,7,8 | 5,7,8 | 5,7 | 4,5,7 | 5,6,8 | 5,7,8', 'A minor root-6 position');
eq(frets(T.buildShape(N('C'), 'major', 'r5')), '3,5 | 2,3,5 | 2,3,5 | 2,4,5 | 3,5,6 | 3,5', 'C major root-5 position');
eq(frets(T.buildShape(N('G'), 'major', '3nps1')), '3,5,7 | 3,5,7 | 4,5,7 | 4,5,7 | 5,7,8 | 5,7,8', 'G major 3nps form 1');
const box = T.buildShape(N('A'), 'minorPent', 'box1');
ok(box.notes.every((n, i) => i === 0 || n.midi > box.notes[i - 1].midi), 'shape ascending');
eq(T.rootToRoot(T.buildShape(N('C'), 'major', 'r5').notes).map((n) => T.noteAscii(n.spelled)).join(' '),
  'C D E F G A B C', 'root-to-root trims C major root-5 shape');
// every shape of every key: all notes belong to the scale, frets >= 0, no duplicate pitches (except neck)
Object.keys(T.SCALES).forEach((sid) => {
  const fam = T.SCALES[sid].family;
  T.keyNames(fam).forEach((k) => {
    T.shapeOptions(sid).forEach((o) => {
      const sh = T.buildShape(N(k), sid, o.id);
      const pcs = new Set(T.scaleNotes(N(k), sid).map((n) => n.pc));
      ok(sh.notes.every((n) => n.fret >= 0 && pcs.has(n.pc)), sid + ' ' + k + ' ' + o.id + ' notes in scale');
      if (o.id !== 'neck') ok(new Set(sh.notes.map((n) => n.midi)).size === sh.notes.length, sid + ' ' + k + ' ' + o.id + ' unique pitches');
      if (o.id !== 'neck') ok(sh.maxFret - sh.minFret <= 6, sid + ' ' + k + ' ' + o.id + ' span ' + (sh.maxFret - sh.minFret));
    });
  });
});

/* ---- patterns ---- */
eq(T.patternIndices(4, 'updown'), [0, 1, 2, 3, 2, 1, 0], 'updown');
eq(T.patternIndices(4, 'groups3'), [0, 1, 2, 1, 2, 3, 3, 2, 1, 2, 1, 0], 'groups of 3');
eq(T.patternIndices(5, 'thirds'), [0, 2, 1, 3, 2, 4, 4, 2, 3, 1, 2, 0], 'thirds');

/* ---- optional modules ---- */
if (GQ.Chords) require('./chords_tests.js')(GQ, ok, eq);
if (GQ.Exercises) require('./exercise_tests.js')(GQ, ok, eq);
if (GQ.Pitch) require('./pitch_tests.js')(GQ, ok, eq);
require(path.join(root, 'notation.js'));
require('./notation_tests.js')(GQ, ok, eq);

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
