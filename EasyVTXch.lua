-- toolName = "TNS|EasyVTXch|TNE"
--
-- EasyVTXch - Simplified VTX Channel Changer for EdgeTX + ELRS
-- One-tap VTX channel changing with favorites support.
-- Requires: EdgeTX 2.11+ (LVGL) for color UI, ELRS TX module
--
-- Usage:
--   Tap a channel button to send VTX command immediately.
--   Long-press a channel button to toggle favorite.
--   Favorites appear at the top for quick access.

---- [1] Constants ----

local CRSF_ADDR_MODULE = 0xEE
local CRSF_ADDR_LUA    = 0xEF
local CRSF_ADDR_RADIO  = 0xEA

local CMD_PING        = 0x28
local CMD_DEVICE_INFO = 0x29
local CMD_PARAM_RESP  = 0x2B
local CMD_PARAM_READ  = 0x2C
local CMD_PARAM_WRITE = 0x2D

local TYPE_UINT8      = 0
local TYPE_TEXT_SEL   = 9
local TYPE_FOLDER     = 11
local TYPE_COMMAND    = 13

local LCS_START     = 1
local LCS_CONFIRMED = 4

local BAND_NAMES = { "A", "B", "E", "F", "R" }
local BAND_VALUES = { A = 1, B = 2, E = 3, F = 4, R = 5 }

local FREQ = {
  A = { 5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725 },
  B = { 5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866 },
  E = { 5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945 },
  F = { 5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880 },
  R = { 5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917 },
}

local FAV_PATH = "/SCRIPTS/TOOLS/easyvtxch.fav"

local TIMEOUT_PING = 300   -- 300 * 10ms = 3s
local TIMEOUT_ENUM = 100   -- 100 * 10ms = 1s per field
local TIMEOUT_WRITE = 15   -- 15 * 10ms = 150ms between writes
local TIMEOUT_SEND  = 20   -- 20 * 10ms = 200ms for send command
local RETRY_MAX = 5

---- [2] State ----

local State = {
  IDLE          = 0,
  PINGING       = 1,
  ENUMERATING   = 2,
  READY         = 3,
  WRITING_BAND  = 4,
  WRITING_CHAN   = 5,
  WRITING_SEND  = 6,
  CONFIRMING    = 7,
  ERROR         = 8,
}

local crsf = {
  state        = State.IDLE,
  deviceId     = CRSF_ADDR_MODULE,
  handsetId    = CRSF_ADDR_LUA,
  fieldCount   = 0,
  fields       = {},
  loadIdx      = 0,
  chunkBuf     = {},
  chunkIdx     = 0,

  vtxFolderId    = nil,
  bandFieldId    = nil,
  channelFieldId = nil,
  sendFieldId    = nil,

  currentBand    = nil,
  currentChannel = nil,

  timer      = 0,
  retryCount = 0,
}

local pending = { band = nil, channel = nil }
local statusText = "Connecting..."
local selectedBand = "R"
local favorites = {}
local favLookup = {}  -- { ["R1"]=true, ... } for O(1) lookup
local exitScript = false
local dirtyAll = false
local bwItemsDirty = true  -- invalidate B&W item cache

---- [3] Favorites Persistence ----

local function rebuildFavLookup()
  favLookup = {}
  for _, fav in ipairs(favorites) do
    favLookup[fav.band .. fav.channel] = true
  end
end

