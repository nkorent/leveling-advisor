local _, ns = ...

local Export = {}
ns.Export = Export

local FRAME_NAME = "LevelingAdvisorExportFrame"
local TITLE = "Leveling Advisor: Export"

local function hint()
  local mac = ns.Util.call(IsMacClient)
  return "Press " .. (mac and "Cmd+C" or "Ctrl+C") .. " to copy, then Escape to close."
end

------------------------------------------------------------------------
-- JSON (deterministic, pure Lua 5.1)
------------------------------------------------------------------------

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r",
  ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f",
}

local function escapeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function encodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then return "null" end
  if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
  -- Shortest %g form that round-trips (no trailing zeros, e.g. 37.4).
  for digits = 15, 17 do
    local s = string.format("%." .. digits .. "g", n)
    if tonumber(s) == n or digits == 17 then return s end
  end
end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return false end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local encodeValue

local function encodeTable(t, out)
  if isArray(t) then
    out[#out + 1] = "["
    for i = 1, #t do
      if i > 1 then out[#out + 1] = "," end
      encodeValue(t[i], out)
    end
    out[#out + 1] = "]"
    return
  end
  local keys = {}
  for k, v in pairs(t) do
    local tk = type(k)
    if (tk == "string" or tk == "number") and type(v) ~= "nil" and type(v) ~= "function"
       and type(v) ~= "userdata" and type(v) ~= "thread" then
      keys[#keys + 1] = tostring(k)
    end
  end
  table.sort(keys)
  -- map string key back to value (numeric keys stringify uniquely enough here)
  local byStr = {}
  for k, v in pairs(t) do byStr[tostring(k)] = v end
  out[#out + 1] = "{"
  for i, k in ipairs(keys) do
    if i > 1 then out[#out + 1] = "," end
    out[#out + 1] = escapeString(k)
    out[#out + 1] = ":"
    encodeValue(byStr[k], out)
  end
  out[#out + 1] = "}"
end

function encodeValue(v, out)
  local tv = type(v)
  if tv == "table" then encodeTable(v, out)
  elseif tv == "string" then out[#out + 1] = escapeString(v)
  elseif tv == "number" then out[#out + 1] = encodeNumber(v)
  elseif tv == "boolean" then out[#out + 1] = v and "true" or "false"
  else out[#out + 1] = "null" end
end

function Export.toJSON(value)
  local out = {}
  encodeValue(value, out)
  return table.concat(out)
end

------------------------------------------------------------------------
-- Base64 (standard alphabet, arithmetic only)
------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function Export.base64(s)
  local out = {}
  local len = #s
  for i = 1, len, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1)
      .. (b and ALPHABET:sub(c3 + 1, c3 + 1) or "=")
      .. (c and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

------------------------------------------------------------------------
-- Payload and encoding
------------------------------------------------------------------------

function Export.payload(store, meta)
  meta = meta or {}
  return {
    v = 1,
    addon = ns.VERSION,
    gameData = meta.gameData,
    built = meta.built,
    recorder = store,
  }
end

function Export.encode(payload, enc)
  local json = Export.toJSON(payload)
  enc = enc or {}
  if enc.compress and enc.base64 then
    local ok, res = pcall(function() return enc.base64(enc.compress(json)) end)
    if ok and type(res) == "string" then return "LA1Z:" .. res end
  end
  return "LA1J:" .. Export.base64(json)
end

function Export.realEnc()
  local enc = {}
  local api = C_EncodingUtil
  if type(api) == "table" then
    if type(api.CompressString) == "function" then
      enc.compress = function(s)
        local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
        return api.CompressString(s, method)
      end
    end
    if type(api.EncodeBase64) == "function" then
      enc.base64 = function(s) return api.EncodeBase64(s) end
    end
  end
  return enc
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local call, method = ns.Util.call, ns.Util.method
local frame, editBox

local function build()
  if type(CreateFrame) ~= "function" then return nil end
  local f = call(CreateFrame, "Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
    or call(CreateFrame, "Frame", FRAME_NAME, UIParent)
  if not f then return nil end
  method(f, "SetSize", 560, 220)
  method(f, "SetPoint", "CENTER")
  method(f, "SetFrameStrata", "DIALOG")
  method(f, "SetMovable", true)
  method(f, "EnableMouse", true)
  method(f, "RegisterForDrag", "LeftButton")
  method(f, "SetScript", "OnDragStart", function(self) method(self, "StartMoving") end)
  method(f, "SetScript", "OnDragStop", function(self) method(self, "StopMovingOrSizing") end)

  local title = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormal")
  if title then
    method(title, "SetPoint", "TOP", 0, -6)
    method(title, "SetText", TITLE)
  end
  local hintText = method(f, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
  if hintText then
    method(hintText, "SetPoint", "BOTTOM", 0, 12)
    method(hintText, "SetText", hint())
  end

  local scroll = call(CreateFrame, "ScrollFrame", FRAME_NAME .. "Scroll", f, "UIPanelScrollFrameTemplate")
  local box = call(CreateFrame, "EditBox", FRAME_NAME .. "EditBox", scroll or f)
  if not box then return f, nil end
  method(box, "SetMultiLine", true)
  method(box, "SetAutoFocus", false)
  method(box, "SetMaxLetters", 0)
  method(box, "SetFontObject", ChatFontNormal)
  method(box, "SetWidth", 500)
  method(box, "SetScript", "OnEscapePressed", function(self)
    method(self, "ClearFocus")
    method(f, "Hide")
  end)
  if scroll then
    method(scroll, "SetPoint", "TOPLEFT", 12, -32)
    method(scroll, "SetPoint", "BOTTOMRIGHT", -32, 36)
    method(scroll, "SetScrollChild", box)
  else
    method(box, "SetPoint", "TOPLEFT", 12, -32)
    method(box, "SetPoint", "BOTTOMRIGHT", -12, 36)
  end

  if type(UISpecialFrames) == "table" then
    UISpecialFrames[#UISpecialFrames + 1] = FRAME_NAME
  end
  return f, box
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

function Export.run()
  if inCombat() then
    ns.Util.say("Not in combat: try again after the fight.")
    return
  end
  local store = ns.db and ns.db.recorder or {}
  local meta = ns.Data and ns.Data.meta or {}
  local str = Export.encode(Export.payload(store, meta), Export.realEnc())

  if not frame then frame, editBox = build() end
  if not frame then
    ns.Util.say("Could not open the export window.")
    return
  end
  if editBox then
    method(editBox, "SetText", str)
  end
  method(frame, "Show")
  if editBox then
    method(editBox, "SetFocus")
    method(editBox, "HighlightText")
  end
end
