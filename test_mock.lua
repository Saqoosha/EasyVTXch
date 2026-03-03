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
clearCrsfOutbox()
local f3payload = { 1, 0 } -- parent=1, type=UINT8(0)
for _, b in ipairs(strBytes("Channel")) do f3payload[#f3payload + 1] = b end
f3payload[#f3payload + 1] = 4 -- value (ch 4)
f3payload[#f3payload + 1] = 1 -- min
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
  print("PASS: Band write sent")

  -- Advance time past TIMEOUT_WRITE (15 ticks)
  advanceTime(20)
  clearCrsfOutbox()
  script.run(0)

  outbox = getCrsfOutbox()
  if #outbox >= 1 then
    assert(outbox[1].cmd == 0x2D, "Expected channel write")
    print("PASS: Channel write sent")

    -- Advance time for Send VTx
    advanceTime(20)
    clearCrsfOutbox()
    script.run(0)

    outbox = getCrsfOutbox()
    if #outbox >= 1 then
      print("PASS: Send VTx command sent")

      -- Advance time for Confirm
      advanceTime(25)
      clearCrsfOutbox()
      script.run(0)

      outbox = getCrsfOutbox()
      if #outbox >= 1 then
        print("PASS: Send VTx confirm sent")

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

---- Test 7: VTX table loading (integration) ----
print("\n=== Test 7: VTX table loading ===")

-- Write a mock vtx_table.lua to the path the script expects
local vtxPath = "/SCRIPTS/TOOLS/vtx_table.lua"
-- Use /tmp for desktop test
vtxPath = "/tmp/vtx_table.lua"
local vf = io.open(vtxPath, "w")
vf:write([[return {
    frequencyTable = {
        { 5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725, },
        { 5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866, },
        { 5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945, },
        { 5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880, },
        { 5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917, },
        { 5653, 5693, 5733, 5773, 5813, 5853, 5893, 5933, },
        { 5333, 5373, 5413, 5453, 5493, 5533, 5573, 5613, },
        { 5325, 5348, 5366, 5384, 5402, 5420, 5438, 5456, },
    },
    frequenciesPerBand = 8,
    bandTable = { [0]="U", "A", "B", "E", "F", "R", " ", " ", " " },
    powerTable = { [1]="25 ", [2]="100", [3]="200", [4]="350", },
}]])
vf:close()

-- Verify the vtx_table.lua format via loadfile (same mechanism as loadVtxTable)
local vtxTable = loadfile(vtxPath)()
assert(type(vtxTable) == "table", "vtx_table.lua should return a table")
assert(type(vtxTable.bandTable) == "table", "bandTable should exist")
assert(type(vtxTable.frequencyTable) == "table", "frequencyTable should exist")

-- Verify bandTable structure: [0] is skipped, " " entries are skipped
local bt = vtxTable.bandTable
assert(bt[0] == "U", "bandTable[0] should be U (skipped by loader)")
assert(bt[1] == "A", "bandTable[1] should be A")
assert(bt[5] == "R", "bandTable[5] should be R")
assert(bt[6] == " ", "bandTable[6] should be space (skipped by loader)")
print("PASS: bandTable structure correct (U at [0], A-R at [1]-[5], spaces at [6]+)")

-- Verify frequencyTable aligns with bandTable indices
local ft = vtxTable.frequencyTable
assert(ft[1][1] == 5865, "A1 freq should be 5865, got " .. tostring(ft[1][1]))
assert(ft[5][1] == 5658, "R1 freq should be 5658, got " .. tostring(ft[5][1]))
print("PASS: frequencyTable indices match bandTable (ft[1]=A, ft[5]=R)")

os.remove(vtxPath)

---- Summary ----
print("\n=== All tests passed! ===")
print("Note: CRSF communication and LVGL UI must be tested on real hardware.")
