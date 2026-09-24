# EasyVTXch — Claude Code Instructions

## Project Overview
EdgeTX Lua script for simplified VTX channel changing via ELRS CRSF protocol.

The tool script highlights the **current** VTX channel reported by ELRS (via VTX Admin Band/Channel field values, with a fallback to the VTX folder dynamic name when it includes `(B:ch:...)`). Color LCD uses LVGL button styling; B&W uses text prefixes (`>` current, `*` favorite).

## Key Files
- `EasyVTXch.lua` — main tool script (goes in `/SCRIPTS/TOOLS/` on SD card)
- `test_mock.lua` — desktop Lua 5.4 mock tests for B&W mode and CRSF protocol
- `ARCHITECTURE.md` — internal architecture and protocol details

## Runtime Files (on SD card)
- `/SCRIPTS/TOOLS/easyvtxch.fav` — favorites + last selected band
- `/SCRIPTS/TOOLS/easyvtxch.cache` — cached CRSF field IDs for fast startup

## Coding Rules

### Lua Style
- Use `local` for all variables and functions
- Use `string.find()`, `string.lower()`, `string.sub()` etc. — **NEVER use `:method()` syntax** on strings. EdgeTX Lua doesn't support string metatable methods reliably
- Use `type(x) == "table"` / `type(x) == "string"` guards before indexing unknown data
- Wrap risky operations in `pcall()` and display errors in `statusText`

### EdgeTX LVGL Rules (Critical)
- **NEVER use `box:clear()` + rebuild** — it doesn't work in EdgeTX LVGL
- **Use `text = function() return val end`** for dynamic text on labels (auto-updates every frame)
- **`page()` subtitle accepts static string ONLY** — NOT functions. Use `getCurrentText()` call, not reference
- **Use `dirtyAll` flag + `lvgl.clear()` + `buildUi()` for structural changes** (favorite toggle, band switch) — this is the only reliable rebuild method
- **`checked` only accepts static booleans** — NOT functions. Set at build time
- **`active = function()` works** for dynamic enable/disable
- **`visible = function()` works** for dynamic show/hide
- **`set({text = ...})` works** on existing widgets for text updates
- **`set({checked = ...})` does NOT visually update** — must rebuild instead
- **Focus control is impossible** — no Lua API for focus. `NO_FOCUS` flag exists only in C++
- **Use absolute `x, y` positioning** — `flexFlow` on page causes nested padding (each flex level adds 2px `PAD_OUTLINE`). `borderPad` and `PERCENT_SIZE` are unavailable in RM 3.0.0 build
- **No flex on page = body padding 0, body width = LCD_W**. Calculate `contentW = SW - MARGIN*2` and position buttons with `x = MARGIN + col * (btnW + PAD)`
- Use spacer label at bottom (`h = 1, text = ""`) to extend scrollable area for bottom margin
- **Button styling**: LVGL `button` supports `color` (background), `textColor`, and `font` (for example `BOLD`, `MIDSIZE`). EasyVTXch uses literal `BLACK` / `WHITE` for the current channel highlight.

### CRSF Protocol
- Field IDs are **dynamic** per firmware version — always discover by name, never hardcode
- **Field ID caching**: `easyvtxch.cache` stores discovered field IDs for fast startup. On cache hit, only the VTX folder ID is trusted; band/channel/send must be independently re-verified by early detection in `parseFieldData`. Never pre-set band/channel/send from cache — let `allVtxFieldsFound()` confirm them
- Use `crossfireTelemetryPush`/`Pop` with nil-check wrappers (`crsfPush`/`crsfPop`)
- Handle `crossfireTelemetryPop` returning `false` (not just `nil`) — use `not cmd` instead of `cmd == nil`
- **Channel values are 1-based** in ELRS CRSF (`min=1, max=8`). Use `field.min + (uiChannel - 1)` to convert from UI (1-8). The firmware internally converts to 0-based via `SetVtxChannel(arg - 1)`. Never hardcode the offset — use the `min` from CRSF enumeration
- **Band values are 1-based** TEXT_SELECTION indices (A=1, B=2, E=3, F=4, R=5)
- **Field names change between ELRS versions** — ELRS 4.x renamed `Band` → `Band/Enable`. Match children of the VTX folder through `isBandFieldName()`, never a literal `"band"`. To check names for a new ELRS release, read `src/lib/tx-crsf/TXModuleParameters.cpp` at that tag (3.x: `src/lib/LUA/tx_devLUA.cpp`). Symptom of a mismatch: "VTX fields incomplete"
- **Validate PARAM_RESP fieldId** before advancing write state — check `data[3]` matches the expected field

### Deployment
- **Always delete `.luac` when updating `.lua`!** EdgeTX caches compiled bytecode
- Tool script to simulator: `rm -f ~/Documents/EdgeTX_SD/SCRIPTS/TOOLS/EasyVTXch.luac && cp EasyVTXch.lua ~/Documents/EdgeTX_SD/SCRIPTS/TOOLS/`
- Tool script to real SD card (TX15): `rm -f /Volumes/TX15/SCRIPTS/TOOLS/EasyVTXch.luac && cp EasyVTXch.lua /Volumes/TX15/SCRIPTS/TOOLS/`
- **Always delete `.luac` AND copy `.lua` on ALL targets** — forgetting either causes stale code to run

## Testing
```bash
lua5.4 test_mock.lua
```
If `lua5.4` is not available, `lua test_mock.lua` is fine on environments where `lua` is Lua 5.x.

Tests cover: init ping, device info parsing, field enumeration, current-channel initialization (VTX folder dynName and Band/Channel field values), ELRS 4.x field names (`Band/Enable`), VTX send sequence (with value assertions for band/channel/send/confirm), favorites file format, and UI label/checked helper behavior. CRSF communication and LVGL UI must be tested on real hardware or EdgeTX Companion simulator.

## Font Constants
Use EdgeTX standard constants: `SMLSIZE`, `MIDSIZE`, `DBLSIZE`, `XXLSIZE`, `BOLD`, `INVERS`, `CENTER`
**NOT** `FONT_S`, `FONT_L`, `FONT_XS`, `FONT_STD` — these don't exist.
