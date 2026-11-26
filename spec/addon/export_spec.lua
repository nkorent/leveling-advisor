local addon = require("spec.helpers.addon")

local FILES = { "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "Core/Export.lua" }

local function b64decode(s)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local map = {}
  for i = 1, #alphabet do map[alphabet:sub(i, i)] = i - 1 end
  s = s:gsub("=+$", "")
  local out, acc, bits = {}, 0, 0
  for i = 1, #s do
    acc = acc * 64 + map[s:sub(i, i)]
    bits = bits + 6
    if bits >= 8 then
      bits = bits - 8
      local div = 2 ^ bits
      out[#out + 1] = string.char(math.floor(acc / div))
      acc = acc % div
    end
  end
  return table.concat(out)
end

local function richCreateFrame(created)
  return function(kind, name, parent, template)
    local f = { kind = kind, name = name, template = template, shown = false, calls = {} }
    setmetatable(f, { __index = function(t, k)
      if type(k) == "string" and k:match("^[A-Z]") then
        return function(self, ...)
          self.calls[#self.calls + 1] = { k, ... }
          if k == "CreateFontString" then
            local fs = richCreateFrame(created)("FontString")
            return fs
          end
          if k == "GetText" then return self.text end
          return nil
        end
      end
    end })
    function f:SetText(t) self.text = t end
    function f:SetScript(n, fn) self.scripts = self.scripts or {}; self.scripts[n] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    created[#created + 1] = f
    return f
  end
end

local function setup(extra)
  local ns, env, out = addon.load(FILES, extra)
  return ns, env, out
end

describe("Export.toJSON", function()
  local ns = setup()
  local E = ns.Export

  it("sorts keys, arrays and escapes", function()
    assert.equal('{"a":[2,3],"b":1,"c":"x\\"y"}', E.toJSON({ b = 1, a = { 2, 3 }, c = 'x"y' }))
  end)
  it("empty table is {}", function() assert.equal("{}", E.toJSON({})) end)
  it("numeric keys that are not 1..n become string keys", function()
    assert.equal('{"18":1700}', E.toJSON({ [18] = 1700 }))
  end)
  it("mixed tables are objects", function()
    assert.equal('{"1":"a","k":"b"}', E.toJSON({ "a", k = "b" }))
  end)
  it("numbers", function()
    assert.equal("[1,37.4,-2,0.5]", E.toJSON({ 1, 37.4, -2, 0.5 }))
    assert.equal("[null,null,null]", E.toJSON({ 0 / 0, 1 / 0, -1 / 0 }))
  end)
  it("escapes control characters and omits nil", function()
    assert.equal('"a\\nb\\tc\\\\\\u0001"', E.toJSON("a\nb\tc\\\1"))
    assert.equal('{"a":true,"b":false}', E.toJSON({ a = true, b = false, c = nil }))
  end)
  it("is deterministic", function()
    local t = { z = 1, y = 2, x = { 3, 4 }, [5] = 6 }
    assert.equal(E.toJSON(t), E.toJSON(t))
  end)
end)

describe("Export.base64", function()
  local ns = setup()
  it("pads per the standard alphabet", function()
    assert.equal("TWFu", ns.Export.base64("Man"))
    assert.equal("TWE=", ns.Export.base64("Ma"))
    assert.equal("TQ==", ns.Export.base64("M"))
    assert.equal("", ns.Export.base64(""))
    assert.equal("/+8=", ns.Export.base64("\255\239"))
  end)
end)

describe("Export.encode", function()
  local ns = setup()
  local E = ns.Export
  local empty = { xp = {}, levels = {}, details = {}, accepted = {} }

  it("falls back to LA1J with no enc", function()
    local p = E.payload(empty, {})
    local s = E.encode(p, {})
    assert.equal("LA1J:", s:sub(1, 5))
    assert.equal(E.toJSON(p), b64decode(s:sub(6)))
  end)
  it("falls back to LA1J when compress throws", function()
    local s = E.encode(E.payload(empty, {}), {
      compress = function() error("boom") end, base64 = function(x) return x end })
    assert.equal("LA1J:", s:sub(1, 5))
  end)
  it("uses LA1Z with both stubs", function()
    local p = E.payload(empty, {})
    local s = E.encode(p, { compress = function(x) return "Z" .. x end, base64 = function(x) return "<" .. x .. ">" end })
    assert.equal("LA1Z:<Z" .. E.toJSON(p) .. ">", s)
  end)
  it("payload carries meta and no player fields", function()
    ns.VERSION = "0.1.0"
    local p = E.payload(empty, { gameData = "1.60.1", built = "2026-11-25" })
    assert.equal(1, p.v)
    assert.equal("1.60.1", p.gameData)
    local json = E.toJSON(p)
    for _, k in ipairs({ "name", "realm", "player" }) do
      assert.is_nil(json:find('"' .. k .. '"', 1, true))
    end
  end)
  it("realEnc is nil-safe without C_EncodingUtil", function()
    local enc = E.realEnc()
    assert.is_nil(enc.compress)
    assert.is_nil(enc.base64)
  end)
  it("realEnc wraps C_EncodingUtil", function()
    local ns2 = setup({
      Enum = { CompressionMethod = { Deflate = 7 } },
      C_EncodingUtil = {
        CompressString = function(s, m) return s .. m end,
        EncodeBase64 = function(s) return "b" .. s end,
      },
    })
    local enc = ns2.Export.realEnc()
    assert.equal("x7", enc.compress("x"))
    assert.equal("bx", enc.base64("x"))
  end)
end)

describe("Export.run", function()
  it("refuses in combat and creates no frame", function()
    local ns, env, out = setup({ InCombatLockdown = function() return true end })
    ns.db = { recorder = {} }
    local before = #env.frames
    ns.Export.run()
    assert.equal("|cffffd100Leveling Advisor:|r Not in combat: try again after the fight.", out[1])
    assert.equal(before, #env.frames)
  end)

  it("builds one reusable window with the string", function()
    local created = {}
    local ns, env, out = setup({
      CreateFrame = richCreateFrame(created),
      UISpecialFrames = {},
    })
    ns.db = { recorder = { xp = {}, levels = {}, details = {}, accepted = {} } }
    ns.Export.run()
    local n = #created
    assert.is_true(n >= 2)
    local frame
    for _, f in ipairs(created) do if f.name == "LevelingAdvisorExportFrame" then frame = f end end
    assert.is_truthy(frame)
    assert.is_true(frame.shown)
    local box
    for _, f in ipairs(created) do if f.kind == "EditBox" then box = f end end
    assert.equal("LA1J:", box.text:sub(1, 5))
    local titled, hint = false, false
    for _, f in ipairs(created) do
      if f.text == "Leveling Advisor: Export" then titled = true end
      if f.text == "Press Ctrl+C to copy, then Escape to close." then hint = true end
    end
    assert.is_true(titled)
    assert.is_true(hint)
    local focused, highlighted = false, false
    for _, c in ipairs(box.calls) do
      if c[1] == "SetFocus" then focused = true end
      if c[1] == "HighlightText" then highlighted = true end
    end
    assert.is_true(focused)
    assert.is_true(highlighted)
    -- escape closes
    box.scripts.OnEscapePressed(box)
    assert.is_false(frame.shown)
    -- reuse
    ns.Export.run()
    assert.equal(n, #created)
    assert.is_true(frame.shown)
    local count = 0
    for _, v in ipairs(env.UISpecialFrames) do if v == "LevelingAdvisorExportFrame" then count = count + 1 end end
    assert.equal(1, count)
  end)

  it("hints Cmd+C on a Mac client and Ctrl+C otherwise or when IsMacClient is missing", function()
    local function hintFor(extra)
      local created = {}
      extra.CreateFrame = richCreateFrame(created)
      extra.UISpecialFrames = {}
      local ns = setup(extra)
      ns.db = { recorder = { xp = {}, levels = {}, details = {}, accepted = {} } }
      ns.Export.run()
      for _, f in ipairs(created) do
        if f.text and f.text:match("^Press .* to copy") then return f.text end
      end
    end
    assert.equal("Press Cmd+C to copy, then Escape to close.",
      hintFor({ IsMacClient = function() return true end }))
    assert.equal("Press Ctrl+C to copy, then Escape to close.",
      hintFor({ IsMacClient = function() return false end }))
    assert.equal("Press Ctrl+C to copy, then Escape to close.", hintFor({}))
    assert.equal("Press Ctrl+C to copy, then Escape to close.",
      hintFor({ IsMacClient = function() error("boom") end }))
  end)

  it("lifts the EditBox letter limit", function()
    local created = {}
    local ns = setup({ CreateFrame = richCreateFrame(created), UISpecialFrames = {} })
    ns.db = { recorder = { xp = {}, levels = {}, details = {}, accepted = {} } }
    ns.Export.run()
    local box
    for _, f in ipairs(created) do if f.kind == "EditBox" then box = f end end
    local set = false
    for _, c in ipairs(box.calls) do
      if c[1] == "SetMaxLetters" and c[2] == 0 then set = true end
    end
    assert.is_true(set)
  end)

  it("survives a missing CreateFrame", function()
    local ns, env = setup()
    env.CreateFrame = nil
    ns.db = { recorder = {} }
    assert.has_no.errors(function() ns.Export.run() end)
  end)
end)

describe("Export privacy with a filled store", function()
  it("never leaks a GUID, a Player- string or a name", function()
    local ns = addon.load({ "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua",
      "Core/Recorder.lua", "Core/Export.lua" })
    ns.db = { settings = {}, recorder = {} }
    local PLAYER_GUID = "Player-3678-0A1B2C3D"
    local api = {
      questID = function() return 4763 end,
      npcGUID = function() return PLAYER_GUID end,
      mapID = function() return 1439 end,
      position = function() return 0.374, 0.401 end,
      rewardXP = function() return 1700 end,
      numChoices = function() return 1 end,
      choiceLink = function() return "|Hitem:15204|h[Thunderfury of Playername]|h" end,
      numRewards = function() return 0 end,
      rewardLink = function() return nil end,
      level = function() return 18 end,
      now = function() return 1764000000 end,
      gossipAvailable = function() return { { questID = 4763, questLevel = 18 } } end,
      greetingAvailable = function() return {} end,
      unitName = function() return "Playername" end,
      realm = function() return "Realmname" end,
    }
    local rec = ns.Recorder.new(ns.db.recorder, api)
    rec:onGossip()
    rec:onDetail()
    rec:onAccepted(4763)
    rec:onComplete()
    rec:onTurnedIn(4763, 1700)
    assert.is_table(ns.db.recorder.details[4763])
    assert.is_nil(ns.db.recorder.details[4763].npcID)

    local json = ns.Export.toJSON(ns.Export.payload(ns.db.recorder, { gameData = "1.60.1" }))
    assert.is_nil(json:find("Player", 1, true))
    assert.is_nil(json:find("3678", 1, true))
    assert.is_nil(json:find("0A1B2C3D", 1, true))
    assert.is_nil(json:find("Realmname", 1, true))
    assert.is_nil(json:find("Playername", 1, true))
    assert.is_nil(json:find("Creature-", 1, true))
    -- the data that should be there is there
    assert.is_truthy(json:find('"xp":1700', 1, true))
  end)
end)
