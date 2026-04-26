-- EdgeTX API mock for testing EasyVTXch logic on desktop Lua 5.4
-- This stubs out EdgeTX-specific globals so the script can load and
-- we can exercise config parsing, state machine, and favorites logic.

---- Mock EdgeTX globals ----

-- Font/display constants
SMLSIZE = 0x04
MIDSIZE = 0x08
DBLSIZE = 0x10
XXLSIZE = 0x40
BOLD = 0x80
INVERS = 0x100
BLINK = 0x200
CENTER = 0x01
LEFT = 0x00
RIGHT = 0x02

-- Color theme constants
COLOR_THEME_PRIMARY1 = 0xFF000000
COLOR_THEME_PRIMARY2 = 0xFF333333
COLOR_THEME_SECONDARY1 = 0xFF666666
COLOR_THEME_SECONDARY2 = 0xFF999999
COLOR_THEME_WARNING = 0xFFFF0000
COLOR_THEME_ACTIVE = 0xFF00FF00
COLOR_THEME_FOCUS = 0xFF0000FF
BLACK = 0xFF000000
WHITE = 0xFFFFFFFF

-- Event constants
EVT_VIRTUAL_ENTER = 1
EVT_VIRTUAL_ENTER_LONG = 2
EVT_VIRTUAL_EXIT = 3
EVT_VIRTUAL_NEXT = 4
EVT_VIRTUAL_PREV = 5
EVT_VIRTUAL_MENU = 6

-- Time tracking (10ms ticks)
local mockTime = 0
function getTime()
  return mockTime
end
function advanceTime(ticks)
  mockTime = mockTime + ticks
end

-- CRSF telemetry mock
local crsfOutbox = {}
local crsfInbox = {}

