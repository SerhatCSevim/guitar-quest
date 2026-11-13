# 06 — Proposed Swift / SwiftUI architecture

Status: this is the design written **before** the port. The implementation in `Sources/` follows it; where the
two differ (e.g. folder names, `Sources/GoldenCheck` instead of an XCTest target), the code wins.

## 1. Shape of the project
```
GuitarQuest/                      Xcode project, macOS app, SwiftUI life cycle
├─ Packages/MusicCore/            Swift package, NO UI, NO audio  ← port first, test against golden JSON
│  ├─ Sources/MusicCore/
│  │  ├─ Theory.swift             theory.js   (notes, scales, keys, chords, harmonize, positions)
│  │  ├─ Shapes.swift             theory.js   (shapeOptions, buildShape, rootToRoot, patternIndices)
│  │  ├─ Voicings.swift           chords.js   (OPEN table, E/A templates, voicingsFor, validate)
│  │  ├─ Score.swift              exercises.js (ticks, buildScaleScore, buildSongScore, timeline)
│  │  ├─ Songs.swift              songs.js
│  │  ├─ GameData.swift           quest LEVELS, jam PROGS/STRUMS, theory-game rules (pure parts)
│  │  └─ NotationLayout.swift     notation.js layout/prepare/beams (pure geometry, no drawing)
│  └─ Tests/MusicCoreTests/       golden/*.json as test resources + parity tests
├─ GuitarQuest/                   app target
│  ├─ App/        GuitarQuestApp.swift, AppModel (current screen, settings), Theme (colours, fonts)
│  ├─ Audio/      KarplusStrong.swift, AudioEngine.swift (AVAudioEngine), Transport.swift (scheduler)
│  ├─ Views/      FretboardView, NotationView (Canvas), ChordDiagramView, NoteBadge, common controls
│  ├─ Features/   Explore/, Quest/, Scales/, Studio/, Harmony/ (Library, Build, Families, Jam, TheoryGames), Progress/
│  ├─ Store/      ProgressStore.swift (Codable, same JSON as the web app), PracticeClock.swift
│  └─ Resources/  Assets.xcassets (AppIcon from img/icon-512.png → needs a 1024 px version), music font
└─ Docs/  (these documents)
```

## 2. JS → Swift mapping notes
| Web | Swift |
|---|---|
| `{l, a}` objects | `struct SpelledNote: Hashable, Codable { let letter: Int; let alter: Int }` |
| string ids (`'major'`, `'box1'`, `'maj'`) | `enum ScaleID: String`, `enum ShapeID`, `enum ChordType: String` — keep the same raw strings so golden keys match |
| `mod()` | a helper that returns a non-negative remainder (Swift `%` keeps the sign!) |
| `Math.round`, `floor` | use `.rounded()` / `floor`; check negative values (`octaveOf`) against golden data |
| `Math.random` | inject a random-number generator (seedable) so tests are deterministic |
| SVG strings | SwiftUI `Canvas` + `Path`; text with resolved `Text` in the graphics context |
| DOM events / hash routing | SwiftUI state; screen = enum in the app model |
| `localStorage` | JSON file in Application Support (see 05) |
| `setInterval` look-ahead | audio render callback or `scheduleBuffer(at:)` (see 04) |

Keep the JS function names as Swift method names where possible (`buildShape`, `harmonize`, `patternIndices` …)
so a reviewer can put both side by side.

## 3. UI
- One window, top segmented tab bar like the web app (a sidebar would be the alternative), minimum size about
  1100×750, opens maximised-friendly.
- Fretboard, notation and chord diagrams are custom drawings (`Canvas`), following 03_NOTATION_SPEC.md.
- Keyboard: Space play/pause, Esc stop (Studio); letters A–G answer in Note Quest; Enter = Next.
- Colours and texts exactly as in 01_FEATURE_SPEC.md (users of the web version already know them).
- Possible Mac extras later: menu bar commands, full-screen practice mode,
  microphone "play the note on your real guitar" mode.

## 4. Order of work
Rule: MusicCore + golden checks green **before** any UI.
