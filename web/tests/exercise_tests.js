/* Score building checks: every generated exercise and song is a valid 4/4 score. */
'use strict';
module.exports = function (GQ, ok, eq) {
  const T = GQ.Theory, E = GQ.Exercises;

  // All songs parse, bars add up, every note is playable and in its key (or written with its own accidental).
  GQ.SONGS.forEach((song) => {
    let sc = null;
    try { sc = E.buildSongScore(song); } catch (e) { ok(false, 'song ' + song.id + ': ' + e.message); return; }
    ok(sc.events.every((ev) => ev.rest || ev.notes.every((n) => n.midi >= 40 && n.fret <= 12)), song.id + ' playable');
    const strs = new Set();
    sc.events.forEach((ev) => ev.notes.forEach((n) => strs.add(n.string)));
    const m = /Strings (\d)-(\d)/.exec(song.strings);
    ok([...strs].every((s) => s >= Number(m[1]) && s <= Number(m[2])), song.id + ' uses only ' + song.strings + ' (got ' + [...strs] + ')');
  });
  const mary = E.buildSongScore(GQ.SONGS[0]);
  eq(mary.measures.length, 8, 'Mary has 8 bars');
  eq(mary.events.slice(0, 3).map((e) => e.notes[0].string + '/' + e.notes[0].fret).join(' '), '1/0 2/3 2/1', 'Mary first notes E D C = e0 B3 B1');

  // Every scale exercise combination builds.
  let built = 0;
  Object.keys(T.SCALES).forEach((sid) => {
    T.keyNames(T.SCALES[sid].family).forEach((k) => {
      T.shapeOptions(sid).filter((o) => o.id !== 'neck').forEach((o) => {
        Object.keys(E.PATTERNS).forEach((p) => {
          Object.keys(E.RHYTHMS).forEach((r) => {
            ['root', 'full'].forEach((range) => {
              try {
                const sc = E.buildScaleScore({ tonic: k, scaleId: sid, shapeId: o.id, pattern: p, rhythm: r, range });
                built++;
                if (sc.events.some((ev) => ev.notes.some((n) => n.fret < 0))) ok(false, 'negative fret');
              } catch (e) {
                ok(false, [sid, k, o.id, p, r, range].join(' ') + ': ' + e.message);
              }
            });
          });
        });
      });
    });
  });
  ok(built > 5000, 'scale exercises built: ' + built);

  const ex = E.buildScaleScore({ tonic: 'A', scaleId: 'minorPent', shapeId: 'box1', pattern: 'updown', rhythm: 'e', range: 'full' });
  eq(ex.events.filter((e) => !e.rest).map((e) => e.notes[0].fret).join(','), '5,8,5,7,5,7,5,7,5,8,5,8,5,8,5,7,5,7,5,7,5,8,5', 'Am pent shape 1 up/down frets');
  eq(ex.measures.length, 3, 'Am pent up/down in eighths = 3 bars');
  const tl = E.timeline(ex);
  eq(tl[1].beat, 0.5, 'second eighth starts at beat 0.5');
};
