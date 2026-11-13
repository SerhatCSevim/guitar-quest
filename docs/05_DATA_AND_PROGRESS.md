# 05 — Saved data, and moving progress from the web app to the Mac app

Reference: `web/js/store.js`, `js/app.js` (practice clock).

## 1. What is saved (one JSON document)
Web: browser `localStorage` key **`guitarQuest.v1`** inside the Edge app profile
(`%LOCALAPPDATA%\GuitarQuest\browser`). The Mac version should store the **same JSON shape** (e.g.
`~/Library/Application Support/GuitarQuest/progress.json`), so the Windows file can be imported unchanged.

```json
{
  "settings": { "naming": "letters", "accidentals": "sharp", "colors": true, "volume": 0.8 },
  "quest": {
    "levels":    { "tab:s12": { "stars": 3, "best": 115, "plays": 2 } },
    "positions": { "2:3": { "seen": 4, "correct": 3, "recent": [1, 0, 1, 1] } },
    "answered": 12, "correct": 10, "bestStreak": 6
  },
  "theory":   { "answered": 5, "correct": 4, "best": { "triad:easy": 3 } },
  "practice": { "2026-10-23": 754 }
}
```

| field | meaning |
|---|---|
| `settings.naming` | `letters` \| `solfege` \| `both` |
| `settings.accidentals` | `sharp` \| `flat` \| `both` (how unspelled black-key notes are named) |
| `quest.levels["<game>:<level>"]` | game ∈ `tab`, `staff`, `hunt`; level ∈ `s12 s34 s56 first sharps bass neck master`; best stars (max), best score (max), plays |
| `quest.positions["<string>:<fret>"]` | every Note Quest answer about that position; `recent` = last 5 results (1/0) |
| `quest.bestStreak` | longest run of correct answers |
| `theory.best["<game>:<level>"]` | best streak per theory game (`steps scale triad family keysig` × `easy medium hard`) |
| `practice["YYYY-MM-DD"]` | seconds practised that local day |

Defaults are merged under whatever is loaded (unknown fields are kept). Saving is debounced 250 ms and flushed
when the window closes.

## 2. Practice clock
Runs while at least one of: a Note Quest round (`quest`), the Studio player (`studio`), the Jam player (`jam`) is
active. Ticks every 5 s; the elapsed seconds are added to today's entry (stored rounded) each time ≥ 15 s have
accumulated and when everything stops (also on screen change and on window close).

## 3. Moving progress from the web app to the Mac app  (not tested yet)
Steps on the Windows PC (only needed if progress exists there):
1. Open Guitar Quest from the desktop icon.
2. Press **F12** (or Ctrl+Shift+I) to open the developer tools, choose **Console**.
3. Type `copy(localStorage.getItem('guitarQuest.v1'))` and press Enter (the progress JSON is now on the clipboard).
4. Paste into a text editor and save it as `guitarquest-progress.json`.

If the developer tools do not open in the app window, the web app has no other export path yet
(an **Export progress** button would be a small addition).

Mac side: Settings → **Import progress…** → choose the JSON → validate (same shape as above) →
if the Mac has no progress yet, replace; otherwise ask "Replace / Keep Mac progress".
**Export progress…** on the Mac writes the same format (useful for backups).
