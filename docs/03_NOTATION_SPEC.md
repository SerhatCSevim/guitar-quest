# 03 — Notation renderer (staff + tab), Guitar-Pro style

Reference: `web/js/notation.js` (layout = pure functions, drawing = SVG strings) and
`chords.js → diagramSVG`. Golden structure: `Sources/GoldenCheck/Golden/notation.json`. Visual reference: screenshots 04, 05, 09.
All numbers are in SVG user units (≈ CSS px at 100 %).

## 1. Pitch → staff
- Written octave = sounding octave + 1 (see engine spec). Staff position `pos = octave·7 + letter − 30`;
  `y(pos) = staffTop + (8 − pos) · SP/2` with **SP = 10** (staff space). Lines at pos 0, 2, 4, 6, 8.
- Ledger lines: for pos ≤ −2 at −2, −4, … down to the note; for pos ≥ 10 at 10, 12, … up to the note
  (x ± 10 around the head).
- **Accidentals, bar by bar**: state is reset at each bar; for every head the "current" alteration of
  (letter, octave) is the bar state if set, else the key signature's alteration for that letter. If the note's
  alteration differs, print its sign (♮ for 0) and store it. (A blues: E♭ gets a ♭ once per bar; D major shows
  no accidentals because F♯/C♯ are in the key signature.)

## 2. Durations → glyphs (`noteValue`)
Triplet events are looked up with `dur × 1.5`.

| ticks | head | flags | dots |
|---|---|---|---|
| 48 | whole | 0 | 0 |
| 36 | half | 0 | 1 |
| 24 | half | 0 | 0 |
| 18 | black | 0 | 1 |
| 12 | black | 0 | 0 |
| 9 | black | 1 | 1 |
| 6 | black | 1 | 0 |
| 3 | black | 2 | 0 |

## 3. Horizontal layout
- Event width `w = 16 + 32·(dur/12)^0.55 (+9 if any head shows an accidental) (+4 if dotted)`.
- Measure width = `12 + Σw + 4`.
- System header width = clef (38 with staff, 30 tab-only) + key signature (`|fifths|·9.5 + 6` if any, staff only)
  + time signature (26, first system only, staff only) + 6. Margins: left 6, right 8.
