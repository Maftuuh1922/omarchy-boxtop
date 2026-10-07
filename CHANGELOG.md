# Changelog

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