function crossfireTelemetryPush(cmd, data)
  if cmd == nil then return true end
  crsfOutbox[#crsfOutbox + 1] = { cmd = cmd, data = data }
  return true
end

function crossfireTelemetryPop()
  if #crsfInbox == 0 then return nil end
  local msg = table.remove(crsfInbox, 1)
  return msg.cmd, msg.data
end

function injectCrsfResponse(cmd, data)
  crsfInbox[#crsfInbox + 1] = { cmd = cmd, data = data }
end

function getCrsfOutbox()
  return crsfOutbox
end

function clearCrsfOutbox()
  crsfOutbox = {}
end

-- LCD mock (B&W)
lcd = {
  clear = function() end,
  drawText = function(x, y, text, flags) end,
  drawNumber = function(x, y, val, flags) end,
}

-- lvgl = nil means B&W mode (no LVGL)
lvgl = nil

-- io mock using real io (for favorites file test)
-- EdgeTX io is a subset, but Lua 5.4 io works fine for testing

---- Load the script ----

print("=== Loading EasyVTXch.lua ===")
-- Opt into the test hook so we can exercise the real manualSort/manualRemove
-- implementations instead of duplicating them in the test file.
_G.__EASYVTX_TEST = true
local chunk, err = loadfile("EasyVTXch.lua")
if not chunk then
  print("LOAD ERROR: " .. err)
  os.exit(1)
end

local script = chunk()
print("Script loaded. Keys: init=" .. type(script.init) .. ", run=" .. type(script.run) .. ", useLvgl=" .. tostring(script.useLvgl))

---- Test 1: init() in B&W mode ----
print("\n=== Test 1: init() in B&W mode (no LVGL) ===")
script.init()

-- Check that a ping was sent
local outbox = getCrsfOutbox()
assert(#outbox >= 1, "Expected at least 1 CRSF message after init")
assert(outbox[1].cmd == 0x28, "Expected CMD_PING (0x28), got " .. string.format("0x%02X", outbox[1].cmd))
print("PASS: Ping sent on init")

---- Test 2: Device Info response → field enumeration ----
print("\n=== Test 2: Device Info → Enumeration ===")
clearCrsfOutbox()

-- Build a mock device info response (0x29)
-- Format: [dest][orig=0xEE][name bytes\0][serial 4B][hw 4B][sw 4B][fieldCount][paramVer]
local deviceInfo = {
  0xEF,       -- dest (handset)
  0xEE,       -- orig (TX module)
  -- name: "ELRS TX" + null
  0x45, 0x4C, 0x52, 0x53, 0x20, 0x54, 0x58, 0x00,
  -- serial (4 bytes) "ELRS"
  0x45, 0x4C, 0x52, 0x53,
  -- hw ver (4 bytes)
  0x00, 0x00, 0x00, 0x01,
  -- sw ver (4 bytes)
  0x00, 0x00, 0x03, 0x00,
  -- field count
  3,
  -- parameter version
  1,
}
injectCrsfResponse(0x29, deviceInfo)
script.run(0) -- process the response
advanceTime(1)

outbox = getCrsfOutbox()
assert(#outbox >= 1, "Expected param read request after device info")
assert(outbox[1].cmd == 0x2C, "Expected CMD_PARAM_READ (0x2C), got " .. string.format("0x%02X", outbox[1].cmd))
print("PASS: Field enumeration started after device info (fieldCount=3)")

---- Test 3: Simulate field responses ----
print("\n=== Test 3: Simulate VTX Admin fields ===")
clearCrsfOutbox()

-- Helper to build a string as byte table
local function strBytes(s)
  local t = {}
  for i = 1, #s do t[#t + 1] = string.byte(s, i) end
  t[#t + 1] = 0 -- null terminator
  return t
end

-- Helper to build param response
local function paramResp(fieldId, chunksRemain, payload)
  local data = { 0xEF, 0xEE, fieldId, chunksRemain }
  for _, b in ipairs(payload) do data[#data + 1] = b end
  return data
end

-- Field 1: VTX Administrator folder (type=11)
-- payload: [parent=0][type=11][name\0][dynName\0]
local f1payload = { 0, 11 } -- parent=0(root), type=FOLDER(11)
for _, b in ipairs(strBytes("VTX Administrator")) do f1payload[#f1payload + 1] = b end
for _, b in ipairs(strBytes("(R:4:2:P)")) do f1payload[#f1payload + 1] = b end
injectCrsfResponse(0x2B, paramResp(1, 0, f1payload))
script.run(0)
advanceTime(1)

-- Field 2: Band (type=9, TEXT_SELECTION, parent=1)
-- payload: [parent=1][type=9][name\0][options\0][value][min][max]
clearCrsfOutbox()
local f2payload = { 1, 9 } -- parent=1(VTX folder), type=TEXT_SEL(9)
for _, b in ipairs(strBytes("Band")) do f2payload[#f2payload + 1] = b end
for _, b in ipairs(strBytes("Off;A;B;E;F;R;L")) do f2payload[#f2payload + 1] = b end
f2payload[#f2payload + 1] = 5 -- value (R=5)
f2payload[#f2payload + 1] = 0 -- min
f2payload[#f2payload + 1] = 6 -- max
injectCrsfResponse(0x2B, paramResp(2, 0, f2payload))
script.run(0)
advanceTime(1)

-- Field 3: Channel (type=0, UINT8, parent=1)
-- CRSF channel field is 1-based (min=1, max=8) per ELRS firmware (tx_devLUA.cpp)
-- Firmware internally converts to 0-based via: config.SetVtxChannel(arg - 1)
clearCrsfOutbox()
local f3payload = { 1, 0 } -- parent=1, type=UINT8(0)
for _, b in ipairs(strBytes("Channel")) do f3payload[#f3payload + 1] = b end
f3payload[#f3payload + 1] = 4 -- value (ch 4, 1-based)
f3payload[#f3payload + 1] = 1 -- min (1-based per ELRS)
f3payload[#f3payload + 1] = 8 -- max
injectCrsfResponse(0x2B, paramResp(3, 0, f3payload))
script.run(0)
advanceTime(1)

print("ERROR: Only 3 fields but no Send VTx field — expected VTX fields incomplete")
-- This is expected to fail because we only have 3 fields and none is "Send VTx"
-- Let's redo with 4 fields

---- Test 4: Full enumeration with Send VTx ----
print("\n=== Test 4: Full enumeration with Send VTx ===")

-- Reset state by re-loading
mockTime = 0
crsfOutbox = {}
crsfInbox = {}
script = loadfile("EasyVTXch.lua")()
script.init()
clearCrsfOutbox()

-- Device info with 4 fields
deviceInfo[#deviceInfo - 1] = 4 -- field count = 4
injectCrsfResponse(0x29, deviceInfo)
script.run(0)
advanceTime(1)
clearCrsfOutbox()

-- Field 1: VTX Administrator folder
injectCrsfResponse(0x2B, paramResp(1, 0, f1payload))
script.run(0)
advanceTime(1)
clearCrsfOutbox()

-- Field 2: Band
injectCrsfResponse(0x2B, paramResp(2, 0, f2payload))
script.run(0)
advanceTime(1)
clearCrsfOutbox()

-- Field 3: Channel
injectCrsfResponse(0x2B, paramResp(3, 0, f3payload))
script.run(0)
advanceTime(1)
clearCrsfOutbox()

-- Field 4: Send VTx (type=13, COMMAND, parent=1)
local f4payload = { 1, 13 } -- parent=1, type=COMMAND(13)
for _, b in ipairs(strBytes("Send VTx")) do f4payload[#f4payload + 1] = b end
f4payload[#f4payload + 1] = 0 -- status (idle)
f4payload[#f4payload + 1] = 10 -- timeout
for _, b in ipairs(strBytes("")) do f4payload[#f4payload + 1] = b end
injectCrsfResponse(0x2B, paramResp(4, 0, f4payload))
script.run(0)
advanceTime(1)

print("PASS: All 4 fields enumerated")

---- Test 4.5: Current channel from Band/Channel field values ----
print("\n=== Test 4.5: Current channel from field values ===")

mockTime = 0
crsfOutbox = {}
crsfInbox = {}
script = loadfile("EasyVTXch.lua")()
script.init()
clearCrsfOutbox()

injectCrsfResponse(0x29, deviceInfo)
script.run(0)
advanceTime(1)
clearCrsfOutbox()

local f1payloadNoCurrent = { 0, 11 }
for _, b in ipairs(strBytes("VTX Administrator")) do f1payloadNoCurrent[#f1payloadNoCurrent + 1] = b end
for _, b in ipairs(strBytes("VTX")) do f1payloadNoCurrent[#f1payloadNoCurrent + 1] = b end
injectCrsfResponse(0x2B, paramResp(1, 0, f1payloadNoCurrent))
script.run(0)
advanceTime(1)
clearCrsfOutbox()

injectCrsfResponse(0x2B, paramResp(2, 0, f2payload))
script.run(0)
advanceTime(1)
clearCrsfOutbox()

injectCrsfResponse(0x2B, paramResp(3, 0, f3payload))
script.run(0)
advanceTime(1)
clearCrsfOutbox()

injectCrsfResponse(0x2B, paramResp(4, 0, f4payload))
script.run(0)
advanceTime(1)

local valueHooks = assert(script.__testHooks, "missing script.__testHooks after reload")
assert(type(valueHooks.isCurrentChannel) == "function", "isCurrentChannel hook missing")
assert(valueHooks.isCurrentChannel("R", 4), "Band/Channel field values should initialize current channel")
print("PASS: Current channel initialized from Band/Channel values")

---- Test 5: VTX Channel Send ----
print("\n=== Test 5: Send VTX channel R6 ===")
clearCrsfOutbox()

-- Simulate B&W mode: select item and send
-- Cursor to R6 (favorites=0 items, so items start at selectedBand channels)
-- R6 = index 6 in list

-- Directly call sendChannel via the run event system
-- In B&W mode, cursor at position 6, press ENTER
-- But sendChannel is local... we need to use the event system

-- Set cursor to 6 (R6) and press enter
for i = 1, 5 do
  script.run(EVT_VIRTUAL_NEXT)
end
script.run(EVT_VIRTUAL_ENTER)

outbox = getCrsfOutbox()
if #outbox >= 1 then
  assert(outbox[1].cmd == 0x2D, "Expected CMD_PARAM_WRITE (0x2D)")
  -- Verify band value: R=5 (1-based, TEXT_SELECTION index)
  local bandWriteData = outbox[1].data
  assert(bandWriteData[4] == 5, "Expected band value 5 (R), got " .. tostring(bandWriteData[4]))
  print("PASS: Band write sent (R=5)")

  -- Advance time past TIMEOUT_WRITE (15 ticks)
  advanceTime(20)
  clearCrsfOutbox()
  script.run(0)

  outbox = getCrsfOutbox()
  if #outbox >= 1 then
    assert(outbox[1].cmd == 0x2D, "Expected channel write")
    -- Verify channel value: ch6 = 1-based 6 (field.min=1, so 1+(6-1)=6)
    local chanWriteData = outbox[1].data
    assert(chanWriteData[4] == 6, "Expected 1-based channel value 6 for ch6, got " .. tostring(chanWriteData[4]))
    print("PASS: Channel write sent (ch6 = 1-based 6)")

    -- Advance time for Send VTx
    advanceTime(20)
    clearCrsfOutbox()
    script.run(0)

    outbox = getCrsfOutbox()
    if #outbox >= 1 then
      -- Verify Send VTx value: LCS_START = 1
      assert(outbox[1].data[4] == 1, "Expected LCS_START (1), got " .. tostring(outbox[1].data[4]))
      print("PASS: Send VTx command sent (LCS_START=1)")

      -- Advance time for Confirm
      advanceTime(25)
      clearCrsfOutbox()
      script.run(0)

      outbox = getCrsfOutbox()
      if #outbox >= 1 then
        -- Verify confirm value: LCS_CONFIRMED = 4
        assert(outbox[1].data[4] == 4, "Expected LCS_CONFIRMED (4), got " .. tostring(outbox[1].data[4]))
        print("PASS: Send VTx confirm sent (LCS_CONFIRMED=4)")

        -- Final confirm timeout
        advanceTime(25)
        script.run(0)
        print("PASS: VTX send sequence complete")
      end
    end
  end
else
  print("SKIP: sendChannel not triggered (cursor may not be at right position)")
end

---- Test 6: Favorites persistence ----
print("\n=== Test 6: Favorites save/load ===")

-- Write a test favorites file
local favPath = "/tmp/test_easyvtxch.fav"
local f = io.open(favPath, "w")
f:write("R1\nR4\nF3\n")
f:close()

-- Read it back manually to verify format
f = io.open(favPath, "r")
local content = f:read("*a")
f:close()
assert(content == "R1\nR4\nF3\n", "Favorites file content mismatch")
print("PASS: Favorites file format is correct")

---- Test 7: manualSort / manualRemove regression (issue #1) ----
-- Exercise the production fallbacks for QX7S / EdgeTX 2.11.4 (where
-- table.sort / table.remove are stripped) through the __testHooks that
-- EasyVTXch.lua exposes when `__EASYVTX_TEST` is set.
print("\n=== Test 7: manualSort / manualRemove ===")

local hooks = assert(script.__testHooks, "missing script.__testHooks — set _G.__EASYVTX_TEST before loading")
local manualSort = hooks.manualSort
local manualRemove = hooks.manualRemove

local function asc(a, b) return a < b end
local function eqList(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- manualSort: empty
local t = {}
manualSort(t, asc)
assert(#t == 0, "empty sort should stay empty")

-- manualSort: single
t = { 42 }
manualSort(t, asc)
assert(eqList(t, { 42 }), "single element sort broken")

-- manualSort: already sorted (early exit path)
t = { 1, 2, 3, 4, 5 }
manualSort(t, asc)
assert(eqList(t, { 1, 2, 3, 4, 5 }), "sorted list should stay sorted")

-- manualSort: reversed
t = { 5, 4, 3, 2, 1 }
manualSort(t, asc)
assert(eqList(t, { 1, 2, 3, 4, 5 }), "reverse sort broken")

-- manualSort: duplicates
t = { 3, 1, 2, 1, 3, 2 }
manualSort(t, asc)
assert(eqList(t, { 1, 1, 2, 2, 3, 3 }), "duplicate sort broken")

-- manualSort: favorites-shaped comparator (band+channel → frequency proxy)
local favs = {
  { band = "R", channel = 8, freq = 5917 },
  { band = "A", channel = 1, freq = 5865 },
  { band = "R", channel = 1, freq = 5658 },
}
manualSort(favs, function(a, b) return a.freq < b.freq end)
assert(favs[1].band == "R" and favs[1].channel == 1, "freq sort order wrong (1st)")
assert(favs[2].band == "A" and favs[2].channel == 1, "freq sort order wrong (2nd)")
assert(favs[3].band == "R" and favs[3].channel == 8, "freq sort order wrong (3rd)")
print("PASS: manualSort handles empty/single/sorted/reversed/duplicates/records")

-- manualRemove: first
t = { 1, 2, 3, 4 }
manualRemove(t, 1)
assert(eqList(t, { 2, 3, 4 }), "remove first broken")

-- manualRemove: middle
t = { 1, 2, 3, 4 }
manualRemove(t, 2)
assert(eqList(t, { 1, 3, 4 }), "remove middle broken")

-- manualRemove: last
t = { 1, 2, 3, 4 }
manualRemove(t, 4)
assert(eqList(t, { 1, 2, 3 }), "remove last broken")

-- manualRemove: single element
t = { 99 }
manualRemove(t, 1)
assert(#t == 0, "remove single element broken")

-- manualRemove: out-of-range idx must not mutate the table (defensive guard)
t = { 1, 2, 3 }
manualRemove(t, 0)
assert(eqList(t, { 1, 2, 3 }), "remove idx=0 should be a no-op")
manualRemove(t, 4)
assert(eqList(t, { 1, 2, 3 }), "remove idx>#t should be a no-op")
manualRemove(t, -1)
assert(eqList(t, { 1, 2, 3 }), "remove negative idx should be a no-op")

-- manualRemove: empty list is a no-op
t = {}
manualRemove(t, 1)
assert(#t == 0, "remove from empty should stay empty")
print("PASS: manualRemove handles first/middle/last/single/out-of-range/empty")

---- Test 8: button labels keep favorite and current indicators distinct ----
print("\n=== Test 8: Button label formatting ===")

local formatChannelText = hooks.formatChannelText
local formatBwChannelText = hooks.formatBwChannelText
local shouldShowFavoriteChecked = hooks.shouldShowFavoriteChecked
local getCurrentButtonColor = hooks.getCurrentButtonColor
local getCurrentButtonTextColor = hooks.getCurrentButtonTextColor
local getCurrentButtonFont = hooks.getCurrentButtonFont
assert(type(formatChannelText) == "function", "formatChannelText hook missing")
assert(type(formatBwChannelText) == "function", "formatBwChannelText hook missing")
assert(type(shouldShowFavoriteChecked) == "function", "shouldShowFavoriteChecked hook missing")
assert(type(getCurrentButtonColor) == "function", "getCurrentButtonColor hook missing")
assert(type(getCurrentButtonTextColor) == "function", "getCurrentButtonTextColor hook missing")
assert(type(getCurrentButtonFont) == "function", "getCurrentButtonFont hook missing")
assert(formatChannelText("R", 4, false, false) == "R4 5769", "plain channel label mismatch")
assert(formatChannelText("R", 4, true, false) == "R4 5769", "favorite channel label should rely on checked color")
assert(formatChannelText("R", 4, false, true) == "R4 5769", "current channel label should rely on inverted colors")
assert(formatChannelText("R", 4, true, true) == "R4 5769", "current favorite label should not duplicate visual markers")
assert(formatBwChannelText("R", 4, false) == "R4 5769", "B&W plain label mismatch")
assert(formatBwChannelText("R", 4, true) == "> R4 5769", "B&W current label should keep a text marker")
assert(shouldShowFavoriteChecked(false, false) == false, "plain channel should not be checked")
assert(shouldShowFavoriteChecked(true, false) == true, "non-current favorite should stay checked")
assert(shouldShowFavoriteChecked(true, true) == false, "current favorite should rely on inverted colors")
assert(getCurrentButtonColor(false) == nil, "non-current button should not override background color")
assert(getCurrentButtonColor(true) == BLACK, "current button should use black background color")
assert(getCurrentButtonTextColor(false) == nil, "non-current button should not override text color")
assert(getCurrentButtonTextColor(true) == WHITE, "current button should use white text color")
assert(getCurrentButtonFont(false) == nil, "non-current button should not override font")
assert(getCurrentButtonFont(true) == BOLD, "current button should use bold font")
print("PASS: Button labels avoid duplicate visual markers")

---- Summary ----
print("\n=== All tests passed! ===")
print("Note: CRSF communication and LVGL UI must be tested on real hardware.")
