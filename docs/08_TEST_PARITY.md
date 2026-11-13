# 08 — Parity tests: proving the Swift version computes exactly what the web version computes

## 1. Golden files (`Sources/GoldenCheck/Golden/`)
Produced from the running JavaScript engine with
`node web/tests/export_golden.js <output folder>` (Node 18+). Regenerate whenever the web engine
changes. Note names use **ASCII** accidentals (`F#`, `Bb`); degree/chord labels use the Unicode signs (`♭3`, `m7♭5`).

| file | content and key format |
|---|---|
| `theory.json` | `scales["<scaleId>:<key>"]` → `[{note, degree, semis, label, pc}]` · `stepPatterns[scaleId]` · `keySignatures["<family>:<key>"]` → `{fifths, list, alters, majorTonic}` · `relatives["<family>:<key>"]` · `chordTones["<root>:<type>"]` (14 roots × 12 types) · `chordFormulas[type]` · `harmonize["<family>:<key>:<3\|7>"]` → `[{degree, root, type, roman, symbol}]` · `staffPositions[]` (every string/fret 0–15, sharp and flat spelling → sounding octave, written staff pos) |
| `shapes.json` | `shapes["<scaleId>:<key>:<shapeId>"]` → `{name, minFret, maxFret, notes: ["string/fret Note label [R]"]}` (all scales × keys × shapes, incl. `neck`) · `rootToRoot[...]` same keys without `neck` · `patterns[pattern][n]` for n = 1…24 |
| `chords.json` | `open[]` (the 32 open shapes) · `voicings["<root>:<type>"]` → `[{kind, frets, fingers, rootFret, validation}]` in `voicingsFor` order; `validation` is always `null` |
| `exercises.json` | **all 20 160** combinations: `scores["<scaleId>:<key>:<shapeId>:<pattern>:<rhythm>:<range>"]` → `{bars, fifths, events}`; events = space-separated `string/fret=Note:ticks`, `r:ticks` for rests, a trailing `t` marks triplets |
| `songs.json` | the 5 songs: source text, bars, key signature, event list |
| `notation.json` | per score (5 songs + 4 exercises): per event the glyph `{head, flags, dots}`, rest flag, heads `{pos, accidentalShown}`; beam groups `{events, tuplet, dir}`; layout at width 1000: systems (measures, scale) and every event x |
| `game.json` | `questLevels[id]` → `{name, hint, maxFret, accidentals, pool: ["s/f"]}` · `progressions[id].byKey[key]` → `[{symbol, roman, frets}]` · `strums[]` |

## 2. Required Swift tests
Implemented as the `GoldenCheck` executable (`swift run GoldenCheck`), so it runs without XCTest.
1. Load each golden file from the test bundle.
2. For every key in the file, call the Swift function with the same inputs and compare the **whole** result
   (encode the Swift result in the same string format, then compare strings — gives readable diffs).
3. `notation.json`: compare structure (glyphs, positions, accidentals, beam groups) exactly; x positions may
   differ by ≤ 0.5 unit (floating point) — or compare after rounding to 0.1.
4. Keep these hand-written checks too (they explain *why* the data is right):
   - D major = D E F♯ G A B C♯; F♯ major contains E♯; D♭ major = D♭ E♭ F G♭ A♭ B♭ C; G♯ minor = G♯ A♯ B C♯ D♯ E F♯
   - E major sharps in order F♯ C♯ G♯ D♯; A♭ major flats B♭ E♭ A♭ D♭; E♭ minor = 6 flats
   - C harmonized `C Dm Em F G Am Bdim` / `I ii iii IV V vi vii°`; with 7ths `Cmaj7 Dm7 Em7 Fmaj7 G7 Am7 Bm7♭5`
   - octaveOf: low E = E2; B♯ at MIDI 60 = B♯3; C♭ at MIDI 59 = C♭4; open low E written at staff pos −7
   - A minor pentatonic shapes: 1 = frets 5–8, 2 = 7–10, 3 = 9–13, 4 = 12–15, 5 = 2–5; E minor shape 1 = open
   - C major open position: `0,1,3 | 0,2,3 | 0,2,3 | 0,2 | 0,1,3 | 0,1,3` (strings 6→1; B is played open, not on G fret 4)
   - Every voicing of every root/type validates; Bm = x24432, Bdim = x2343x, Caug = x3221x, Cdim7 = x3424x
   - Mary Had a Little Lamb starts e0, B3, B1; every song stays in its string range
   - A blues prints a ♭ on E♭; D major prints no accidentals; every score ends on a bar line, no event crosses one
5. Audio/transport: unit-test the scheduler maths (beat → sample time, count-in length, loop restart time,
   trainer increase) with a fake clock; the sound itself is checked by ear against the web version.

## 3. UI parity (manual, with the screenshots)
| screenshot | check |
|---|---|
| 01_fretboard_explorer | default selection A on string 3 fret 2, ladder G → G♯ → A, unison rings |
| 02_note_quest_lobby | 3 games, round options, 8 levels with stars |
| 03_scales | A minor pentatonic shape 1, faint notes elsewhere, step badges |
| 04_studio_top / 05_studio_playing | controls; cursor, orange current note, next-note ring on the fretboard |
| 06_quest_tab_question / 07_quest_wrong_answer | tab question; wrong-answer explanation and marks |
| 08_chord_library … 12_theory_games | diagrams (red roots, barre bar, 3fr label), build steps, families, jam strum slots |
| 13_progress | stat cards, 14-day bars, fretboard map |

## 4. The web test-suite
`node web/tests/run_tests.js` → 2717 checks (theory, voicings, every exercise combination,
notation rendering). It must still pass if the web version is changed.
