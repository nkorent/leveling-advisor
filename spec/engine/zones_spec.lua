local H = require("spec.helpers.engine")

describe("Candidates and ZoneScore", function()
  local ns, db, Candidates, ZoneScore
  local S18, with = H.states.S18, H.with

  before_each(function()
    ns = H.load()
    db = ns.DB.new(H.data())
    Candidates, ZoneScore = ns.Candidates, ns.ZoneScore
  end)

  local function mapIDs(zones)
    local out = {}
    for i, z in ipairs(zones) do out[i] = z.mapID end
    return out
  end

  it("S18 ranks Darkshore, Ashenvale, Loch Modan with reasons", function()
    local z = ZoneScore.rank(db, S18, Candidates.build(db, S18))
    assert.same({ 1439, 1440, 1432 }, { z[1].mapID, z[2].mapID, z[3].mapID })
    assert.equals("You are here — finish before you leave", z[1].reason)
    assert.is_true(z[1].isHere)
    assert.equals("Next zone — walk south", z[2].reason)
    assert.equals("Alternative — boat from Auberdine", z[3].reason)
    assert.equals(6, z[1].questCount)
    assert.equals(7030, z[1].xp)
    assert.equals(1, z[1].chains)
    assert.equals(4, z[2].questCount)
  end)

  it("never names the other faction's transport as the reason", function()
    local s = with(S18, { mapID = 1440, x = 40, y = 10 })
    local z = ZoneScore.rank(db, s, Candidates.build(db, s))
    local found
    for _, r in ipairs(z) do
      if r.mapID == 1432 then found = r end
      assert.is_nil((r.reason or ""):find("zeppelin", 1, true))
    end
    assert.is_truthy(found)
    assert.equals("Most XP for your level", found.reason)
  end)

  it("S18 scores: 6825.0, 6207.3 and 324.1 (hub bonus, no travel at home, travel elsewhere)", function()
    local z = ZoneScore.rank(db, S18, Candidates.build(db, S18))
    assert.near(6825.0, z[1].score, 0.05)
    assert.near(6207.3, z[2].score, 0.05)
    assert.near(324.1, z[3].score, 0.05)
  end)

  it("never lists the other faction's zone", function()
    local z = ZoneScore.rank(db, S18, Candidates.build(db, S18))
    assert.same({ 1439, 1440, 1432 }, mapIDs(z)) -- Durotar (1411) is Horde-only
  end)

  it("elite setting off drops elite quests from candidates", function()
    local s = with(S18, { settings = { elite = false, dungeons = true } })
    assert.is_nil(H.candidateFor(Candidates.build(db, s), 1000))
  end)

  it("elite setting off keeps an elite quest that is in the log", function()
    local s = with(S18, {
      settings = { elite = false, dungeons = true },
      log = { [966] = { complete = false }, [4730] = { complete = true }, [1000] = { complete = false } },
    })
    local found = H.candidateFor(Candidates.build(db, s), 1000)
    assert.is_not_nil(found)
    assert.equals("progress", found.status)
  end)

  it("player's zone is not pinned when it has fewer than 2 quests", function()
    local s = with(S18, {
      completed = { [4762] = true, [965] = true, [4763] = true, [5061] = true, [1000] = true,
                    [7003] = true, [966] = true, [4730] = true },
      log = {},
    })
    local z = ZoneScore.rank(db, s, Candidates.build(db, s))
    -- Darkshore keeps one quest (1200 XP) and falls to second place
    assert.same({ 1440, 1439, 1432 }, mapIDs(z))
    assert.is_true(z[2].isHere)
  end)

  -- Hand-built candidates: one quest per entry, XP given directly.
  local function cand(id, mapID, x, y, xp, extra)
    local q = { id = id, zone = mapID, giver = { mapID = mapID, x = x, y = y } }
    for k, v in pairs(extra or {}) do q[k] = v end
    return { quest = q, status = "eligible", xp = xp }
  end
  -- The player stands in Darkshore (1439), so that zone has no travel cost.
  local function homeScore(list)
    local z = ZoneScore.rank(db, S18, list)
    assert.equals(1439, z[1].mapID)
    return z[1].score
  end

  describe("score formula", function()
    it("adds 25% per extra giver at the same hub", function()
      -- three givers at one spot: factor 1.5 each
      assert.near(4500, homeScore({
        cand(1, 1439, 40, 40, 1000), cand(2, 1439, 40, 40, 1000), cand(3, 1439, 40, 40, 1000),
      }), 1e-6)
    end)

    it("does not give a hub bonus to givers that are far apart", function()
      assert.near(3000, homeScore({
        cand(1, 1439, 10, 10, 1000), cand(2, 1439, 50, 50, 1000), cand(3, 1439, 90, 90, 1000),
      }), 1e-6)
    end)

    it("caps the hub bonus at +100%", function()
      -- six givers at one spot: 1 + min(0.25 * 5, 1.0) = 2.0 each, not 2.25
      local list = {}
      for i = 1, 6 do list[i] = cand(i, 1439, 40, 40, 1000) end
      assert.near(12000, homeScore(list), 1e-6)
    end)

    it("halves elite and group quests", function()
      assert.near(2000, homeScore({
        cand(1, 1439, 10, 10, 1000),
        cand(2, 1439, 50, 50, 1000, { elite = true }),
        cand(3, 1439, 90, 90, 1000, { groupSize = 2 }),
      }), 1e-6) -- 1000 + 500 + 500
    end)

    it("subtracts travel for a zone the player is not in", function()
      local z = ZoneScore.rank(db, S18, { cand(1, 1440, 50, 50, 1000), cand(2, 1439, 10, 10, 100), cand(3, 1439, 90, 90, 100) })
      -- Ashenvale: 1000 minus the walk there (767.7 to its centre)
      assert.same({ 1439, 1440 }, mapIDs(z))
      assert.near(232.3, z[2].score, 0.1)
    end)
  end)

  describe("ordering and limits", function()
    local function zoneDb(extra)
      local data = H.data()
      for _, id in ipairs(extra) do
        local z = {}
        for k, v in pairs(data.zones[1440]) do z[k] = v end
        z.name = "Zone " .. id
        z.links = {}
        data.zones[id] = z
      end
      return ns.DB.new(data)
    end

    it("pins the player's zone first when it has 2 quests, despite a lower score", function()
      local z = ZoneScore.rank(db, S18, {
        cand(1, 1439, 10, 10, 100), cand(2, 1439, 90, 90, 100), cand(3, 1440, 50, 50, 5000),
      })
      assert.same({ 1439, 1440 }, mapIDs(z))
      assert.is_true(z[1].score < z[2].score)
    end)

    it("does not pin the player's zone with one quest", function()
      local z = ZoneScore.rank(db, S18, { cand(1, 1439, 10, 10, 100), cand(3, 1440, 50, 50, 5000) })
      assert.same({ 1440, 1439 }, mapIDs(z))
    end)

    it("keeps only the best 3 zones", function()
      local d = zoneDb({ 1500, 1501, 1502, 1503 })
      local z = ZoneScore.rank(d, S18, {
        cand(1, 1500, 50, 50, 40000), cand(2, 1501, 50, 50, 30000),
        cand(3, 1502, 50, 50, 20000), cand(4, 1503, 50, 50, 10000),
      })
      assert.same({ 1500, 1501, 1502 }, mapIDs(z))
    end)

    it("sorts equal scores by ascending map ID", function()
      local d = zoneDb({ 1500, 1501 })
      -- the 1501 quest has the lower ID, so it is seen first; the sort must still put 1500 first
      local z = ZoneScore.rank(d, S18, { cand(1, 1501, 50, 50, 9000), cand(2, 1500, 50, 50, 9000) })
      assert.equals(z[1].score, z[2].score)
      assert.same({ 1500, 1501 }, mapIDs(z))
    end)
  end)
end)

