# Changelog

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
