# 01 — Feature specification (what the app does, screen by screen)

Reference: `web/js/views/*.js` (one file per screen), screenshots in `screenshots/`.
Audience: young beginners who learn guitar from **tab** and are also starting to read standard notation.
UI language: **English only**. Default note names: **C D E** (settings also offer Do Re Mi / both).

## 0. App shell
- Top bar: logo (orange guitar pick) + "Guitar Quest"; six tabs: **Fretboard · Note Quest · Scales ·
  Practice Studio · Chords & Harmony · My Progress**; settings (gear) button on the right.
- Settings panel: Note names (`C D E` / `Do Re Mi` / `Both`), Black-key notes (`C♯` / `D♭` / `C♯/D♭`),
  Note colours (On/Off), Volume slider 0–1. Changing a setting re-renders the current screen.
  Footer text: "Progress is saved in this browser on this computer only." (Mac: "on this Mac").
- Sound starts after the first click/key (browser rule; on Mac there is no such limit).
- One colour per note letter, used everywhere (fretboard dots, staff note heads, tab names, buttons):
  C `#E53935` · D `#F57C00` · E `#E8B100` (dark text on it) · F `#43A047` · G `#0097A7` · A `#5E35B1` ·
  B `#D81B60` · any sharp/flat `#546E7A`.
- Practice clock: counts seconds while a Note Quest round, the Studio player or the Jam player is running;
  stored per day (see `05_DATA_AND_PROGRESS.md`).
- Design tokens (CSS `:root`): background `#F6F2EA`, card `#FFFFFF`, ink `#1E2230`, muted `#697083`,
  accent `#E0672B`, teal `#11808A`, good `#2E9E5B`, bad `#D64545`, gold `#F2B705`, radius 14.

## 1. Fretboard Explorer (`explore.js`) — screenshot 01
Goal: connect **fretboard position ↔ note name ↔ tab number ↔ staff note**.
- Fretboard 0–15 frets, **high e on top** (same orientation as tab). Clicking a fret plays the note and selects it.
- Toolbar: *Show note names* (Hidden / Natural notes / All notes); *Find every…* letter buttons C…B (toggle;
  shows every position of that pitch class); *Walk up a string* buttons `6 E … 1 e` (plays frets 0→12 of that
  string, 0.32 s apart, lighting each fret; then selects fret 12).
- Selected note: big coloured badge (black keys show both names), "String n (X string) · fret f",
  "Tab number: f on line n from the top", letter name if naming ≠ letters; "The very same note (same sound) is
  also here:" chips for unison positions (click = select them). Unison positions get ring marks on the board.
- "Tab and staff" card: one bar, whole note, treble clef, key of C, staff + tab + note name.
  Caption: guitar music is written one octave higher than it sounds.
- "How to find it" card: ladder of chips from the open string up to the fret (fret ≤ 7); for frets 8–12 count
  back from fret 12 ("Fret 12 is the open-string note again"); above 12 count up from 12. Tip text: E–F and B–C are
  one fret apart (shown when the ladder crosses them) else "One fret = one half step…".
- "The musical alphabet" card: C D E F G A B C chips with "2 frets"/"1 fret" between; a one-octave piano
  (click key → find that pc on the fretboard and play it).
- Default selection on first open: string 3, fret 2 (A).

## 2. Note Quest (`quest.js`) — screenshots 02, 06, 07
Lobby: three game cards, round mode (**10 questions** / **60-second blitz**), "Also show the staff" (Tab game only),
eight level cards (number, name, hint, 3 stars, best score, Play).

| # | id | Name | Positions (string: frets) | Accidentals | fretboard max |
|---|---|---|---|---|---|
| 1 | s12 | Strings 1 & 2 | 1,2: 0,1,3 | no | 12 |
| 2 | s34 | Strings 3 & 4 | 3: 0,2 · 4: 0,2,3 | no | 12 |
| 3 | s56 | Strings 5 & 6 | 5: 0,2,3 · 6: 0,1,3 | no | 12 |
| 4 | first | First position | all strings, frets 0–3, natural notes | no | 12 |
| 5 | sharps | Sharps and flats | all strings, frets 0–4, every note | yes | 12 |
| 6 | bass | Bass strings up the neck | strings 5–6, frets 0–12, naturals | no | 15 |
| 7 | neck | Whole neck | all strings, frets 0–12, naturals | no | 15 |
| 8 | master | Fretboard master | all strings, frets 0–12, every note | yes | 15 |

