local H = require("spec.helpers.engine")

describe("Travel", function()
  local ns, db, Travel
  local S18, H20, with = H.states.S18, H.states.H20, H.with
  local reach

  before_each(function()
    ns = H.load()
    db = ns.DB.new(H.data())
    Travel = ns.Travel
    reach = Travel.fromPlayer(db, S18)
  end)

  it("costs nothing in the player's zone", function()
    assert.equals(0, reach[1439].xp)
  end)

  it("walks to a neighbour and arrives at the link back", function()
    assert.near(400.9, reach[1440].xp, 0.1)
    assert.same({ 1440, 40, 5 }, reach[1440].arrive)
    assert.near(767.7, Travel.costTo(db, reach, S18, { 1440, 50, 50 }), 0.1)
  end)

  it("adds the boat fare", function()
    assert.near(575.9, reach[1432].xp, 0.1)
    assert.same({ "boat from Auberdine" }, reach[1432].hops)
  end)

  it("chains hops and skips the other faction's transport", function()
    local r = Travel.fromPlayer(db, with(S18, { mapID = 1440, x = 40, y = 10 }))
    assert.same({ "walk north", "boat from Auberdine" }, r[1432].hops)
    assert.near(938.4, r[1432].xp, 0.1)
  end)

  it("passes through the other faction's non-city zone", function()
    assert.same({ "walk south", "walk east" }, reach[1411].hops)
    local h = Travel.fromPlayer(db, H20)
    assert.same({ "walk west", "walk north" }, h[1439].hops)
    assert.same({ "walk west" }, h[1440].hops)
  end)

  it("falls back without a path", function()
    local d2 = ns.DB.new((function()
      local data = H.data()
      data.zones[1440].links = { { to = 1411, kind = "walk", x = 90, y = 50, label = "walk east" } }
      return data
    end)())
    assert.equals(4000, Travel.costTo(d2, Travel.fromPlayer(d2, H20), H20, { 1432, 50, 50 }))
  end)

  it("returns an empty reach when the player's map is unknown", function()
    local s = with(S18, {})
    s.mapID = nil
    local r
    assert.has_no.errors(function() r = Travel.fromPlayer(db, s) end)
    assert.same({}, r)
  end)

  it("start zone has empty hops", function()
    assert.same({}, reach[1439].hops)
  end)

  local function dbWithZones(edit)
    local data = H.data() -- a fresh copy on every call
    edit(data)
    return ns.DB.new(data)
  end

  it("falls back to the straight line on the same continent when no path leads there", function()
    -- with the Ashenvale-Darkshore border cut, Durotar cannot reach Darkshore but both are on Kalimdor:
    -- 9882.1 yd * 0.2 XP per yard
    local d2 = dbWithZones(function(data)
      data.zones[1440].links = { { to = 1411, kind = "walk", x = 90, y = 50, label = "walk east" } }
    end)
    local r = Travel.fromPlayer(d2, H20)
    assert.near(1976.4, Travel.costTo(d2, r, H20, { 1439, 50, 50 }), 0.1)
  end)

  it("keeps the cheaper of two routes to a zone", function()
    -- the direct link to Ashenvale becomes a zeppelin (500 XP: 900.9 in all);
    -- via Loch Modan's portal it costs 575.9 + 200 = 775.9
    local d2 = dbWithZones(function(data)
      data.zones[1439].links[1].kind = "zeppelin"
      data.zones[1432].links = { { to = 1440, kind = "portal", x = 50, y = 50, label = "portal to Ashenvale" } }
    end)
    local r = Travel.fromPlayer(d2, S18)
    assert.near(775.9, r[1440].xp, 0.1)
    assert.same({ "boat from Auberdine", "portal to Ashenvale" }, r[1440].hops)
  end)

  it("keeps the direct route when the detour costs more", function()
    -- direct zeppelin: 900.9; via Loch Modan: 575.9 + 500 (boat) = 1075.9. Loch
    -- Modan is settled before Ashenvale, so the detour is offered second.
    local d2 = dbWithZones(function(data)
      data.zones[1439].links[1].kind = "zeppelin"
      data.zones[1432].links = { { to = 1440, kind = "boat", x = 50, y = 50, label = "boat to Ashenvale" } }
    end)
    local r = Travel.fromPlayer(d2, S18)
    assert.near(900.9, r[1440].xp, 0.1)
    assert.same({ "walk south" }, r[1440].hops)
  end)

  it("marks a route approximate when a link has no position, and passes that on", function()
    local d2 = dbWithZones(function(data)
      data.zones[1439].links[1].x = nil
      data.zones[1439].links[1].y = nil
      local far = {}
      for k, v in pairs(data.zones[1440]) do far[k] = v end
      far.links = {}
      data.zones[1500] = far
      data.zones[1440].links[#data.zones[1440].links + 1] = { to = 1500, kind = "walk", x = 50, y = 50, label = "walk on" }
    end)
    local r = Travel.fromPlayer(d2, S18)
    assert.is_true(r[1440].approx)
    assert.is_true(r[1500].approx)
  end)

  it("does not mark an exact route approximate", function()
    assert.is_nil(reach[1440].approx)
    assert.is_nil(reach[1432].approx)
  end)

  describe("zone faction is not a travel wall", function()
    local function zone(faction, kind, links)
      return { name = "Z", continent = 1414, faction = faction, kind = kind, minLevel = 1, maxLevel = 60,
        live = true, complete = true, yards = { 5000, 3000 }, rect = { 0.1, 0.2, 0.1, 0.2 }, links = links or {} }
    end
    local function walk(to, x, y) return { to = to, kind = "walk", x = x, y = y, label = "walk to " .. to } end
    local function withChain(edit)
      return dbWithZones(function(data)
        data.zones[1440].links = { walk(1413, 90, 50) }
        data.zones[1413] = zone(2, nil, { walk(1440, 10, 50), walk(1445, 90, 50) })
        data.zones[1445] = zone(3, nil, { walk(1413, 10, 50) })
        if edit then edit(data) end
      end)
    end
    local at1440 = function() return with(S18, { mapID = 1440, x = 50, y = 50 }) end

    it("routes an Alliance player through a Horde non-city zone", function()
      local r = Travel.fromPlayer(withChain(), at1440())
      assert.same({ "walk to 1413", "walk to 1445" }, r[1445].hops)
      local d = withChain()
      local a = Travel.fromPlayer(d, at1440())
      local y1 = ns.Geo.distance(d, { 1440, 50, 50 }, { 1440, 90, 50 })
      local y2 = ns.Geo.distance(d, { 1413, 10, 50 }, { 1413, 90, 50 })
      assert.near((y1 + y2) * ns.Tuning.TRAVEL_XP_PER_YD, a[1445].xp, 0.1)
    end)

    it("never routes an Alliance player through the Horde capital, even when shorter", function()
      local d = withChain(function(data)
        data.zones[1454] = zone(2, "city", { walk(1440, 10, 50), walk(1445, 90, 50) })
        data.zones[1440].links[#data.zones[1440].links + 1] = walk(1454, 50, 50)
        data.zones[1445].links[#data.zones[1445].links + 1] = walk(1454, 10, 50)
      end)
      local r = Travel.fromPlayer(d, at1440())
      assert.is_nil(r[1454])
      assert.same({ "walk to 1413", "walk to 1445" }, r[1445].hops)
      local d2 = withChain(function(data)
        data.zones[1413].links = { walk(1440, 10, 50) }
        data.zones[1454] = zone(2, "city", { walk(1445, 90, 50) })
        data.zones[1440].links[#data.zones[1440].links + 1] = walk(1454, 50, 50)
      end)
      assert.is_nil(Travel.fromPlayer(d2, at1440())[1445])
    end)

    it("lets a Horde player pass through Horde capital and an Alliance non-city zone", function()
      local d = withChain(function(data)
        data.zones[1454] = zone(2, "city", { walk(1440, 10, 50) })
        data.zones[1440].links[#data.zones[1440].links + 1] = walk(1454, 50, 50)
        data.zones[1413] = zone(1, nil, { walk(1440, 10, 50), walk(1445, 90, 50) })
      end)
      local r = Travel.fromPlayer(d, with(H20, { mapID = 1440, x = 50, y = 50 }))
      assert.is_not_nil(r[1454])
      assert.is_not_nil(r[1445])
    end)

    it("never uses the other faction's zeppelin link", function()
      local d = withChain(function(data)
        data.zones[1440].links = { { to = 1445, kind = "zeppelin", x = 50, y = 50, label = "zep", faction = 2 } }
      end)
      assert.is_nil(Travel.fromPlayer(d, at1440())[1445])
      assert.same({ "zep" }, Travel.fromPlayer(d, with(H20, { mapID = 1440, x = 50, y = 50 }))[1445].hops)
    end)

    it("keeps a neutral city enterable for both factions", function()
      local d = withChain(function(data)
        data.zones[1413] = zone(3, "city", { walk(1440, 10, 50), walk(1445, 90, 50) })
      end)
      assert.is_not_nil(Travel.fromPlayer(d, at1440())[1445])
      assert.is_not_nil(Travel.fromPlayer(d, with(H20, { mapID = 1440, x = 50, y = 50 }))[1445])
    end)
  end)
end)
