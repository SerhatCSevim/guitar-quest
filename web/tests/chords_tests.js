/* Chord voicing checks: every shape must really be the chord it claims to be. */
'use strict';
module.exports = function (GQ, ok, eq) {
  const T = GQ.Theory, C = GQ.Chords;
  const N = T.parseNote;

  C.OPEN.forEach((v) => {
    const err = C.validate(v);
    ok(!err, 'open ' + T.chordSymbol(v.root, v.type) + ': ' + err);
  });

  const roots = ['C', 'C#', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'Gb', 'G', 'Ab', 'G#', 'A', 'Bb', 'B'];
  let count = 0;
  roots.forEach((r) => {
    Object.keys(T.CHORD_TYPES).forEach((type) => {
      C.voicingsFor(N(r), type).forEach((v) => {
        count++;
        const err = C.validate(v);
        ok(!err, v.kind + ' ' + T.chordSymbol(v.root, v.type) + ' ' + JSON.stringify(v.frets) + ': ' + err);
        ok(v.frets.every((f) => f <= 15), 'fret range ' + T.chordSymbol(v.root, v.type));
      });
    });
  });
  ok(count > 200, 'many voicings generated: ' + count);

  // Every chord of every harmonized key (triads and sevenths) has at least one voicing.
  ['major', 'minor'].forEach((fam) => {
    T.keyNames(fam).forEach((k) => {
      [false, true].forEach((sev) => {
        T.harmonize(N(k), fam, sev).forEach((ch) => {
          ok(!!C.bestVoicing(ch.root, ch.type), 'voicing exists for ' + T.chordSymbol(ch.root, ch.type));
        });
      });
    });
  });

  eq(C.bestVoicing(N('B'), 'min').frets, [-1, 2, 4, 4, 3, 2], 'Bm barre at 2');
  eq(C.bestVoicing(N('F#'), 'min').frets, [2, 4, 4, 2, 2, 2], 'F#m barre at 2');
  eq(C.bestVoicing(N('Bb'), 'maj').frets, [-1, 1, 3, 3, 3, 1], 'Bb barre at 1');
  eq(C.bestVoicing(N('B'), 'dim').frets, [-1, 2, 3, 4, 3, -1], 'Bdim');
  eq(C.bestVoicing(N('C'), 'aug').frets, [-1, 3, 2, 1, 1, -1], 'Caug');
  eq(C.bestVoicing(N('C'), 'dim7').frets, [-1, 3, 4, 2, 4, -1], 'Cdim7');
  ok(C.diagramSVG(C.bestVoicing(N('C'), 'maj'), { title: 'C' }).indexOf('<svg') === 0, 'diagram svg');
};