(Exact pools: `Sources/GoldenCheck/Golden/game.json → questLevels`.)

Games:
- **Tab → Note**: big 6-line tab (string labels e B G D A E at the left, the asked string drawn darker, fret
  number in an orange box). Answer pad: 7 natural buttons (or 12 for accidental levels, black keys labelled
  `C♯/D♭`), coloured per note. Keyboard: letters A–G answer (non-accidental levels); Enter/Space = Next.
  Optional small staff next to the tab.
- **Staff → Fretboard**: a whole note on the staff (key of C; black-key notes randomly spelled ♯ or ♭); click
  the fretboard; **any position with exactly that pitch is correct**. Same letter but wrong octave → wrong, with
  "Right letter, wrong octave!" explanation.
- **Note Hunt**: "Find [X] on string n (Y)"; the string is highlighted; any fret on that string with that pitch
  class is correct. Clicking another string only shows a toast ("Use string n…"), no penalty.

Flow and scoring:
- Question choice is weighted: never the same position twice in a row; weight = 2 if the position has no history,
  else `1 + 3·(1 − accuracy of its last 5 answers)`.
- Correct: +10, +5 more if streak ≥ 3, only 5 if a hint was used. Plays the note, marks it, cheer text
  ("Great!", "Yes!", "Correct!", "Nice one!", "Super!", "You got it!") + explanation; auto-next after 1.3 s
  (blitz 0.65 s).
- Wrong: streak reset, right answer shown (pad button outlined green, positions marked on the board), the right
  note is played, explanation (e.g. "Not A. String 2 is B. Count up 3 frets: C, C♯, D. So it is D.");
  **Next** button (blitz: auto-next after 1.6 s).
- Hint (once per question): Tab game lights the ladder from open (or fret 12) to a "?" target; Staff game reveals
  the note name; Hunt shows the other natural notes on that string.
- Blitz timer 60 s, paused while feedback is shown.
- End screen: stars — round: accuracy ≥ 90% → 3, ≥ 70% → 2, ≥ 50% → 1; blitz: correct ≥ 20 → 3, ≥ 12 → 2,
  ≥ 6 → 1. Message, score, correct/answered, best streak, "Notes to practise" (up to 4 most-missed positions),
  buttons Play again / Next level / All levels. Best stars and best score are saved per game+level.
- Every answer is stored per position (`string:fret`) for the progress map.

## 3. Scales (`scales.js`) — screenshot 03
- Scale: Major / Minor / Major pentatonic / Minor pentatonic / Blues; Key: 12 chips (minor keys shown with `m`);
  Shape: dropdown from `shapeOptions`; Dots show: Note names / Scale steps / Nothing.
- Fretboard (max fret = max(15, shape max + 1)): shape notes bright (roots with a white ring), all other scale
  notes on the neck faint and unlabeled; clicking any fret plays it.
- **Hear it**: plays the shape up and down in eighth notes at 110 BPM, highlighting the playing dot; button
  toggles to Stop. **Practise in the Studio →** opens the Studio with this scale/key/shape (disabled for Whole neck).
- Info: the notes with degree labels and step badges between them (W, H, W+H) plus the octave; the written
  scale (one octave root-to-root, eighths, staff + tab; Whole neck uses Shape 1 / Open position);
  "Good to know" facts (key signature, relative key, scale facts, shape facts).

## 4. Practice Studio (`studio.js`) — screenshots 04, 05
The Guitar-Pro-like player.
- Source: **Scale exercise** (Scale, Key, Shape, Pattern, Rhythm, Range: Root to root / Whole shape — default
  Whole shape for pentatonic/blues, Root to root otherwise) or **Song** (5 song cards with string range tag).
  Songs cap the tempo at the song's own tempo when loaded.
- Transport bar: Play/Pause (Space), Stop (Esc), Loop; Tempo −5 / slider 30–220 / +5 and "N BPM"; toggles Click
  (metronome), Count-in (one bar), Guitar (sound on/off — off = the student plays along); Speed trainer: each loop
  +2/+5/+10 up to a target BPM (only while Loop is on; toast "Speed trainer: N BPM"); view Staff + Tab / Tab /
  Staff; Note names (letter names under the tab, coloured).
