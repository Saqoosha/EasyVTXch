# EasyVTXch Architecture

## Overview

Single-file Lua script for EdgeTX that provides one-tap VTX channel changing via ELRS CRSF protocol. The script discovers VTX Admin fields dynamically, presents a channel grid UI, and sends band/channel/send commands in sequence.

## Script Structure

```
EasyVTXch.lua
├── [1] Constants          — CRSF addresses, frame types, field types, bands, frequencies
├── [2] State              — CRSF state machine, pending writes, UI state
├── [3] Favorites          — Load/save favorites + selected band to .fav file
├── [4] CRSF Communication — Ping, field enumeration, field parsing, nil-safe wrappers
├── [5] VTX Commander      — Sequential band→channel→send→confirm write sequence
├── [6] CRSF Processing    — Main loop: pop messages, handle timeouts
├── [7] LVGL UI            — Color LCD widget tree (480×272)
├── [8] B&W Fallback       — Monochrome LCD list UI (128×64)
└── [9] init / run         — Entry points returned to EdgeTX
```

## CRSF Protocol

### Addresses
| Constant | Value | Description |
|----------|-------|-------------|
| `CRSF_ADDR_MODULE` | `0xEE` | TX module (ELRS) |
| `CRSF_ADDR_LUA` | `0xEF` | Lua script (handset) |
| `CRSF_ADDR_RADIO` | `0xEA` | Radio |

### Frame Types
| Constant | Value | Direction | Description |
|----------|-------|-----------|-------------|
| `CMD_PING` | `0x28` | Script → Module | Discover device |
| `CMD_DEVICE_INFO` | `0x29` | Module → Script | Device name + field count |
| `CMD_PARAM_RESP` | `0x2B` | Module → Script | Field data (may be chunked) |
| `CMD_PARAM_READ` | `0x2C` | Script → Module | Request field by ID |
| `CMD_PARAM_WRITE` | `0x2D` | Script → Module | Write field value |

### Field Types
| Type | Value | Used For |
|------|-------|----------|
| `UINT8` | `0` | Channel number |
| `TEXT_SELECTION` | `9` | Band selection (Off/A/B/E/F/R) |
| `FOLDER` | `11` | VTX Administrator folder |
| `COMMAND` | `13` | Send VTx button |

### Device Info Response (0x29)
```
data[1] = dest address
data[2] = source address (device ID, expect 0xEE)
data[3..] = device name (null terminated)
then: serial(4B) + hw_ver(4B) + sw_ver(4B) + field_count(1B) + param_version(1B)
```
Field count is at `offset + 12` where offset is the byte after the null terminator of device name.

### Param Response (0x2B)
```
data[1] = dest
data[2] = source (device ID)
data[3] = field ID
data[4] = chunks remaining (0 = last chunk)
data[5+] = field payload (accumulated across chunks)
```

### Field Payload Format
```
byte[0] = parent field ID (0 = root)
byte[1] = type | (hidden << 7)
byte[2+] = name (null terminated)
... type-specific data follows
```

Type-specific data:
- **TEXT_SELECTION (9)**: options string (null terminated, semicolon-separated), value, min, max
- **UINT8 (0)**: value, min, max
- **FOLDER (11)**: optional dynamic name (null terminated) e.g. `"(R:4:2:P)"`
- **COMMAND (13)**: status, timeout, info string

### VTX Admin Dynamic Name
The VTX Administrator folder's dynamic name encodes current state:
```
"(R:4:2:P)" = Band:R, Channel:4, Power:2, PitMode:P
```
Parsed with: `string.match(dynName, "%((%a):(%d+)")`

## State Machine

```
IDLE → PINGING → ENUMERATING → READY ⇄ SENDING
                                  ↓
                                ERROR
```

### PINGING
- Send `CMD_PING` with `{0x00, CRSF_ADDR_RADIO}`
- Wait for `CMD_DEVICE_INFO` response
- Timeout: 3s, retry up to 5 times → ERROR "TX module not found"

### ENUMERATING
- Request each field via `CMD_PARAM_READ` with `{deviceId, handsetId, fieldId, chunkIndex}`
- Accumulate chunked responses in `crsf.chunkBuf`
- Parse field data and store in `crsf.fields[fieldId]`
- After all fields: find VTX Admin folder and children **by name** (field IDs are dynamic!)

### READY
- UI is interactive, channel/fav/band buttons enabled
- Tap triggers SENDING sequence

### SENDING (4-step sequence)
```
WRITING_BAND  → write band value (1-based: A=1..R=5) → wait 150ms or response
WRITING_CHAN  → write channel (field.min + ch-1, typically 0-based) → wait 150ms or response
WRITING_SEND  → write Send VTx (start) → wait 200ms or response
CONFIRMING    → write Send VTx (confirm) → wait 200ms or response → READY
```

Each step: `CMD_PARAM_WRITE` with `{deviceId, handsetId, fieldId, value}`

Channel value conversion: `field.min + (uiChannel - 1)` where `field.min` is discovered during enumeration. ELRS uses 0-based (`min=0, max=7`) but the script adapts dynamically.

Band value: 1-based TEXT_SELECTION index (A=1, B=2, E=3, F=4, R=5).

