/* Notation renders every song and a sample of exercises to SVG without errors. */
'use strict';
module.exports = function (GQ, ok, eq) {
  const N = GQ.Notation, E = GQ.Exercises;
  const optsList = [
    { width: 900, showStaff: true, showTab: true, showNames: true, colors: false, naming: 'letters' },
    { width: 600, showStaff: false, showTab: true, showNames: false, colors: false, naming: 'letters' },
    { width: 1200, showStaff: true, showTab: false, showNames: false, colors: false, naming: 'solfege' },
  ];
  const scores = GQ.SONGS.map((s) => E.buildSongScore(s));
  ['e', 't', 's', 'q'].forEach((r) => {
    scores.push(E.buildScaleScore({ tonic: 'Eb', scaleId: 'major', shapeId: '3nps3', pattern: 'groups4', rhythm: r, range: 'full' }));
    scores.push(E.buildScaleScore({ tonic: 'A', scaleId: 'blues', shapeId: 'box1', pattern: 'groups3', rhythm: r, range: 'full' }));
    scores.push(E.buildScaleScore({ tonic: 'F#', scaleId: 'minor', shapeId: 'r6', pattern: 'thirds', rhythm: r, range: 'root' }));
  });
  scores.forEach((sc, k) => {
    optsList.forEach((o) => {
      try {
        const L = N.layout(sc, o);
        N.prepareBeams(L);
        const svg = L.systems.map((s, i) => N.drawSystem(L, i)).join('');
        ok(svg.indexOf('NaN') < 0, 'no NaN in svg for score ' + k + ' (' + sc.title + ')');
        ok(L.systems.every((s) => s.right <= o.width + 0.5), 'systems fit width for score ' + k);
        const evCount = (svg.match(/data-ev="/g) || []).length;
        eq(evCount, sc.events.length, 'every event drawn once for score ' + k);
      } catch (e) {
        ok(false, 'render score ' + k + ' (' + sc.title + '): ' + e.message);
      }
    });
  });
  // accidentals: A blues has Eb (not in key of A minor) -> printed once per bar
  const blues = E.buildScaleScore({ tonic: 'A', scaleId: 'blues', shapeId: 'box1', pattern: 'up', rhythm: 'q', range: 'full' });
  const prep = N.prepare(blues);
  const ebs = prep.filter((p) => p.heads.some((h) => h.spelled.l === 2 && h.spelled.a === -1));
  ok(ebs.length >= 2 && ebs.every((p) => p.heads[0].acc === -1 || p.heads[0].acc === null), 'Eb flats in A blues');
  ok(ebs.some((p) => p.heads[0].acc === -1), 'Eb gets a flat sign');
  // key signature: D major scale has F# and C# in the key signature -> no accidentals printed
  const d = E.buildScaleScore({ tonic: 'D', scaleId: 'major', shapeId: 'open', pattern: 'up', rhythm: 'q', range: 'root' });
  ok(N.prepare(d).every((p) => p.heads.every((h) => h.acc === null)), 'D major needs no accidentals with its key signature');
  // written pitch: open low E is written E3, three ledger lines below the staff
  const lowE = E.finalize([{ dur: 48, tuplet: 0, notes: [{ string: 6, fret: 0, midi: 40, spelled: { l: 2, a: 0 } }] }], { keySig: GQ.Theory.keySignature({ l: 0, a: 0 }, 'major') });
  eq(N.prepare(lowE)[0].heads[0].pos, -7, 'open low E staff position');
};
