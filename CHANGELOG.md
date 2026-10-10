# Changelog

## v1.5.0 — 2026-10-10

Liquid glass and a built-in updater.

- **Liquid glass look**, flat and gradient-free: translucent card, boxes,
  chips, sliders and bar pill share one set of glass tokens — flat tint,
  1 px hairline border, 1 px top highlight, rounded corners
- **Glass styles**: `regular` (adaptive frosted), `clear` (high
  transparency), `dark` (smoked), `tinted` (coloured by the accent) and
  `solid` (opaque, no blur — accessibility)
- **Contrast guard**: text colour and glass opacity are solved so every
  label clears WCAG 4.5:1 against the glass over both the theme background
  and the wallpaper's average colour; secondary labels never dim below that
- **Blur behind** (opt-in): writes an Omarchy Hyprland toggle file
  (`~/.local/state/omarchy/toggles/hypr/boxtop-glass.lua`) with a layer
  blur rule for the panel and the chosen strength; removed when turned off
- **Accent**: 14 presets (incl. the Omarchy theme accent), custom hex, or
  3–5 swatches extracted from the current wallpaper (Pillow → ImageMagick →
  theme colours fallback). A manual pick turns "from wallpaper" off
- **Sliders** with live preview: blur, glass opacity, tint, corner radius,
  scale (80–130 %), title/subtitle size, process count
- Settings reorganised into tabs: glass · colour · layout · header · data ·
  presets
- **Presets**: save/export to `~/.config/boxtop/presets/*.json`, import a
  file, delete, and two-tap "reset to defaults"; settings are mirrored to
  `~/.config/boxtop/settings.json` and restored after a reinstall
- Popup position (under the icon / centred), network units (bytes / bits),
  temperature (°C / °F), box order from settings (drag & drop still works)
- Spring animations (card pop, chips, sliders, box moves) with a
  reduced-motion option that follows Omarchy's animation toggle
- Meters and graphs are flat by default (solid level colours); the old btop
  gradients are still available as `gradients: true`
- **Built-in updater** (`updater.py`): checks the latest GitHub release (or
  `VERSION` / new commits on `main` when there are no releases) at start-up
  and every 6 h with a cache, shows a dot on the bar pill and an "Update
  available vX → vY" row with release notes; "update now" fast-forwards a
  git install or swaps in the release tarball with a backup, validates,
  rolls back on failure, notifies and reloads the shell. Can be switched off
- New `VERSION` file; `update_check.py` replaced by `updater.py`
- New IPC: `glass`, `accent`, `checkUpdate`, `update`, `reset`,
  `savePreset`, `loadPreset`
- Default box frames are now glass boxes (`stroke: false`); set
  `stroke: true` for btop outlines
- The sampler is unchanged (no extra per-tick work)

## v1.4.0 — 2026-10-07

Hero banner, fonts and layout.

- Hero banner: upload a custom image, pick its crop from nine anchor points
  and let it run full-bleed across the card. The header (title, photo, ⚙)
  sits directly on the banner instead of a separate strip
- The banner dissolves into the card: colour drains toward the bottom
  (desaturation ramp) before the background takes over, so it merges cleanly
  on dark and light themes
- Profile photo upload with its own crop position
- Title customization: custom text, bundled fonts (pixel / bebas / anton /
  mono), upload any TTF/OTF, or pick any installed system font
- Title size (16–46 px) changes only the text — banner and photo keep their
  size. Subtitle size and a box text scale (normal / small / tiny)
- Portrait or landscape card, compact density, drag & drop box reordering
- The net box charts live traffic: up / down rates, totals and peak scale
- Update notice: the card tells you when a newer release is on GitHub and
  updates in place (runs `omarchy plugin update`, then restarts the shell)
- Closing the card commits any pending edit and folds the settings panel away
- New IPC commands: `pickAvatar`, `pickHero`, `pickFont`

## v1.3.0 — 2026-10-07

Customization.

- New ⚙ settings menu inside the card. Changes apply instantly and are saved
  to `shell.json`
- Colour presets: `theme` (follows the active Omarchy theme), `btop`,
  `catppuccin`, `nord`, `mono`
- Graph styles: `dots`, `bars`, `line`
- Show or hide each box (cpu, mem, net, proc)
- Compact size, rounded or sharp corners, 1–3 px border thickness
- Stroke or no-stroke boxes: btop outlines, or soft filled panels
- btop-style fade on the process list
- Optional soft shadow
- Adjustable refresh interval (1–10 s) and process count (3–15)
- New IPC commands: `preset <name>`, `graph <style>`, `set <key> <json>`
- CPU box height adapts to the number of cores

Performance:

- The sampler now runs as one long-lived process while the card is open
  (stopped on close) and streams a JSON line per tick. No more Python start-up
  every refresh
- CPU usage (overall, per-core, per-process) is a delta against the previous
  tick. The two 150 ms sleeps per sample are gone
- The process scan reads only `/proc/PID/stat`; usernames are resolved only
  for the rows shown, and cached
- One sample: ~500 ms → ~14 ms CPU. Total plugin cost with the card open:
  ~36 → ~15 ms of CPU per second on a Celeron N4020
- Graph grid is drawn once on a separate canvas; dots are batched per row
  (one fill per colour band instead of one per dot)
- Box frames repaint only when their layout changes, not on every value update
- Meter width animation removed, so the blurred card isn't re-rendered at
  60 fps after each tick

## v1.2.0 — 2026-10-07

First public release.

- Bar chip icon that opens a btop-style popup card
- **cpu** box: per-core gradient meters, temperature, frequency, CPU model
  (detected automatically), dot-matrix usage history, uptime and load average
- **mem** box: RAM history graph plus Used / Cached / Swap / Disk gradient meters
- **net** box: total bytes received and sent
- **proc** box: top 8 processes by live CPU %, with PID and memory
- Rounded btop-style box frames with tab titles, divider labels and footers
- Data is sampled every 2 s only while the card is open; when it's closed,
  nothing runs
- Only dependency is `python3`; reads `/proc` and `/sys` directly