- Score: title + subtitle; wrapped systems; orange cursor bar on the current event; current notes orange in
  staff and tab, next tab number teal; auto-scroll; click any note to start from there; big count-down number
  (4, 3, 2, 1) over the score during count-in.
- Fretboard under the score: every note of the exercise faint; current note solid with ring; next note as a ring.
- Defaults: A minor pentatonic, Shape 1, Up and down, eighths, Whole shape, 80 BPM, loop/click/count-in/guitar on,
  names on.

## 5. Chords & Harmony (`harmony.js`) — screenshots 08–12
Sub-tabs:
1. **Chord library** — Open chords (groups: Major, Minor (+ Bm barre), Seventh, Minor seventh, Major seventh,
   sus2, sus4), Barre chords (root chips; E-shape and A-shape for maj, min, 7, m7, sus4, maj7), Power chords.
   Click a diagram → strum + detail card: big diagram, tones with degree labels, formula, buttons Strum /
   Up-strum / One string at a time, explanation, staff + tab of the exact voicing.
2. **Build a chord** — root chips (major key names) × type (Major, Minor, Diminished, Augmented, sus 2nd, sus 4th,
   7th, Major 7th, Minor 7th). Step 1 the root's major scale with chosen steps highlighted (altered steps show
   "lower 1 fret"/"raise 1 fret" and the new note); Step 2 formula → notes, one explanation sentence per type;
   chord detail; Step 3 compact fretboard with all chord tones (labels R, 3, ♭3, 5 …).
3. **Chord families** — Major/Minor keys (major: C G D A E F B♭; minor: A E B D G C F♯), 3-note / 7th chords;
   intro text with the I-IV-V pattern; 7 cards (roman numeral coloured by quality, chord name, quality, small
   diagram; click = strum + detail); "Famous chord progressions in this key" with **Jam →** buttons.
4. **Jam along** — progression, key, strum pattern; Play/Stop, tempo 40–160 (default 72), Click, Guitar;
   current chord big diagram + next chord small; strum slots with arrows and counts `1 & 2 & 3 & 4 &`, the
   current slot orange; timeline of bars with chord + roman numeral. Loops with a count-in.
   Progressions: Three-chord song I-IV-V-I · Pop song I-V-vi-IV · 1950s song I-vi-IV-V · Jazz ii7-V7-Imaj7 ·
   12-bar blues I7×4 IV7×2 I7×2 V7 IV7 I7 V7 · Minor song i-iv-V-i (major V) · Epic minor i-VI-III-VII.
   Keys: major C G D A E F; minor A E D B. Strum patterns over 8 eighth slots: One strum per bar `D-------` ·
   Four down-strums `D-D-D-D-` · Down, down-up, up-down-up `D-DU-UDU` (default) · Down-up all the way
   `DUDUDUDU` · Rock `D-D-DUDU`. Each strum lasts until the next slot; beat-1 strum is louder.
5. **Theory games** — five games × Easy/Medium/Hard, score and streak, best streak saved:
   Half & whole steps (12 note buttons, enharmonics accepted, a strip of neighbouring frets as help) ·
   Scale steps ("In D major, what is note number 6?" — answer must be correctly spelled: accidental toggle
   ♭/♮/♯ + letter) · Build the chord (pick the 3 spelled notes; easy maj/min, medium + dim, hard + aug) ·
   Chord families (which chord is IV / which numeral is Em; 4 options) · Key signatures (how many ♯/♭; which key
   has …). Keys: easy C G F D; medium C G D A E F B♭ E♭; hard all 12. Correct → next after 1.7 s; wrong → answer +
   explanation + Next.

## 6. My Progress (`progress.js`) — screenshot 13
Stat cards: minutes today, this week (7 days), practice streak (consecutive days with ≥ 60 s; today counts only
once it has ≥ 60 s), notes answered, % correct, best answer streak. Bar chart of the last 14 days (bars reaching
15 min are green). Fretboard map frets 0–12: colour by the last-5 accuracy (≥ 0.8 green, ≥ 0.5 orange, else red,
grey = never asked). Stars table (levels × games), theory-games summary, "Reset all progress" (confirmation).

## 7. Things any port must NOT lose
- Correct enharmonic spelling everywhere (E♯ in F♯ major, B♭ in F minor…).
- Tab orientation = fretboard orientation (high e on top).
- Written pitch one octave above sounding pitch.
- The explanations after wrong answers (they are the teaching).
- Adaptive question choice and the per-position map.
