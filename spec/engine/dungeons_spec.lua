local H = require("spec.helpers.engine")
local ns = H.load()
local db = ns.DB.new(H.data())
local S18, S20, with, pickupIDs = H.states.S18, H.states.S20, H.with, H.pickupIDs
local Engine = ns.Engine

describe("Dungeons.recommend", function()
  it("no dungeon at 18 (below 22-2)", function() assert.is_nil(Engine.compute(db, S18).dungeon) end)

  it("BFD at 20 with pickups in route order", function()
    local d = Engine.compute(db, S20).dungeon
    assert.equals("BFD", d.key); assert.equals(21, d.bestLevel)
    assert.same({ 1199, 1275, 6563, 6922 }, pickupIDs(d))
    assert.equals("Best at 21 — three of its quests start on your way", d.reason)
  end)

  it("fills the Contract C dungeon shape", function()
    local d = Engine.compute(db, S20).dungeon
    assert.equals("Blackfathom Deeps", d.name)
    assert.equals(22, d.minLevel); assert.equals(28, d.maxLevel); assert.equals(5, d.groupSize)
    assert.equals(4, d.questCount)
    assert.same({ mapID = 1440, x = 14.0, y = 14.0 }, d.entrance)
    assert.is_true(d.xp > 0)
    assert.same({ false, false, false, false },
      { d.pickups[1].inLog, d.pickups[2].inLog, d.pickups[3].inLog, d.pickups[4].inLog })
  end)

  it("needs two quests", function()
    local s = with(S20, { completed = { [4762] = true, [965] = true, [1199] = true, [1275] = true, [6563] = true } })
    assert.is_nil(Engine.compute(db, s).dungeon)
  end)

  it("respects the setting", function()
    local s = with(S20, { settings = { elite = true, dungeons = false } })
    assert.is_nil(Engine.compute(db, s).dungeon)
  end)

  it("uses the singular for one quest on the way", function()
    -- only 6563 (next zone, Ashenvale) and 6922 (Loch Modan) remain
    local s = with(S20, { completed = { [4762] = true, [965] = true, [1199] = true, [1275] = true } })
    local d = Engine.compute(db, s).dungeon
    assert.equals("BFD", d.key)
    assert.same({ 6563, 6922 }, pickupIDs(d))
    assert.equals("Best at 21 — one of its quests starts on your way", d.reason)
  end)

  it("lists in-log dungeon quests as inLog pickups", function()
    local s = with(S20, { log = { [966] = { complete = false }, [4730] = { complete = true }, [1199] = { complete = false } } })
    local d = Engine.compute(db, s).dungeon
    assert.is_true(H.pickupFor(d, 1199).inLog)
  end)


  it("does not count in-log pickups as on the way", function()
    local s = with(S20, { log = { [966] = { complete = false }, [4730] = { complete = true }, [1199] = { complete = false } } })
    assert.equals("Best at 21 — two of its quests start on your way", Engine.compute(db, s).dungeon.reason)
  end)

  local function dbWith(edit)
    local data = H.data()
    edit(data)
    return ns.DB.new(data)
  end

  describe("quests the player cannot pick up yet", function()
    -- 1199 and 1275 need level 22; at level 20 they are "soon", not available
    local function soonDb()
      return dbWith(function(data)
        data.quests[1199][5] = 22
        data.quests[1275][5] = 22
      end)
    end

    it("does not recommend a dungeon whose only quests are soon", function()
      local s = with(S20, { completed = { [4762] = true, [965] = true, [6563] = true, [6922] = true } })
      assert.is_nil(Engine.compute(soonDb(), s).dungeon)
    end)

    it("counts and lists only the quests the player can get or has", function()
      local d = Engine.compute(soonDb(), S20).dungeon
      assert.equals("BFD", d.key)
      assert.equals(2, d.questCount)
      assert.same({ 6563, 6922 }, pickupIDs(d))
      assert.equals("Best at 21 — one of its quests starts on your way", d.reason)
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
  local HERE = { 1439, 38.0, 41.0 }   -- the player's feet in S20

  describe("choosing between dungeons", function()
    it("takes the cheaper trip when the quest XP is the same", function()
      local d = Engine.compute(withDungeon("NEAR", 9100, { entrance = HERE }), S20).dungeon
      assert.equals("NEAR", d.key)
      assert.same({ mapID = 1439, x = 38.0, y = 41.0 }, d.entrance)
    end)

    it("a farther entrance loses to BFD at the same XP", function()
      local far = { 1440, 90.0, 90.0 }   -- the far corner of BFD's zone
      local d = Engine.compute(withDungeon("FAR", 9100, { entrance = far }), S20).dungeon
      assert.equals("BFD", d.key)
    end)

    it("takes the dungeon with more quest XP", function()
      local db2 = withDungeon("RICH", 9100, { quests = { 9101, 9102, 9103, 9104 } })
      -- same entrance and quests as BFD, but one RICH quest is worth far more
      db2.data.quests[9101][17] = 50000
      assert.equals("RICH", Engine.compute(db2, S20).dungeon.key)
    end)

    it("breaks an exact tie by the lower key", function()
      local lower = Engine.compute(withDungeon("ABD", 9100), S20).dungeon
      assert.equals("ABD", lower.key)
      local higher = Engine.compute(withDungeon("ZFD", 9100), S20).dungeon
      assert.equals("BFD", higher.key)
    end)

    it("skips a dungeon that is not live", function()
      local db2 = withDungeon("NEAR", 9100, { entrance = HERE, live = false })
      assert.equals("BFD", Engine.compute(db2, S20).dungeon.key)
    end)

    it("skips a dungeon of the other faction", function()
      local db2 = withDungeon("NEAR", 9100, { entrance = HERE, faction = 2 })
      assert.equals("BFD", Engine.compute(db2, S20).dungeon.key)
    end)

    it("keeps a dungeon of the player's own faction", function()
      local db2 = withDungeon("NEAR", 9100, { entrance = HERE, faction = 1 })
      assert.equals("NEAR", Engine.compute(db2, S20).dungeon.key)
    end)

    it("skips a dungeon the player has outgrown", function()
      local db2 = withDungeon("LOW", 9100, { entrance = HERE, minLevel = 10, maxLevel = 19 })
      assert.equals("BFD", Engine.compute(db2, S20).dungeon.key)
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
    local function lowQuestDb(level)
      return dbWith(function(data) data.quests[1199][6] = level end)
    end

    it("scores quest XP at the dungeon's minimum level for a lower-level player", function()
      -- level 14 is x0.4 at 22 (900) but would be x0.8 at the player's 20 (1800)
      assert.equals(7050, Engine.compute(lowQuestDb(14), S20).dungeon.xp)
    end)

    it("scores quest XP at the player's level once above the minimum", function()
      -- level 19 is x0.8 at 25 (1800) but would be x1.0 at the minimum 22 (2250)
      assert.equals(7950, Engine.compute(lowQuestDb(19), with(S20, { level = 25 })).dungeon.xp)
    end)
  end)
end)
