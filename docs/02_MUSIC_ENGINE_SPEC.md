# 02 — Music engine specification

Source of truth: `web/js/theory.js`, `chords.js`, `exercises.js`, `songs.js`.
Every function below has golden output in `Sources/GoldenCheck/Golden/*.json` (see `08_TEST_PARITY.md`). The Swift port
(`MusicCore` package) must reproduce those outputs exactly. This module has **no UI and no audio**.

## 1. Basic conventions

| Concept | Rule |
|---|---|
| Letter index `l` | 0..6 = C D E F G A B |
| Natural pitch class of a letter | `LETTER_PC = [0,2,4,5,7,9,11]` |
| Spelled note | `{ l, a }`, `a` = alteration −2..+2 (bb, b, natural, #, ##) |
| Pitch class of a spelled note | `mod(LETTER_PC[l] + a, 12)` |
| MIDI | C4 = 60, A4 = 69 = 440 Hz; `freq = 440·2^((midi−69)/12)` |
| Strings | **1 = high e (thinnest) … 6 = low E**. Tuning MIDI: 1:64, 2:59, 3:55, 4:50, 5:45, 6:40 |
| Open-string labels | 1 `e`, 2 `B`, 3 `G`, 4 `D`, 5 `A`, 6 `E` |
| `midiAt(string, fret)` | `TUNING[string] + fret` |
| `mod(n, m)` | always non-negative: `((n % m) + m) % m` |

Display strings: sharps/flats use the Unicode signs `♯ ♭ 𝄪 𝄫`; ASCII form (`#`, `b`, `##`, `bb`) is used in golden
files and in parsing. `parseNote` accepts `C`, `C#`, `Db`, `C##`/`Cx`, `Dbb` and the Unicode signs.

Naming modes (setting): `letters` → `C♯`, `solfege` → `Do♯` (Do Re Mi Fa Sol La Si), `both` → `C♯ (Do♯)`.

## 2. Spelling helpers

- `spellPc(pc, pref)`: natural if possible, otherwise sharp (`pref='sharp'`) or flat (`'flat'`) spelling.
- `isNaturalPc(pc)`: pc ∈ {0,2,4,5,7,9,11}.
- `pcLabel(pc, naming, pref)`: `pref='both'` → `C♯/D♭` for black-key notes.
- **`degreeNote(tonic, degree, semis)`** — the core of all correct spelling:
  ```
  l = mod(tonic.l + degree − 1, 7)
  target = mod(pc(tonic) + semis, 12)
  a = mod(target − LETTER_PC[l] + 6, 12) − 6
  ```
  e.g. F♯ + (7, 11) = E♯; G♭ + (4, 5) = C♭.
- `degreeLabel(degree, semis)`: compare with the major scale `[0,2,4,5,7,9,11]`; prefix `♭`×n or `♯`×n
  (e.g. `♭3`, `♭♭7`, `♯5`).
- **`octaveOf(midi, spelled)`** = `round((midi − a − LETTER_PC[l]) / 12) − 1` (so B♯3 = MIDI 60, C♭4 = MIDI 59).
- **`staffPos(l, octave)`** = `octave·7 + l − 30`. 0 = E4 (bottom line of treble staff), 8 = F5 (top line).
  Guitar music is written **one octave higher than it sounds**: written octave = `octaveOf(...) + 1`
  (open low E sounds E2, written E3, staff position −7).

## 3. Scales

| id | name | family | steps `[degree, semis]` |
|---|---|---|---|
| `major` | Major | major | [1,0] [2,2] [3,4] [4,5] [5,7] [6,9] [7,11] |
| `minor` | Natural minor | minor | [1,0] [2,2] [3,3] [4,5] [5,7] [6,8] [7,10] |
| `majorPent` | Major pentatonic | major (pent) | [1,0] [2,2] [3,4] [5,7] [6,9] |
| `minorPent` | Minor pentatonic | minor (pent) | [1,0] [3,3] [4,5] [5,7] [7,10] |
| `blues` | Blues | minor (pent, blues) | [1,0] [3,3] [4,5] [5,6] [5,7] [7,10] |

`scaleNotes(tonic, id)` = `degreeNote` for every step, plus `label = degreeLabel` and `pc`.
The blues ♭5 is written as a lowered 5th (A blues → E♭, not D♯).

`stepPattern(id)`: differences between consecutive semitone values incl. the octave (12);
1 → `H`, 2 → `W`, 3 → `W+H`. Major = `W W H W W W H`, minor = `W H W W H W W`.

### Keys offered (exact lists, in this order)
- Major: `C Db D Eb E F F# G Ab A Bb B`
- Minor: `C C# D Eb E F F# G G# A Bb B`

When the user switches scale family, keep the same pitch class (e.g. D♭ major → C♯ minor), else first key.

### Key signature
`keySignature(tonic, family)`: use the tonic (major) or its **relative major** (minor: `degreeNote(t, 3, 3)`),
build its major scale, collect alterations per letter. Sharps listed in order F C G D A E B, flats in order
B E A D G C F. Result: `fifths` (+sharps / −flats), `alters[7]`, ordered `list`, `majorTonic`.
Relative minor of a major key = `degreeNote(t, 6, 9)`.

## 4. Chords

| type | name | symbol | tones `[degree, semis]` |
|---|---|---|---|
| maj | Major | `` | [1,0] [3,4] [5,7] |
| min | Minor | `m` | [1,0] [3,3] [5,7] |
| dim | Diminished | `dim` | [1,0] [3,3] [5,6] |
| aug | Augmented | `aug` | [1,0] [3,4] [5,8] |
| sus2 | Suspended 2nd | `sus2` | [1,0] [2,2] [5,7] |
| sus4 | Suspended 4th | `sus4` | [1,0] [4,5] [5,7] |
| power | Power chord | `5` | [1,0] [5,7] |
| dom7 | Dominant 7th | `7` | [1,0] [3,4] [5,7] [7,10] |
| maj7 | Major 7th | `maj7` | [1,0] [3,4] [5,7] [7,11] |
| min7 | Minor 7th | `m7` | [1,0] [3,3] [5,7] [7,10] |
| m7b5 | Half-diminished 7th | `m7♭5` | [1,0] [3,3] [5,6] [7,10] |
| dim7 | Diminished 7th | `dim7` | [1,0] [3,3] [5,6] [7,9] |

- `chordTones(root, type)` = `degreeNote` per tone (E dim7 = E G B♭ D♭).
- `chordSymbol(root, type, naming)` = note label + symbol.
- `chordFormula(type)` = degree labels (`dim7` → `1 ♭3 ♭5 ♭♭7`).
- `typeFromIntervals(semis above root)`: `4,7` maj · `3,7` min · `3,6` dim · `4,8` aug · `4,7,11` maj7 ·
  `3,7,10` min7 · `4,7,10` dom7 · `3,6,10` m7b5 · `3,6,9` dim7.
- `romanFor(index, type)`: `I…VII`; lower-case for min/dim/min7/m7b5/dim7; suffix `°` (dim), `+` (aug),
  `maj7`, `7` (dom7 and min7), `ø7` (m7b5), `°7` (dim7).
- **`harmonize(tonic, family, sevenths)`**: scale = major or natural minor; for each step i stack
  scale[i+2], scale[i+4] (+ scale[i+6] if sevenths), intervals mod 12 → type → roman.
  C major → `C Dm Em F G Am Bdim` / `I ii iii IV V vi vii°`; A minor → `i ii° III iv v VI VII`.

## 5. Fretboard helpers
- `positionsOfMidi(midi, maxFret)`: every (string, fret ≤ maxFret) with that exact pitch.
- `positionsOfPc(pc, maxFret)`.
- **`lowestPosition(midi)`**: among all positions (frets 0–24) the one with the smallest fret
  (gives first-position fingering: B3 → open B, A3 → G string fret 2). Used for song tab.

## 6. Scale shapes (fingerings)

`shapeOptions(scaleId)`:
- pentatonic/blues: `neck` "Whole neck", `box1`…`box5` "Shape 1"…"Shape 5"
- major/minor: `neck`, `open` "Open position", `r6` "Root on 6th string", `r5` "Root on 5th string",
  `3nps1`…`3nps7` "3 notes per string - form k"

`buildShape(tonic, scaleId, shapeId, maxFret = 15)` returns `{ notes, minFret, maxFret }`; every note has
`string, fret, midi, pc, spelled, degree, label, isRoot`. Notes are **sorted by MIDI ascending, ties: higher
string number first**. Algorithms:

| shape | algorithm |
|---|---|
| `neck` | every (string, fret 0…maxFret) whose pc is in the scale |
| `open` | `windowShape(lo=0, hi=4)` |
| `r6` / `r5` | r = `mod(tonicPc − TUNING[s], 12)`, r = 12 if 0; `windowShape(r−1, r+3)` with s = 6 / 5 |
| `boxK` | see below |
| `3npsK` | `sequentialShape(scale pcs, startFret = mod(pc of scale note K − 40, 12), perString = 3)` |

**windowShape(lo, hi)**: strings 6→1, frets max(0,lo)…hi, keep scale tones. If the same MIDI pitch occurs twice
(only possible at G-string `hi` and B-string `lo`), keep the one on the **higher string (smaller number)**.

**sequentialShape(pcSet, startFret, perString)**: walk MIDI upward from `40 + startFret`, collect the first
`6·perString` pitches whose pc is in the set; note i goes on string `6 − floor(i / perString)`, fret = midi − tuning.

**Pentatonic boxes** (`boxK`, also for major pentatonic and blues): shapes are always numbered from the
**minor** pentatonic (major keys use their relative minor). `minorPent = scaleNotes(minorTonic,'minorPent')`;
`startFret = mod(minorPent[K−1].pc − 40, 12)`; `shape1Fret = mod(minorPent[0].pc − 40, 12)`;
list = `sequentialShape(minor pent pcs, startFret, 2)`. Then **move the whole shape +12 frets** if
(a) any fret < 0, or (b) `K > 1 && startFret < shape1Fret && highestFret + 12 ≤ maxFret`.
Blues: after that, add the ♭5 (minorTonic + 6) on every string for frets between the box's min and max fret.
Check: A minor pent → shape 1 frets 5–8, shape 2 7–10, shape 3 9–13, shape 4 12–15, shape 5 2–5.

**rootToRoot(notes)**: slice from the first to the last note with `isRoot` (unchanged if fewer than 2 roots).

**patternIndices(n, pattern)** over n ascending notes:
- `up` 0…n−1 · `down` n−1…0 · `updown` = up + down without repeating the top
- `groups3` / `groups4` (size g): ascending windows `i…i+g−1` for i = 0…n−g, then descending windows
  `i, i−1, …, i−g+1` for i = n−1…g−1; if n < g fall back to updown
- `thirds`: pairs `(i, i+2)` for i = 0…n−3, then `(i, i−2)` for i = n−1…2; if n < 3 → updown

## 7. Chord voicings (`chords.js`)

Frets/fingers are written **6th string → 1st string**; fret −1 = muted (×), 0 = open; finger 0 = none.

**Open shapes (32)** — root, type, frets, fingers:

| chord | frets | fingers | | chord | frets | fingers |
|---|---|---|---|---|---|---|
| C | x32010 | 032010 | | E7 | 020100 | 020100 |
| C7 | x32310 | 032410 | | Em7 | 020000 | 020000 |
| Cmaj7 | x32000 | 032000 | | Emaj7 | 021100 | 031200 |
| D | xx0232 | 000132 | | Esus4 | 022200 | 023400 |
| Dm | xx0231 | 000231 | | E5 | 022xxx | 012000 |
| D7 | xx0212 | 000213 | | F (small) | xx3211 | 003211 |
| Dm7 | xx0211 | 000211 | | Fmaj7 | xx3210 | 003210 |
| Dmaj7 | xx0222 | 000111 | | G | 320003 | 320004 |
| Dsus2 | xx0230 | 000130 | | G7 | 320001 | 320001 |
| Dsus4 | xx0233 | 000134 | | Gmaj7 | 320002 | 320001 |
| D5 | xx023x | 000130 | | A | x02220 | 001230 |
| E | 022100 | 023100 | | Am | x02210 | 002310 |
| Em | 022000 | 023000 | | A7 | x02020 | 002030 |
| | | | | Am7 | x02010 | 002010 |
| | | | | Amaj7 | x02120 | 002130 |
| | | | | Asus2 | x02200 | 001200 |
| | | | | Asus4 | x02230 | 001230 |
| | | | | A5 | x022xx | 001200 |
| | | | | B7 | x21202 | 021304 |

**Moveable templates** (offsets from root fret r; `null` = muted; fingers `null` = draw dots without numbers):

| type | E-shape (root on 6th) offsets / fingers | A-shape (root on 5th) offsets / fingers |
|---|---|---|
| maj | 0,2,2,1,0,0 / 1,3,4,2,1,1 | x,0,2,2,2,0 / 0,1,2,3,4,1 |
| min | 0,2,2,0,0,0 / 1,3,4,1,1,1 | x,0,2,2,1,0 / 0,1,3,4,2,1 |
| dom7 | 0,2,0,1,0,0 / 1,3,1,2,1,1 | x,0,2,0,2,0 / 0,1,3,1,4,1 |
| min7 | 0,2,0,0,0,0 / 1,3,1,1,1,1 | x,0,2,0,1,0 / 0,1,3,1,2,1 |
| sus4 | 0,2,2,2,0,0 / 1,2,3,4,1,1 | x,0,2,2,3,0 / 0,1,2,3,4,1 |
| sus2 | — | x,0,2,2,0,0 / 0,1,3,4,1,1 |
| maj7 | 0,x,1,1,0,x / 1,0,3,4,2,0 | x,0,2,1,2,0 / 0,1,3,2,4,1 |
| dim | 0,1,2,0,x,x / (no fingers) | x,0,1,2,1,x / 0,1,2,4,3,0 |
| m7b5 | — | x,0,1,0,1,x / 0,1,3,2,4,0 |
| dim7 | — | x,0,1,−1,1,x / 0,2,3,1,4,0 |
| aug | — | x,0,−1,−2,−2,x / 0,3,2,1,1,0 |
| power | 0,2,2,x,x,x / 1,3,4,0,0,0 | x,0,2,2,x,x / 0,1,3,4,0,0 |

`fromShape`: r = `mod(rootPc − TUNING[rootString], 12)`; if r = 0 or `r + minOffset < 1` → r += 12. Fingers
on frets ≤ 0 are forced to 0. `kind` = `E-shape` / `A-shape`, `rootFret = r`.

**`voicingsFor(root, type)`** = open voicings with the same root pc and type, then the moveable ones sorted by
`rootFret`. `bestVoicing` = first. Every chord of every harmonized key has at least one voicing.

**`validate(v)`** (returns null when correct): every sounding note is a chord tone; the lowest sounding note is
the root; every tone except the 5th is present; fingers exist exactly on fretted (>0) strings. All shapes pass.

`voicingNotes(v)` → `[{string, fret, midi}]` low → high (used for strums and the chord's staff/tab).

## 8. Scores and exercises (`exercises.js`)

Time unit: **ticks, 12 per quarter-note beat, 48 per 4/4 bar**. Durations: `w`48 `h.`36 `h`24 `q.`18 `q`12
`8.`9 `8`6 `16`3; triplet eighth = 4 ticks with `tuplet: 3`.

Score = `{ title, subtitle, keySig, tempo, time [4,4], tpb 12, bar 48, events[], measures[][], totalTicks }`.
Event = `{ i, tick, measure, dur, tuplet (0|3), rest?, notes: [{ string, fret, midi, spelled }] }`.
`finalize` assigns ticks; an event may never cross a bar line and the score must end on a bar line (else error).

Rhythms: `q` Quarter notes (unit 12) · `e` Eighth notes (6) · `t` Triplets (4, tuplet 3) · `s` Sixteenth notes (3).
Patterns (UI names): `updown` Up and down · `up` Up only · `down` Down only · `groups3` Groups of 3 ·
`groups4` Groups of 4 · `thirds` Thirds (skip a note).

**`buildScaleScore({tonic, scaleId, shapeId, pattern, rhythm, range, tempo})`**
1. shape = `buildShape(tonic, scaleId, shapeId, 24)`; `neck` is rejected.
2. range `root` → `rootToRoot`, `full` → whole shape.
3. idx = `patternIndices(len, pattern)`; every index except the last becomes one note of the rhythm unit.
4. Pad with rests of the same unit until the next beat boundary (tick % 12 == 0).
5. The last index becomes one long note filling the rest of the bar (48/36/24/12 ticks).
6. title `"<Tonic> <scale name lower-case>"`, subtitle `"<shape name> - <pattern> - <rhythm lower-case>"`,
   keySig from the scale family.

**Songs** (`songs.js`): pitches as they **sound**; tokens `Note+octave[:duration][@string/fret]`, `r` = rest,
bars separated by `|`, every bar must equal 48 ticks. Position = `lowestPosition(midi)` unless given.
Five songs: Mary Had a Little Lamb (strings 1-2), Jingle Bells chorus (1-2), Ode to Joy (1-3),
Twinkle in G (1-3), Twinkle low in C (3-5). (Melodies were typed from memory — public domain.)

**`timeline(score)`** → `[{ i, beat = tick/12, beats = dur/12, rest, midis }]` for the transport.

## 9. Game data
- Note Quest levels (pools of string/fret positions): `Sources/GoldenCheck/Golden/game.json → questLevels` and `01_FEATURE_SPEC.md`.
- Jam progressions and strum patterns: `Sources/GoldenCheck/Golden/game.json → progressions, strums` and `01_FEATURE_SPEC.md`.