describe("ZoneScore zone kind", function()
  local ns, Candidates, ZoneScore
  before_each(function()
    ns = H.load()
    Candidates, ZoneScore = ns.Candidates, ns.ZoneScore
  end)

  local function rank(kindZone, kind, state)
    local data = H.data()
    data.zones[kindZone].kind = kind
    local db = ns.DB.new(data)
    return ZoneScore.rank(db, state, Candidates.build(db, state))
  end

  it("never recommends a city, even when the player stands in it", function()
    for _, z in ipairs(rank(1439, "city", H.states.S18)) do assert.not_equals(1439, z.mapID) end
  end)
  it("never recommends a battleground", function()
    for _, z in ipairs(rank(1439, "battleground", H.states.S18)) do assert.not_equals(1439, z.mapID) end
  end)
  it("skips a city with the most XP", function()
    local s = H.with(H.states.S18, { mapID = 1440, x = 40, y = 10 })
    for _, z in ipairs(rank(1439, "city", s)) do assert.not_equals(1439, z.mapID) end
    assert.is_truthy(rank(1439, nil, s)[1])
  end)
  it("an unknown kind is a leveling zone", function()
    assert.equals(1439, rank(1439, "dungeon", H.states.S18)[1].mapID)
  end)
  it("its quests still appear in Right Here", function()
    local data = H.data()
    data.zones[1439].kind = "city"
    local db = ns.DB.new(data)
    local c = Candidates.build(db, H.states.S18)
    local sections = ns.Sections.build(db, H.states.S18, c, ZoneScore.rank(db, H.states.S18, c))
    assert.is_truthy(H.find(sections, "here"))
  end)
end)