- Packing: add measures to a system while they fit in `width − margins − header`; at least one per system.
- Stretch every system to the full width; exceptions: the last system of a multi-system score max ×1.35, a
  single-system score max ×1.6 (and that single system's SVG is only as wide as needed, so it can be centred).
- Inside a measure: start at `x + 12·scale`; each event occupies a slot of `w·scale`; the note head centre is
  `slotStart + 6 (+9 if an accidental is printed)`.

## 4. Vertical layout
- With staff: `staffTop = 52`, staff bottom = 92, `tabTop = staffBottom + 64` (if tab shown).
- Tab only: `tabTop = 30`. Tab line spacing **TS = 13**, string 1 at the top line.
- Note-name row (option): 22 below the lowest element. Tab-only rhythm row: 8 below, 30 high.
- System height = bottom + 16.

## 5. Staff elements
- Treble clef glyph U+1D11E (web: Segoe UI Symbol, 58 px), anchored so its baseline is 13 below the G line.
  **Mac: Segoe UI Symbol does not exist** — bundle a SMuFL music font (e.g. Bravura, SIL Open Font License;
  confirm the licence file when downloading) or draw the clef as a path.
- Key signature after the clef, 9.5 apart. Sharp positions F C G D A E B → pos `8 5 9 6 3 7 4`;
  flat positions B E A D G C F → pos `4 7 3 6 2 5 1`.
- Time signature "4/4", Georgia/Times bold 23 px, digits centred on pos 6 and pos 2 (+7.5 baseline).
- Accidental glyphs are **drawn paths** (no font): sharp = two verticals + two slanted thick bars; flat = stem +
  belly; natural = two offset verticals + bars. Placed at `x − 15` from the head centre.
- Note heads: ellipse rx 6.3, ry 4.6 rotated −22°. Black = filled; half = white fill, stroke 2; whole = rx 7.6,
  not rotated, stroke 2.6. Colour per note letter when "colours" is on (`--hc`).
- Seconds inside a chord: the upper note of a second is pushed to the other side of the stem (± 2·rx − 0.5).
- Dots: r 1.9 at `head x + rx + 5`; if the head sits on a line the dot moves up half a space.
- **Stems** length 34; direction: average pos ≥ 4 → down, else up. Up stem at `x + rx − 0.7`, from the lowest head
  to `min(highestHeadY − 34, y(4))` (always reaches the middle line). Down stem at `x − rx + 0.7`, from the highest
  head to `max(lowestHeadY + 34, y(4))`.
- Flags (single eighths/16ths): filled curved wedge from the stem end, second flag 7 further in.
- **Beams**: group consecutive non-rest eighth/16th events **inside the same beat** with the same tuplet value
  (a triplet beat = 3). Group direction from the average pos of all heads. Beam line from the first to the last
  stem: wanted ends = head ∓ 34, slope clamped to ±9/dx, then shifted so every stem is ≥ 27 long. Thickness
  4.6; 16th secondary beam 7.2 further in (a lone 16th gets an 8-unit stub).
- Triplet "3" (11 px italic bold) centred above/below the beam.
- Rests: whole = 12×5 block under line pos 6; half = 12×5 block on pos 4; quarter = zig-zag polyline (stroke 2.6);
  eighth/16th = dot(s) + slanted stroke(s).

## 6. Tab elements
- Six lines, "T A B" letters (900 weight, 15 px) at the left with a white halo so the lines don't cross them.
- Fret numbers 13 px bold, centred at the head x on the string line, on a white rectangle `7.5·digits + 3` wide,
  14 high (cuts the line).
- Note names row: letter names coloured per note.
- Tab-only mode shows rhythm under the tab: stems 24 (half notes 14, whole none), dots, flags pointing down,
  beams as 4-high bars (second bar for all-16th groups), triplet "3".

## 7. Bar lines, numbers, cursor, interaction
- Bar line at every measure end, from staff top to tab bottom; final bar = thin + thick (3.4) line.
- Bar numbers (10 px italic grey) above each bar — only when the score has more than one bar.
- Cursor: rounded rect 30 wide, orange 14 % fill + 45 % stroke, spanning staff top − 30 to the bottom; hidden
  until playback; moves to `x − 15` of the active event; the system scrolls into view.
- Active event: heads and tab number orange (`#E0672B`), tab number background `#FFF3EC`; the next event's tab
  number teal. Hover tint on each event slot; clicking a slot = seek playback to that event.

## 8. Chord diagram (`diagramSVG`)
- Base scale s = width/120; drawing width 132·s (room for the "Nfr" label).
- Strings 15·s apart starting at 22·s, frets 19·s high, ≥ 4 rows (`max(4, maxFret − base + 1)`).
- base fret = 1 if the highest fret ≤ 4, else the lowest fretted fret; nut line (5·s) only when base = 1, else
  "Nfr" label at the right of the first row.
- × above muted strings, ○ above open strings; dots r 7·s with finger numbers (white, 10.5·s); **root notes in
  red** (`#D64545`, open root ring red). Barre = rounded bar when finger 1 presses ≥ 2 strings at its lowest fret.
- Title (chord name) 19·s bold on top when given.

## 9. Fretboard component (`fretboard.js`)
- Width 1000 units: string-name column 26, open-string column 48, nut at 74; fret wires follow the real
  guitar rule `x(n) = nut + L·(1 − 2^(−n/12))` scaled so the last fret ends at 986.
- Strings 26 apart (21 compact), string 1 on top; wound strings 4–6 tinted; string thickness `0.9 + 0.42·(s−1)`.
- Inlays at 3 5 7 9 15 17 19 21, double at 12. Fret numbers below ("open", 1, 2 …; inlay frets bold).
- Rosewood gradient `#6b4423 → #4a2c15`, frets `#C8CBD0`, nut `#F4EBDC`.
- Marks: circle r 11.5 (9.5 compact) in note colour with label; kinds: note, root (extra white ring), ghost
  (28 % opacity, no label), ring (outline only), target (dashed outline, "?").
- Highlighted string: yellow band + yellow string. Flash animation on answers (green/red expanding ring).
