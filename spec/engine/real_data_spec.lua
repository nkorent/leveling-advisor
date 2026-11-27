-- Invariants of the engine on the shipped data (LevelingAdvisor/Data/*.lua), for a grid of
-- characters: both factions, races 1/8/2^32 (Alliance) and 2/16/2^33 (Horde), levels 1-58,
-- four maps per faction. Skipped when the generated data is absent.
local H = require("spec.helpers.engine")

local DATA = { "Meta", "Zones", "NPCs", "Dungeons", "Quests" }

local function exists(p)
  local f = io.open(p, "r")
  if f then f:close() end
  return f ~= nil
end

local function haveData()
  for _, f in ipairs(DATA) do
    if not exists("LevelingAdvisor/Data/" .. f .. ".lua") then return false end
  end
  return true
end

local ALLIANCE = {
  races = { { 1, "WARRIOR", 1 }, { 8, "DRUID", 1024 }, { 2 ^ 32, "MAGE", 128 } },
  maps = { 1429, 1439, 1440, 1434 }, -- Elwynn, Darkshore, Ashenvale, Stranglethorn
}
local HORDE = {
  races = { { 2, "WARRIOR", 1 }, { 16, "ROGUE", 8 }, { 2 ^ 33, "PRIEST", 16 } },
  maps = { 1411, 1413, 1420, 1424 }, -- Durotar, The Barrens, Tirisfal, Hillsbrad
}
local LEVELS = { 1, 6, 12, 17, 22, 27, 33, 39, 45, 51, 55, 58 }

local function characters()
  local out = {}
  for _, side in ipairs({ { "Alliance", ALLIANCE }, { "Horde", HORDE } }) do
    local faction, t = side[1], side[2]
    for ri, race in ipairs(t.races) do
      for li, level in ipairs(LEVELS) do
        out[#out + 1] = {
          faction = faction, raceMask = race[1], classFile = race[2], classMask = race[3],
          level = level, mapID = t.maps[(ri + li) % #t.maps + 1], x = 50, y = 50,
          completed = {}, log = {}, ignored = {}, recordedXP = {},
          settings = { elite = true, dungeons = true },
        }
      end
    end
  end
  return out
end

local function label(s)
  return string.format("%s race %.0f level %d on %d", s.faction, s.raceMask, s.level, s.mapID)
end

;(haveData() and describe or pending)("Engine invariants on the shipped data", function()
  local ns, db, T, chars, runs
  local FACTION = { Alliance = 1, Horde = 2 }

  setup(function()
    ns = H.load()
    for _, f in ipairs(DATA) do
      assert(loadfile("LevelingAdvisor/Data/" .. f .. ".lua"))("LevelingAdvisor", ns)
    end
    db = ns.DB.new(ns.Data)
    T = ns.Tuning
    chars = characters()
    runs = {}
    for i, s in ipairs(chars) do
      local rec = ns.Engine.compute(db, s)
      runs[i] = { state = s, rec = rec, steps = ns.Engine.route(db, s, s.mapID, rec) }
    end
  end)

  it("covers both factions, every grid race and levels 1 to 58", function()
    assert.equals(72, #chars)
  end)

  local function quest(id) return db:quest(id) end

  it("never recommends an enemy-faction zone", function()
    for _, r in ipairs(runs) do
      for _, z in ipairs(r.rec.zones) do
        local f = db:zone(z.mapID).faction
        assert.is_true(f ~= 1 and f ~= 2 or f == FACTION[r.state.faction],
          label(r.state) .. ": zone " .. z.mapID .. " belongs to faction " .. tostring(f))
      end
    end
  end)

  it("offers available rows that pass Eligibility as eligible, and soon rows as soon", function()
    local checked = 0
    for _, r in ipairs(runs) do
      for _, sec in ipairs(r.rec.sections) do
        for _, row in ipairs(sec.rows) do
          if row.state == "available" then
            local want = row.soon and "soon" or "eligible"
            local got, why = ns.Eligibility.check(db, quest(row.questID), r.state)
            assert.equals(want, got, label(r.state) .. ": " .. sec.key .. " row " .. row.questID
              .. " is " .. tostring(got or why))
            checked = checked + 1
          end
        end
      end
    end
    assert.is_true(checked > 100, "rows checked: " .. checked)
  end)

  it("keeps dungeon quests out of the here, chains and next sections", function()
    local KEYS = { here = true, chains = true, next = true }
    for _, r in ipairs(runs) do
      for _, sec in ipairs(r.rec.sections) do
        if KEYS[sec.key] then
          for _, row in ipairs(sec.rows) do
            assert.is_false(quest(row.questID).dungeonQuest,
              label(r.state) .. ": dungeon quest " .. row.questID .. " in " .. sec.key)
          end
        end
      end
    end
  end)

  it("recommends a dungeon only inside its level window", function()
    local seen = 0
    for _, r in ipairs(runs) do
      local d = r.rec.dungeon
      if d then
        seen = seen + 1
        local lvl = r.state.level
        assert.is_true(lvl >= d.minLevel - T.DUNGEON_LEVEL_WINDOW and lvl <= d.maxLevel,
          label(r.state) .. ": " .. d.key .. " is " .. d.minLevel .. "-" .. d.maxLevel)
      end
    end
    assert.is_true(seen >= 10, "dungeons recommended: " .. seen)
  end)

  it("recommends the same dungeon with elite quests turned off", function()
    for _, r in ipairs(runs) do
      local s = H.with(r.state, { settings = { elite = false, dungeons = true } })
      local d = ns.Engine.compute(db, s).dungeon
      assert.equals(r.rec.dungeon and r.rec.dungeon.key, d and d.key, label(r.state))
    end
  end)

  it("routes pickups on the zone map, and dungeon pickups only of the recommended dungeon", function()
    local pickups, dungeonPickups = 0, 0
    for _, r in ipairs(runs) do
      local key = r.rec.dungeon and r.rec.dungeon.key
      for _, step in ipairs(r.steps) do
        assert.equals(r.state.mapID, step.mapID, label(r.state))
        for _, a in ipairs(step.actions) do
          if a[2] == "pickup" then
            local q = quest(a[1])
            pickups = pickups + 1
            assert.equals(r.state.mapID, q.giver.mapID, label(r.state) .. ": pickup " .. a[1])
            if q.dungeonQuest then
              dungeonPickups = dungeonPickups + 1
              assert.equals(key, q.dungeonKey, label(r.state) .. ": dungeon pickup " .. a[1])
            end
          end
        end
      end
    end
    assert.is_true(pickups > 100, "pickups: " .. pickups)
    assert.is_true(dungeonPickups > 0, "dungeon pickups: " .. dungeonPickups)
  end)

  it("never rejects a quest two levels up as level (the soon window)", function()
    local byRequired = {}
    for _, id in ipairs(db:questIDs()) do
      local q = quest(id)
      if q.requiredLevel then
        local list = byRequired[q.requiredLevel] or {}
        byRequired[q.requiredLevel] = list
        list[#list + 1] = q
      end
    end
    local checked = 0
    for _, r in ipairs(runs) do
      for _, q in ipairs(byRequired[r.state.level + T.SOON_LEVELS] or {}) do
        local _, why = ns.Eligibility.check(db, q, r.state)
        assert.are_not.equals("level", why, label(r.state) .. ": quest " .. q.id)
        checked = checked + 1
      end
    end
    assert.is_true(checked > 100, "quests checked: " .. checked)
  end)
end)
