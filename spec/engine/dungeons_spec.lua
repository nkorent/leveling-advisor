local H = require("spec.helpers.engine")
local ns = H.load()
local db = ns.DB.new(H.data())
local S18, S20, S22, with, pickupIDs = H.states.S18, H.states.S20, H.states.S22, H.with, H.pickupIDs
local Engine = ns.Engine
-- BFD's quests are level 23 and 24: orange at 20 and 21, yellow from 22 (level fit, 0.3.0), so
-- the recommended-dungeon cases use S22 (S20's character at level 22).

describe("Dungeons.recommend", function()
  it("no dungeon at 18 (below 22-2)", function() assert.is_nil(Engine.compute(db, S18).dungeon) end)

  it("no dungeon at 20: every BFD quest is orange, so none is a pickup", function()
    assert.is_nil(Engine.compute(db, S20).dungeon)
  end)

  it("an orange dungeon quest is not a pickup", function()
    -- 1199 at level 25 is orange at 22; the other three still make the run
    local data = H.data()
    data.quests[1199][6] = 25
    local d = Engine.compute(ns.DB.new(data), S22).dungeon
    assert.equals("BFD", d.key)
    assert.equals(3, d.questCount)
    assert.is_nil(H.pickupFor(d, 1199))
  end)

  it("an orange dungeon quest in the log is not a pickup either", function()
    local data = H.data()
    data.quests[1199][6] = 25
    local s = with(S22, { log = { [966] = { complete = false }, [4730] = { complete = true },
      [1199] = { complete = false } } })
    local d = Engine.compute(ns.DB.new(data), s).dungeon
    assert.equals("BFD", d.key)
    assert.is_nil(H.pickupFor(d, 1199))
  end)

  it("BFD at 22 with pickups in route order", function()
    local d = Engine.compute(db, S22).dungeon
    assert.equals("BFD", d.key); assert.equals(22, d.bestLevel) -- the 2nd lowest quest is 24: yellow from 22
    assert.same({ 1199, 1275, 6563, 6922 }, pickupIDs(d))
    assert.equals("Best at 22 — three of its quests start on your way", d.reason)
  end)

  it("best level is the lowest at which two quests are yellow or green", function()
    local data = H.data()
    data.quests[1199][6] = 30; data.quests[1275][6] = 30; data.quests[6563][6] = 26
    data.quests[6922][6] = 23
    local d = Engine.compute(ns.DB.new(data), with(S22, { level = 25 })).dungeon
    assert.equals(24, d.bestLevel) -- 23 and 26 are yellow together from level 24
    assert.is_truthy(d.reason:match("^Best at 24"))
  end)

  it("best level never goes below the dungeon's minimum level", function()
    local data = H.data()
    for _, id in ipairs({ 1199, 1275, 6563, 6922 }) do data.quests[id][6] = 16 end -- green at 22
    local d = Engine.compute(ns.DB.new(data), S22).dungeon
    assert.equals(22, d.bestLevel) -- 16 - 2 = 14, clamped to minLevel 22
    assert.is_truthy(d.reason:match("^Best at 22"))
  end)

  it("bestLevel: below the range -> minLevel; above it or under two quests -> minLevel - 1", function()
    local d = { minLevel = 22, maxLevel = 28 }
    assert.equals(22, ns.Dungeons.bestLevel({ 12, 14 }, d))
    assert.equals(24, ns.Dungeons.bestLevel({ 23, 24 }, d))
    assert.equals(28, ns.Dungeons.bestLevel({ 20, 28 }, d))
    assert.equals(21, ns.Dungeons.bestLevel({ 29, 30 }, d)) -- all quests too high for the range
    assert.equals(21, ns.Dungeons.bestLevel({ 24 }, d))
    assert.equals(21, ns.Dungeons.bestLevel({}, d))
  end)

  it("fills the Contract C dungeon shape", function()
    local d = Engine.compute(db, S22).dungeon
    assert.equals("Blackfathom Deeps", d.name)
    assert.equals(22, d.minLevel); assert.equals(28, d.maxLevel); assert.equals(5, d.groupSize)
    assert.equals(4, d.questCount)
    assert.same({ mapID = 1440, x = 14.0, y = 14.0 }, d.entrance)
    assert.is_true(d.xp > 0)
    assert.same({ false, false, false, false },
      { d.pickups[1].inLog, d.pickups[2].inLog, d.pickups[3].inLog, d.pickups[4].inLog })
  end)

  it("needs two quests", function()
    local s = with(S22, { completed = { [4762] = true, [965] = true, [1199] = true, [1275] = true, [6563] = true } })
    assert.is_nil(Engine.compute(db, s).dungeon)
  end)

  it("elite quests off keeps BFD and its four pickups (dungeon quests are not elite filler)", function()
    local s = with(S22, { settings = { elite = false, dungeons = true } })
    local d = Engine.compute(db, s).dungeon
    assert.equals("BFD", d.key)
    assert.same({ 1199, 1275, 6563, 6922 }, pickupIDs(d))
  end)

  it("never recommends a dungeon with a single available quest (Wailing Caverns at 20)", function()
    -- WC is in its level window at 20 and 1486 is eligible, but one quest is not a run
    local d = Engine.compute(db, S22).dungeon
    assert.equals("BFD", d.key)
    assert.is_nil(H.pickupFor(d, 1486))
  end)

  it("respects the setting", function()
    local s = with(S22, { settings = { elite = true, dungeons = false } })
    assert.is_nil(Engine.compute(db, s).dungeon)
  end)

  it("uses the singular for one quest on the way", function()
    -- only 6563 (next zone, Ashenvale) and 6922 (Loch Modan) remain
    local s = with(S22, { completed = { [4762] = true, [965] = true, [1199] = true, [1275] = true } })
    local d = Engine.compute(db, s).dungeon
    assert.equals("BFD", d.key)
    assert.same({ 6563, 6922 }, pickupIDs(d))
    assert.equals("Best at 22 — one of its quests starts on your way", d.reason)
  end)

  it("lists in-log dungeon quests as inLog pickups", function()
    local s = with(S22, { log = { [966] = { complete = false }, [4730] = { complete = true }, [1199] = { complete = false } } })
    local d = Engine.compute(db, s).dungeon
    assert.is_true(H.pickupFor(d, 1199).inLog)
  end)


  it("does not count in-log pickups as on the way", function()
    local s = with(S22, { log = { [966] = { complete = false }, [4730] = { complete = true }, [1199] = { complete = false } } })
    assert.equals("Best at 22 — two of its quests start on your way", Engine.compute(db, s).dungeon.reason)
  end)

  local function dbWith(edit)
    local data = H.data()
    edit(data)
    return ns.DB.new(data)
  end

  describe("quests the player cannot pick up yet", function()
    -- 1199 and 1275 need level 24; at level 22 they are "soon", not available
    local function soonDb()
      return dbWith(function(data)
        data.quests[1199][5] = 24
        data.quests[1275][5] = 24
      end)
    end

    it("does not recommend a dungeon whose only quests are soon", function()
      local s = with(S22, { completed = { [4762] = true, [965] = true, [6563] = true, [6922] = true } })
      assert.is_nil(Engine.compute(soonDb(), s).dungeon)
    end)

    it("counts and lists only the quests the player can get or has", function()
      local d = Engine.compute(soonDb(), S22).dungeon
      assert.equals("BFD", d.key)
      assert.equals(2, d.questCount)
      assert.same({ 6563, 6922 }, pickupIDs(d))
      assert.equals("Best at 22 — one of its quests starts on your way", d.reason)
    end)
  end)

  -- Adds a dungeon `key` with four copies of the BFD quests (same XP), then
  -- applies `over` to the dungeon record. Quest IDs are base+1..base+4.
  local function withDungeon(key, base, over)
    return dbWith(function(data)
      local ids = {}
      for i, src in ipairs({ 1199, 1275, 6563, 6922 }) do
        local r = {}
        for k, v in pairs(data.quests[src]) do r[k] = v end
        r[23] = key
        data.quests[base + i] = r
        ids[i] = base + i
      end
      local d = {}
      for k, v in pairs(data.dungeons.BFD) do d[k] = v end
      d.quests = ids
      for k, v in pairs(over or {}) do d[k] = v end
      data.dungeons[key] = d
    end)
  end
  local HERE = { 1439, 38.0, 41.0 }   -- the player's feet in S22

  describe("choosing between dungeons", function()
    it("takes the cheaper trip when the quest XP is the same", function()
      local d = Engine.compute(withDungeon("NEAR", 9100, { entrance = HERE }), S22).dungeon
      assert.equals("NEAR", d.key)
      assert.same({ mapID = 1439, x = 38.0, y = 41.0 }, d.entrance)
    end)

    it("a farther entrance loses to BFD at the same XP", function()
      local far = { 1440, 90.0, 90.0 }   -- the far corner of BFD's zone
      local d = Engine.compute(withDungeon("FAR", 9100, { entrance = far }), S22).dungeon
      assert.equals("BFD", d.key)
    end)

    it("takes the dungeon with more quest XP", function()
      local db2 = withDungeon("RICH", 9100, { quests = { 9101, 9102, 9103, 9104 } })
      -- same entrance and quests as BFD, but one RICH quest is worth far more
      db2.data.quests[9101][17] = 50000
      assert.equals("RICH", Engine.compute(db2, S22).dungeon.key)
    end)

    it("breaks an exact tie by the lower key", function()
      local lower = Engine.compute(withDungeon("ABD", 9100), S22).dungeon
      assert.equals("ABD", lower.key)
      local higher = Engine.compute(withDungeon("ZFD", 9100), S22).dungeon
      assert.equals("BFD", higher.key)
    end)

    it("skips a dungeon that is not live", function()
      local db2 = withDungeon("NEAR", 9100, { entrance = HERE, live = false })
      assert.equals("BFD", Engine.compute(db2, S22).dungeon.key)
    end)

    it("skips a dungeon of the other faction", function()
      local db2 = withDungeon("NEAR", 9100, { entrance = HERE, faction = 2 })
      assert.equals("BFD", Engine.compute(db2, S22).dungeon.key)
    end)

    it("keeps a dungeon of the player's own faction", function()
      local db2 = withDungeon("NEAR", 9100, { entrance = HERE, faction = 1 })
      assert.equals("NEAR", Engine.compute(db2, S22).dungeon.key)
    end)

    it("skips a dungeon the player has outgrown", function()
      local db2 = withDungeon("LOW", 9100, { entrance = HERE, minLevel = 10, maxLevel = 19 })
      assert.equals("BFD", Engine.compute(db2, S22).dungeon.key)
    end)

    it("does not recommend anything above the only dungeon's maximum level", function()
      local s = with(S20, { level = 29, log = {}, completed = {} })
      assert.is_nil(Engine.compute(db, s).dungeon)
    end)

    it("still recommends at the maximum level", function()
      local s = with(S20, { level = 28 })
      assert.equals("BFD", Engine.compute(db, s).dungeon.key)
    end)

    -- 1199 is made a low-level quest worth 2250 XP at full value, so its XP
    -- depends on which level the dungeon scores it at. The other three quests
    -- are worth 2100 + 2000 + 2050 and never change in this range.
    -- othersAt: the level of the other three (they keep their full XP from 22 to 25).
    local function lowQuestDb(level, othersAt)
      return dbWith(function(data)
        data.quests[1199][6] = level
        for _, id in ipairs(othersAt and { 1275, 6563, 6922 } or {}) do data.quests[id][6] = othersAt end
      end)
    end

    it("scores quest XP at the dungeon's minimum level for a lower-level player", function()
      -- level 14 is x0.4 at 22 (900) but would be x0.8 at the player's 20 (1800); the other
      -- three are made level 22, so they fit (yellow) at 20
      assert.equals(7050, Engine.compute(lowQuestDb(14, 22), S20).dungeon.xp)
    end)

    it("scores quest XP at the player's level once above the minimum", function()
      -- level 19 is x0.8 at 25 (1800) but would be x1.0 at the minimum 22 (2250)
      assert.equals(7950, Engine.compute(lowQuestDb(19), with(S20, { level = 25 })).dungeon.xp)
    end)
  end)
end)
