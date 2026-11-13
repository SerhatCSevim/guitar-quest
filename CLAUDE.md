# Guitar Quest — instructions for AI coding assistants

Guitar-learning app (notes on the fretboard, tab ↔ note ↔ staff, scales, Guitar-Pro-style practice player, chords and
harmony). Two implementations of the same app: the web app in `web/` and a native macOS SwiftUI app in `Sources/`.
Details are in `docs/01`–`docs/08`.

## Source of truth
`web/js/*.js` > `Sources/GoldenCheck/Golden/*.json` > `docs/02_MUSIC_ENGINE_SPEC.md`, `docs/01_FEATURE_SPEC.md` > the
other docs. If a document and the code disagree, the code wins — and say so.
Change the music rules in the web engine first, regenerate the golden data
(`node web/tests/export_golden.js Sources/GoldenCheck/Golden`), then port the change to Swift.

## Layout
- `web/` — HTML/CSS/JS app, no dependencies, no build step. Tests: `node web/tests/run_tests.js`.
- `Sources/MusicCore` — pure Swift engine (theory, shapes, voicings, scores/exercises, songs, game data, notation
  layout). JS function names and string ids (`major`, `box1`, `maj`, `updown` …) are kept as they are.
- `Sources/GuitarQuest` — SwiftUI app: App/ (model, theme, snapshots), Audio/ (Karplus-Strong, transport),
  Views/ (fretboard, notation, chord diagram), Features/ (six screens), Store/ (progress.json, practice clock).
- `Sources/GoldenCheck` — parity checker (`swift run GoldenCheck`), including all 20,160 exercises.
- `scripts/build_app.sh` — makes `build/Guitar Quest.app` (`--install` moves it to /Applications).

## Product rules
- UI texts are **English and identical** in both versions.
- Correct enharmonic spelling everywhere (E♯ in F♯ major, E♭ in A blues). Tab orientation = fretboard orientation
  (thin e string on top). Written pitch is one octave above the sounding pitch. Keep the wrong-answer explanations
  word for word — they are the teaching.
- No third-party dependencies. No network access, no telemetry. The saved progress file has the same JSON shape as
  the web app's `guitarQuest.v1` storage entry (`docs/05`).

## Engineering rules
- In Swift always use `Theory.mod` instead of `%` (negative-safe). Randomness is injected so checks are repeatable.
- "Done" = it builds, `node web/tests/run_tests.js` and `swift run GoldenCheck` pass, and the affected screen was
  checked (by hand or with `GQ_SNAPSHOT_DIR`).
- Do not invent Apple API names; if unsure, compile and see. Mark anything unverified as unverified.
- Building from the command line needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when
  `xcode-select` points at the Command Line Tools (`scripts/build.sh` handles this).
- Tests and snapshots never write to the real user data folder (`~/Library/Application Support/GuitarQuest`).

## Working with the maintainer
- Be critical and name the risks; the maintainer decides. After every change, list which files changed and how.
- Commit or push only when asked.
