# EasyVTXch — Claude Code Instructions

## Project Overview
Single-file EdgeTX Lua script (`EasyVTXch.lua`) for simplified VTX channel changing via ELRS CRSF protocol. Color LCD (LVGL) + B&W fallback.

## Key Files
- `EasyVTXch.lua` — main script (goes in `/SCRIPTS/TOOLS/` on SD card)
- `test_mock.lua` — desktop Lua 5.4 mock tests for B&W mode and CRSF protocol
- `ARCHITECTURE.md` — internal architecture and protocol details

## Coding Rules

### Lua Style
- Use `local` for all variables and functions
- Use `string.find()`, `string.lower()`, `string.sub()` etc. — **NEVER use `:method()` syntax** on strings. EdgeTX Lua doesn't support string metatable methods reliably
- Use `type(x) == "table"` / `type(x) == "string"` guards before indexing unknown data
- Wrap risky operations in `pcall()` and display errors in `statusText`

### EdgeTX LVGL Rules (Critical)
- **NEVER use `box:clear()` + rebuild** — it doesn't work in EdgeTX LVGL
- **Use `text = function() return val end`** for dynamic text that changes every frame (status, subtitle)
- **Use `dirtyAll` flag + `lvgl.clear()` + `buildUi()` for structural changes** (favorite toggle, band switch) — this is the only reliable rebuild method
- **`checked` only accepts static booleans** — NOT functions. Set at build time
- **`active = function()` works** for dynamic enable/disable
- **`visible = function()` works** for dynamic show/hide
- **`set({text = ...})` works** on existing widgets for text updates
- **`set({checked = ...})` does NOT visually update** — must rebuild instead
- **Focus control is impossible** — no Lua API for focus. `NO_FOCUS` flag exists only in C++
- **`FLOW_ROW` doesn't auto-wrap** — create explicit rows for grid layouts
- Use explicit `x, y` positioning for page-level layout

### CRSF Protocol
- Field IDs are **dynamic** per firmware version — always discover by name, never hardcode
- Use `crossfireTelemetryPush`/`Pop` with nil-check wrappers (`crsfPush`/`crsfPop`)
- Handle `crossfireTelemetryPop` returning `false` (not just `nil`) — use `not cmd` instead of `cmd == nil`

### Deployment
- **Always delete `.luac` when updating `.lua`!** EdgeTX caches compiled bytecode
- Copy to simulator: `rm -f ~/Documents/EdgeTX_SD/SCRIPTS/TOOLS/EasyVTXch.luac && cp EasyVTXch.lua ~/Documents/EdgeTX_SD/SCRIPTS/TOOLS/`

## Testing
```bash
lua5.4 test_mock.lua
```
Tests cover: init ping, device info parsing, field enumeration, VTX send sequence, favorites file format. CRSF communication and LVGL UI must be tested on real hardware or EdgeTX Companion simulator.

## Font Constants
Use EdgeTX standard constants: `SMLSIZE`, `MIDSIZE`, `DBLSIZE`, `XXLSIZE`, `BOLD`, `INVERS`, `CENTER`
**NOT** `FONT_S`, `FONT_L`, `FONT_XS`, `FONT_STD` — these don't exist.