Send VTx values:
- `LCS_START = 1` — initiate send
- `LCS_CONFIRMED = 4` — confirm send

### PARAM_RESP Validation
During the SENDING sequence, incoming `CMD_PARAM_RESP` messages are validated: the response's `fieldId` (data[3]) must match the field being written (band/channel/send) before advancing to the next state. This prevents unrelated responses from accidentally progressing the state machine.

## LVGL UI Architecture

### Widget Tree
```
page (title="EasyVTXch", subtitle=dynamic currentText)
├── label (statusText, dynamic)
├── favBox (FLOW_COLUMN, only if favorites exist)
│   └── row(s) (FLOW_ROW, 4 buttons per row)
│       └── button × N (static text, active=isReady)
├── bandBox (FLOW_ROW)
│   └── button × 5 (A/B/E/F/R, checked=selected, active=isReady)
├── chanBox (FLOW_COLUMN)
│   ├── row1 (FLOW_ROW)
│   │   └── button × 4 (ch 1-4, static text, checked=isFavorite, active=isReady)
│   └── row2 (FLOW_ROW)
│       └── button × 4 (ch 5-8, static text, checked=isFavorite, active=isReady)
└── retryButton (visible when ERROR state)
```

### Rebuild Strategy
The UI uses a **full rebuild** approach via `dirtyAll` flag:

1. Band switch or favorite toggle sets `dirtyAll = true`
2. In `run()`, if `dirtyAll`: call `lvgl.clear()` then `buildUi()`
3. All widget properties (`checked`, `text`) are computed fresh at build time
4. Dynamic text functions (`text = function()`) used only for continuously changing values (statusText, subtitle via `getCurrentText()`)

**Why not partial updates:**
- `box:clear()` doesn't work in EdgeTX LVGL
- `btn:set({checked = ...})` doesn't visually update
- `btn:set({text = ...})` works but `checked` doesn't → inconsistent
- Full `lvgl.clear()` + rebuild is the only reliable method

**Tradeoff:** Focus resets to first element on rebuild. Focus control is not available in EdgeTX Lua API.

### Performance Optimizations
- **`favLookup`**: Hash table `{ ["R1"]=true, ... }` rebuilt on favorite change for O(1) `isFavorite()` lookups
- **`bandDirty`**: Defers `saveFavorites()` to script exit instead of saving on every band switch (reduces flash wear)
- **`bwItemsDirty`**: Caches B&W mode item list, invalidated only on band switch or favorite toggle (avoids per-frame allocation)
- **`getCurrentText()`**: Derived function instead of cached state variable (eliminates stale state risk)
- **`writeParam()`**: Helper that consolidates `crsfPush` + state transition + timer reset

### CRSF Nil-Safety
```lua
local function crsfPush(cmd, data)
  if crossfireTelemetryPush then
    return crossfireTelemetryPush(cmd, data)
  end
  return nil
end

local function crsfPop()
  if crossfireTelemetryPop then
    return crossfireTelemetryPop()
  end
  return nil
end
```
Required because simulator may not have CRSF functions defined.

### String Method Safety
EdgeTX Lua does NOT reliably support string metatable methods (`:find()`, `:lower()`, etc.).
Always use explicit library calls: `string.find(s, pattern)`, `string.lower(s)`, etc.

## Favorites File Format

Path: `/SCRIPTS/TOOLS/easyvtxch.fav`

```
R1
R4
F3
band:R
```

- Lines matching `^[A-Z][1-8]$` are favorites
- Line matching `^band:[A-Z]$` stores the last selected band
- Written with EdgeTX `io.write(f, str)` API (not standard Lua `f:write()`)
- Read with `io.read(f, 128)` in chunks (EdgeTX doesn't support `*all` or `*line`)

## VTX Frequency Table

| Band | Ch1  | Ch2  | Ch3  | Ch4  | Ch5  | Ch6  | Ch7  | Ch8  |
|------|------|------|------|------|------|------|------|------|
| A    | 5865 | 5845 | 5825 | 5805 | 5785 | 5765 | 5745 | 5725 |
| B    | 5733 | 5752 | 5771 | 5790 | 5809 | 5828 | 5847 | 5866 |
| E    | 5705 | 5685 | 5665 | 5645 | 5885 | 5905 | 5925 | 5945 |
| F    | 5740 | 5760 | 5780 | 5800 | 5820 | 5840 | 5860 | 5880 |
| R    | 5658 | 5695 | 5732 | 5769 | 5806 | 5843 | 5880 | 5917 |

## Band Values (CRSF)

ELRS TEXT_SELECTION options: `"Off;A;B;E;F;R"`
- Off=0, A=1, B=2, E=3, F=4, R=5

## Timeouts

| Constant | Value | Description |
|----------|-------|-------------|
| `TIMEOUT_PING` | 300 (3s) | Wait for device info |
| `TIMEOUT_ENUM` | 100 (1s) | Wait per field response |
| `TIMEOUT_WRITE` | 15 (150ms) | Between band/channel writes |
| `TIMEOUT_SEND` | 20 (200ms) | For send command + confirm |
| `RETRY_MAX` | 5 | Max ping retries |

`getTime()` returns 10ms ticks.
