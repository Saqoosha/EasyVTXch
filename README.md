# EasyVTXch

Simplified VTX channel changer for EdgeTX + ELRS. One-tap VTX channel changing with favorites support.

ELRS VTX Admin requires 8-10 button presses to change a VTX channel (SYS → Tools → ELRS → wait → VTX Admin folder → Band → Channel → Power → Send). EasyVTXch reduces it to **2 steps**: launch script → tap channel.

## Features

- **One-tap channel switching** — tap any channel button to send VTX command immediately
- **Favorites** — long-press a channel to star it. Favorites appear at the top in a grid for quick access
- **All bands** — A, B, E, F, R, L bands with 8 channels each
- **Frequency display** — each channel button shows its frequency
- **Persistent state** — favorites and last selected band are saved across sessions
- **Color LCD UI** — LVGL-based UI for 480×272 color radios (TX16S, TX18S, etc.)
- **B&W fallback** — basic list UI for 128×64 monochrome radios

## Requirements

- EdgeTX 2.11+ (for LVGL widget support on color radios)
- ELRS TX module with VTX Admin support
- VTX that supports CRSF VTX control

## Installation

1. Copy `EasyVTXch.lua` to `/SCRIPTS/TOOLS/` on your EdgeTX SD card
2. On your radio: SYS → Tools → EasyVTXch

## Usage

### Color LCD (LVGL)
- **Tap a channel** → sends VTX band + channel + Send VTx command
- **Long-press a channel** → toggles favorite (shown with checked/highlighted background)
- **Tap a band button** (A/B/E/F/R/L) → switches the channel grid
- **Long-press a favorite** → removes it from favorites

### B&W LCD
- **Scroll** with encoder to navigate channels
- **Enter** to send VTX command
- **Long-press Enter** to toggle favorite
- **Menu** to cycle through bands

## File Format

Favorites and settings are stored in `/SCRIPTS/TOOLS/easyvtxch.fav`:

```
R1
R4
F3
band:R
```

Each line is either:
- `{Band}{Channel}` — a favorite entry (e.g., `R1`, `F3`)
- `band:{Band}` — last selected band (e.g., `band:R`)

## Development

### Testing on Desktop

```bash
# Run mock tests (requires Lua 5.4)
lua5.4 test_mock.lua
```

### Testing in EdgeTX Companion Simulator

1. Download [EdgeTX Companion](https://edgetx.org/companion) and set up a TX16S profile
2. Set SD card path to a directory with EdgeTX SD card content
3. Copy `EasyVTXch.lua` to `SCRIPTS/TOOLS/` in the SD card directory
4. **Important**: Delete `EasyVTXch.luac` after every code change — EdgeTX caches compiled bytecode and will ignore `.lua` updates if a stale `.luac` exists

### Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for internal architecture, CRSF protocol details, and EdgeTX LVGL lessons learned.

## License

MIT