local function loadFavorites()
  favorites = {}
  local f = io.open(FAV_PATH, "r")
  if not f then
    rebuildFavLookup()
    return
  end
  local buf = ""
  while true do
    local chunk = io.read(f, 128)
    if not chunk or #chunk == 0 then break end
    buf = buf .. chunk
  end
  io.close(f)
  for line in string.gmatch(buf .. "\n", "([^\r\n]+)") do
    if string.sub(line, 1, 5) == "band:" then
      local b = string.upper(string.sub(line, 6, 6))
      if BAND_VALUES[b] then selectedBand = b end
    else
      local b = string.upper(string.sub(line, 1, 1))
      local c = tonumber(string.sub(line, 2))
      if BAND_VALUES[b] and c and c >= 1 and c <= 8 then
        favorites[#favorites + 1] = { band = b, channel = c }
      end
    end
  end
  rebuildFavLookup()
end

local function saveFavorites()
  local f = io.open(FAV_PATH, "w")
  if not f then return end
  for _, fav in ipairs(favorites) do
    io.write(f, fav.band .. tostring(fav.channel) .. "\n")
  end
  io.write(f, "band:" .. selectedBand .. "\n")
  io.close(f)
  bandDirty = false
end

local function isFavorite(band, ch)
  return favLookup[band .. ch] == true
end

local function toggleFavorite(band, ch)
  local key = band .. ch
  local wasAdded
  if favLookup[key] then
    for i, fav in ipairs(favorites) do
      if fav.band == band and fav.channel == ch then
        table.remove(favorites, i)
        break
      end
    end
    wasAdded = false
  else
    favorites[#favorites + 1] = { band = band, channel = ch }
    wasAdded = true
  end
  rebuildFavLookup()
  bwItemsDirty = true
  saveFavorites()
  return wasAdded
end

---- [4] CRSF Communication ----

local findVtxFields
local refreshUi

local function getFreq(band, ch)
  local t = FREQ[band]
  if t and ch >= 1 and ch <= 8 then return t[ch] end
  return 0
end

local function fieldGetString(data, offset)
  local s = ""
  local i = offset
  while data[i] and data[i] ~= 0 do
    s = s .. string.char(data[i])
    i = i + 1
  end
  return s, i + 1
end

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

local function sendPing()
  crsfPush(CMD_PING, { 0x00, CRSF_ADDR_RADIO })
  crsf.timer = getTime()
  crsf.state = State.PINGING
  statusText = "Connecting..."
end

local function requestField(fieldId)
  crsf.loadIdx = fieldId
  crsf.chunkBuf = {}
  crsf.chunkIdx = 0
  crsfPush(CMD_PARAM_READ, {
    crsf.deviceId, crsf.handsetId, fieldId, 0
  })
  crsf.timer = getTime()
end

local function requestNextField()
  if crsf.loadIdx >= crsf.fieldCount then
    findVtxFields()
    return
  end
  requestField(crsf.loadIdx + 1)
end

local function parseDeviceInfo(data)
  if not data or #data < 3 then return end
  local srcId = data[2]
  if srcId ~= CRSF_ADDR_MODULE then return end
  crsf.deviceId = srcId

  local _, offset = fieldGetString(data, 3)
  if offset + 12 <= #data then
    crsf.fieldCount = data[offset + 12]
  else
    crsf.fieldCount = 0
  end

  if crsf.fieldCount == 0 then
    statusText = "No fields found"
    crsf.state = State.ERROR
    return
  end

  statusText = "Loading fields..."
  crsf.state = State.ENUMERATING
  crsf.loadIdx = 0
  crsf.fields = {}
  requestNextField()
end

local function parseFieldData(fieldId, d)
  if type(d) ~= "table" or #d < 3 then return end
  local field = { id = fieldId }
  local i = 1

  field.parent = d[i]; i = i + 1
  if field.parent == 0 then field.parent = nil end

  local rawType = d[i]; i = i + 1
  field.type = rawType % 128
  field.hidden = rawType >= 128

  field.name, i = fieldGetString(d, i)

  if field.type == TYPE_TEXT_SEL then
    field.options, i = fieldGetString(d, i)
  end
  if field.type == TYPE_TEXT_SEL or field.type == TYPE_UINT8 then
    if i <= #d then field.value = d[i]; i = i + 1 end
    if i <= #d then field.min = d[i]; i = i + 1 end
    if i <= #d then field.max = d[i]; i = i + 1 end
  elseif field.type == TYPE_FOLDER then
    if i <= #d and d[i] ~= 0 then
      field.dynName, i = fieldGetString(d, i)
    end
  elseif field.type == TYPE_COMMAND then
    if i <= #d then field.status = d[i]; i = i + 1 end
    if i <= #d then field.timeout = d[i]; i = i + 1 end
    if i <= #d then field.info, i = fieldGetString(d, i) end
  end

  crsf.fields[fieldId] = field
end

local function parseParamInfo(data)
  if not data or #data < 5 then return end
  if data[2] ~= crsf.deviceId then return end

  local fieldId = data[3]
  local chunksRemain = data[4]

  for i = 5, #data do
    crsf.chunkBuf[#crsf.chunkBuf + 1] = data[i]
  end

  if chunksRemain > 0 then
    crsf.chunkIdx = crsf.chunkIdx + 1
    crsfPush(CMD_PARAM_READ, {
      crsf.deviceId, crsf.handsetId, fieldId, crsf.chunkIdx
    })
    crsf.timer = getTime()
    return
  end

  parseFieldData(fieldId, crsf.chunkBuf)
  statusText = "Loading... " .. fieldId .. "/" .. crsf.fieldCount
  requestNextField()
end

findVtxFields = function()
  for id, f in pairs(crsf.fields) do
    if type(f) == "table" and f.type == TYPE_FOLDER
       and type(f.name) == "string" and string.find(f.name, "VTX") then
      crsf.vtxFolderId = id
      if type(f.dynName) == "string" then
        local b, c = string.match(f.dynName, "%((%a):(%d+)")
        if b and c then
          crsf.currentBand = b
          crsf.currentChannel = tonumber(c)
        end
      end
      break
    end
  end

  if not crsf.vtxFolderId then
    statusText = "VTX Admin not found"
    crsf.state = State.ERROR
    return
  end

  for id, f in pairs(crsf.fields) do
    if type(f) == "table" and f.parent == crsf.vtxFolderId then
      local n = type(f.name) == "string" and string.lower(f.name) or ""
      if n == "band" then
        crsf.bandFieldId = id
      elseif n == "channel" then
        crsf.channelFieldId = id
      elseif string.find(n, "send") then
        crsf.sendFieldId = id
      end
    end
  end

  if not (crsf.bandFieldId and crsf.channelFieldId and crsf.sendFieldId) then
    statusText = "VTX fields incomplete"
    crsf.state = State.ERROR
    return
  end

  crsf.state = State.READY
  statusText = "Ready"
  refreshUi()
end

local function getCurrentText()
  if crsf.currentBand and crsf.currentChannel then
    local freq = getFreq(crsf.currentBand, crsf.currentChannel)
    return crsf.currentBand .. crsf.currentChannel .. " " .. freq .. "MHz"
  end
  return ""
end

refreshUi = function()
  dirtyAll = true
end

---- [5] VTX Commander ----

local function writeParam(fieldId, value, nextState)
  crsfPush(CMD_PARAM_WRITE, {
    crsf.deviceId, crsf.handsetId, fieldId, value
  })
  crsf.state = nextState
  crsf.timer = getTime()
end

local function sendChannel(band, ch)
  if crsf.state ~= State.READY then return end
  local bandVal = BAND_VALUES[band]
  if not bandVal then return end

  pending.band = band
  pending.channel = ch
  statusText = "Setting " .. band .. ch .. "..."
  writeParam(crsf.bandFieldId, bandVal, State.WRITING_BAND)
end

local function continueApply()
  if crsf.state == State.WRITING_BAND then
    -- Convert UI channel (1-8) to CRSF value using discovered field.min
    -- ELRS field is 1-based (min=1, max=8); firmware converts internally
    local chanField = crsf.fields[crsf.channelFieldId]
    local chanMin = (chanField and chanField.min) or 0
    writeParam(crsf.channelFieldId, chanMin + (pending.channel - 1), State.WRITING_CHAN)
  elseif crsf.state == State.WRITING_CHAN then
    writeParam(crsf.sendFieldId, LCS_START, State.WRITING_SEND)
  elseif crsf.state == State.WRITING_SEND then
    writeParam(crsf.sendFieldId, LCS_CONFIRMED, State.CONFIRMING)
  elseif crsf.state == State.CONFIRMING then
    crsf.currentBand = pending.band
    crsf.currentChannel = pending.channel
    pending.band = nil
    pending.channel = nil
    crsf.state = State.READY
    statusText = "Sent!"
    refreshUi()
  end
end

---- [6] CRSF Processing (called every frame in run()) ----

local function processCrsf()
  for _ = 1, 20 do
    local cmd, data = crsfPop()
    if not cmd then break end

    if cmd == CMD_DEVICE_INFO and crsf.state == State.PINGING then
      parseDeviceInfo(data)
    elseif cmd == CMD_PARAM_RESP then
      if crsf.state == State.ENUMERATING then
        parseParamInfo(data)
      elseif crsf.state >= State.WRITING_BAND and crsf.state <= State.CONFIRMING then
        -- Verify response is for the field we're writing
        local respFieldId = data and data[3]
        local expectedId =
          (crsf.state == State.WRITING_BAND and crsf.bandFieldId) or
          (crsf.state == State.WRITING_CHAN and crsf.channelFieldId) or
          crsf.sendFieldId
        if respFieldId == expectedId then
          continueApply()
        end
      end
    end
  end

  local elapsed = getTime() - crsf.timer

  if crsf.state == State.PINGING and elapsed > TIMEOUT_PING then
    if crsf.retryCount < RETRY_MAX then
      crsf.retryCount = crsf.retryCount + 1
      sendPing()
    else
      statusText = "TX module not found"
      crsf.state = State.ERROR
    end
  elseif crsf.state == State.ENUMERATING and elapsed > TIMEOUT_ENUM then
    requestField(crsf.loadIdx)
  elseif crsf.state >= State.WRITING_BAND and crsf.state <= State.CONFIRMING then
    local timeout = (crsf.state <= State.WRITING_CHAN) and TIMEOUT_WRITE or TIMEOUT_SEND
    if elapsed > timeout then
      continueApply()
    end
  end
end

---- [7] LVGL UI ----

local function isReady()
  return crsf.state == State.READY
end

local ui = {
  bandBtns = {},  -- { [bandName] = btn }
}

local bandDirty = false  -- track if band changed (save on exit)

local function updateBandUi()
  bandDirty = true
  bwItemsDirty = true
  dirtyAll = true
end

local function buildUi()
  if lvgl == nil then return end

  lvgl.clear()
  ui.bandBtns = {}

  local page = lvgl.page({
    title = "EasyVTXch",
    subtitle = getCurrentText,
    back = function()
      exitScript = true
    end,
  })

  local y = 0

  -- Status bar
  page:label({
    x = 4, y = y,
    text = function() return statusText end,
    font = SMLSIZE,
    color = COLOR_THEME_PRIMARY1,
  })
  y = y + 18

  -- Favorites grid (4 columns per row, multiple rows)
  if #favorites > 0 then
    local favBox = page:box({
      x = 0, y = y, w = 460,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = lvgl.PAD_TINY,
    })
    for rowStart = 1, #favorites, 4 do
      local row = favBox:box({ flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_SMALL })
      for i = rowStart, math.min(rowStart + 3, #favorites) do
        local fb, fc = favorites[i].band, favorites[i].channel
        row:button({
          w = 108, h = 28,
          text = fb .. fc .. " " .. getFreq(fb, fc),
          font = SMLSIZE,
          active = isReady,
          press = function() sendChannel(fb, fc) end,
          longpress = function()
            toggleFavorite(fb, fc)
            dirtyAll = true
          end,
        })
      end
    end
    local favRows = math.ceil(#favorites / 4)
    y = y + favRows * 32 + 12
  end

  -- Band selector
  local bandBox = page:box({
    x = 0, y = y, w = 460, h = 32,
    flexFlow = lvgl.FLOW_ROW,
    flexPad = lvgl.PAD_SMALL,
  })
  for _, bname in ipairs(BAND_NAMES) do
    local b = bname
    local btn = bandBox:button({
      w = 60, h = 28,
      text = b,
      checked = (selectedBand == b),
      active = isReady,
      press = function()
        selectedBand = b
        updateBandUi()
      end,
    })
    ui.bandBtns[b] = btn
  end
  y = y + 36

  -- Channel grid (2 rows x 4 cols)
  local chanBox = page:box({
    x = 0, y = y, w = 472,
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_SMALL,
  })

  local function makeRow(parent, startCh, endCh)
    local row = parent:box({ flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_SMALL })
    for ch = startCh, endCh do
      local c = ch
      row:button({
        w = 108, h = 50,
        text = selectedBand .. c .. "\n" .. getFreq(selectedBand, c),
        checked = isFavorite(selectedBand, c),
        active = isReady,
        press = function() sendChannel(selectedBand, c) end,
        longpress = function()
          toggleFavorite(selectedBand, c)
          dirtyAll = true
        end,
      })
    end
  end

  makeRow(chanBox, 1, 4)
  makeRow(chanBox, 5, 8)

  -- Retry button
  page:button({
    x = 140, y = y + 120, w = 180,
    text = "Retry Connection",
    visible = function() return crsf.state == State.ERROR end,
    press = function()
      crsf.retryCount = 0
      sendPing()
    end,
  })
end

---- [8] B&W Fallback (128x64) ----

local bw = {
  cursor = 1,
  scrollOffset = 0,
}

local bwItemsCache = {}

local function getBwItems()
  if not bwItemsDirty then return bwItemsCache end
  bwItemsCache = {}
  for _, fav in ipairs(favorites) do
    bwItemsCache[#bwItemsCache + 1] = {
      label = "* " .. fav.band .. fav.channel .. " " .. getFreq(fav.band, fav.channel),
      band = fav.band,
      channel = fav.channel,
    }
  end
  for ch = 1, 8 do
    bwItemsCache[#bwItemsCache + 1] = {
      label = selectedBand .. ch .. " " .. getFreq(selectedBand, ch),
      band = selectedBand,
      channel = ch,
    }
  end
  bwItemsDirty = false
  return bwItemsCache
end

local function drawBwUi()
  lcd.clear()
  lcd.drawText(1, 0, "EasyVTXch", BOLD)
  lcd.drawText(70, 0, statusText, SMLSIZE)

  local ct = getCurrentText()
  if ct ~= "" then
    lcd.drawText(1, 9, "Now:" .. ct, SMLSIZE)
  end

  lcd.drawText(1, 17, "Band:" .. selectedBand, SMLSIZE + INVERS)

  local items = getBwItems()
  local maxVisible = 4
  local startY = 26

  if bw.cursor > #items then bw.cursor = #items end
  if bw.cursor < 1 then bw.cursor = 1 end
  if bw.cursor > bw.scrollOffset + maxVisible then
    bw.scrollOffset = bw.cursor - maxVisible
  end
  if bw.cursor <= bw.scrollOffset then
    bw.scrollOffset = bw.cursor - 1
  end

  for i = 1, maxVisible do
    local idx = i + bw.scrollOffset
    if idx > #items then break end
    local y = startY + (i - 1) * 10
    local attr = (idx == bw.cursor) and INVERS or 0
    lcd.drawText(1, y, items[idx].label, SMLSIZE + attr)
  end
end

local function handleBwEvent(event)
  if event == EVT_VIRTUAL_NEXT then
    bw.cursor = bw.cursor + 1
  elseif event == EVT_VIRTUAL_PREV then
    bw.cursor = bw.cursor - 1
  elseif event == EVT_VIRTUAL_ENTER then
    local items = getBwItems()
    local item = items[bw.cursor]
    if item then
      sendChannel(item.band, item.channel)
    end
  elseif event == EVT_VIRTUAL_ENTER_LONG then
    local items = getBwItems()
    local item = items[bw.cursor]
    if item then
      toggleFavorite(item.band, item.channel)
    end
  elseif event == EVT_VIRTUAL_MENU then
    local idx = 0
    for i, b in ipairs(BAND_NAMES) do
      if b == selectedBand then idx = i; break end
    end
    idx = idx + 1
    if idx > #BAND_NAMES then idx = 1 end
    selectedBand = BAND_NAMES[idx]
    bandDirty = true
    bwItemsDirty = true
  end
end

---- [9] init / run ----

local function init()
  loadFavorites()

  if lvgl ~= nil then
    buildUi()
  end

  crsf.retryCount = 0
  sendPing()
end

local function run(event, touchState)
  if event == EVT_VIRTUAL_EXIT and lvgl == nil then
    if bandDirty then saveFavorites() end
    return 2
  end

  local ok, err = pcall(processCrsf)
  if not ok then
    statusText = tostring(err)
    crsf.state = State.ERROR
  end

  -- Full UI rebuild (lvgl.clear + rebuild)
  if lvgl ~= nil and dirtyAll then
    dirtyAll = false
    buildUi()
    -- Try to restore focus to selected band button
    local btn = ui.bandBtns[selectedBand]
    if btn then pcall(function() btn:focus() end) end
  end

  if lvgl == nil then
    handleBwEvent(event)
    drawBwUi()
  end

  if exitScript then
    if bandDirty then saveFavorites() end
    return 2
  end
  return 0
end

return { init = init, run = run, useLvgl = true }
