local H = require("spec.helpers.engine")

describe("Geo and Hubs", function()
  local ns, db, Geo, Hubs
  before_each(function()
    ns = H.load()
    db = ns.DB.new(H.data())
    Geo, Hubs = ns.Geo, ns.Hubs
  end)

  it("same-map yards", function() -- Darkshore 6000x4000: 1 unit = 60 x 40 yd
    assert.near(50.9, Geo.distance(db, { 1439, 38.0, 41.0 }, { 1439, 37.4, 40.1 }), 0.1)
  end)

  it("accepts named points", function()
    local d = Geo.distance(db, { mapID = 1439, x = 38.0, y = 41.0 }, { mapID = 1439, x = 37.4, y = 40.1 })
    assert.near(50.9, d, 0.1)
  end)

  it("default size when yards missing", function()
    local data = H.data()
    local zones = {}
    for k, v in pairs(data.zones) do zones[k] = v end
    local z = {}
    for k, v in pairs(zones[1439]) do z[k] = v end
    z.yards = nil
    zones[1439] = z
    local copy = {}
    for k, v in pairs(data) do copy[k] = v end
    copy.zones = zones
    local db2 = ns.DB.new(copy)
    local w, h = Geo.zoneYards(db2, 1439)
    assert.equals(3000, w); assert.equals(2000, h)
    assert.near(30, Geo.distance(db2, { 1439, 10, 10 }, { 1439, 11, 10 }), 0.001)
    assert.near(20, Geo.distance(db2, { 1439, 10, 10 }, { 1439, 10, 11 }), 0.001)
  end)

  it("cross-zone on one continent uses rects and continent yards", function()
    -- zone centres: Darkshore (0.45, 0.225), Ashenvale (0.425, 0.415) of a
    -- 36800 x 24533 yd continent: dx = 920 yd, dy = 4661.3 yd
    local d, same = Geo.distance(db, { 1439, 50, 50 }, { 1440, 50, 50 })
    assert.is_true(same)
    assert.near(4751.2, d, 0.1)
  end)

  local function dbWithZones(edit)
    local data = H.data() -- a fresh copy on every call
    edit(data)
    return ns.DB.new(data)
  end

  it("same continent but one zone has no rect -> nil yards, still the same continent", function()
    local d2 = dbWithZones(function(data) data.zones[1440].rect = nil end)
    local d, same = Geo.distance(d2, { 1439, 50, 50 }, { 1440, 50, 50 })
    assert.is_nil(d); assert.is_true(same)
    d, same = Geo.distance(d2, { 1440, 50, 50 }, { 1439, 50, 50 })
    assert.is_nil(d); assert.is_true(same)
  end)

  it("same continent but no continent yards -> nil yards, still the same continent", function()
    local d2 = dbWithZones(function(data) data.continents = {} end)
    local d, same = Geo.distance(d2, { 1439, 50, 50 }, { 1440, 50, 50 })
    assert.is_nil(d); assert.is_true(same)
  end)

  it("other continent -> nil", function()
    local d, same = Geo.distance(db, { 1439, 50, 50 }, { 1432, 50, 50 })
    assert.is_nil(d); assert.is_false(same)
  end)

  it("nil coordinates or map -> nil, false, no error", function()
    local d, same = Geo.distance(db, { 1439, nil, 50 }, { 1439, 50, 50 })
    assert.is_nil(d); assert.is_false(same)
    d, same = Geo.distance(db, { nil, 50, 50 }, { 1439, 50, 50 })
    assert.is_nil(d); assert.is_false(same)
  end)

  it("continentPoint", function()
    local c, cx, cy = Geo.continentPoint(db, 1439, 50, 50)
    assert.equals(1414, c); assert.near(0.45, cx, 1e-9); assert.near(0.225, cy, 1e-9)
  end)

  it("clusters within radius and splits beyond it", function()
    local hubs = Hubs.cluster(db, {
      { 1439, 37.4, 40.1, "a" }, { 1439, 38.0, 41.0, "b" },
      { 1439, 55.0, 24.9, "c" }, { 1440, 37.4, 40.1, "d" } }, 150)
    assert.equals(3, #hubs); assert.same({ "a", "b" }, hubs[1].members)
    assert.near(37.7, hubs[1].x, 1e-9); assert.near(40.55, hubs[1].y, 1e-9)
    assert.equals(1440, hubs[3].mapID)
  end)


  it("fails soft on points with nil fields", function()
    local hubs
    assert.has_no.errors(function()
      hubs = Hubs.cluster(db, {
        { nil, 50, 50, "a" }, { 1439, nil, 50, "b" }, { 1439, 50, nil, "c" }, { 1439, 50, 50, "d" },
      }, 150)
    end)
    assert.equals(4, #hubs)
  end)

  it("makes every point its own hub when the radius is not positive", function()
    for _, r in ipairs({ 0, -5 }) do
      local hubs = Hubs.cluster(db, { { 1439, 50, 50, "a" }, { 1439, 50, 50, "b" } }, r)
      assert.equals(2, #hubs)
    end
  end)

  describe("equivalence with the O(n*h) reference", function()
    local reference = require("spec.helpers.hubs_reference")

    -- Seeded LCG; every product stays below 2^53 (same form as helpers/synthetic).
    local function lcg(seed)
      local st = seed
      return function(n) -- integer in [0, n)
        st = ((st * 16838 % 32768) * 65536 + st * 20077 + 12345) % 2147483648
        return math.floor(st / 65536) % n
      end
    end

    local function assertSame(expected, actual)
      assert.equals(#expected, #actual)
      for i, e in ipairs(expected) do
        local a = actual[i]
        assert.equals(e.mapID, a.mapID)
        assert.same(e.members, a.members)
        assert.is_true(math.abs(e.x - a.x) <= 1e-9)
        assert.is_true(math.abs(e.y - a.y) <= 1e-9)
      end
    end

    it("matches on 300 random point sets", function()
      local rnd = lcg(20261125)
      local maps = { 1439, 1440, 1432 }
      local radii = { 50, 150, 400 }
      for set = 1, 300 do
        local mapCount = 2 + rnd(2)
        local radius = radii[1 + rnd(#radii)]
        -- a few centres per map with jitter, so points really do join hubs
        local centres = {}
        for m = 1, mapCount do
          centres[m] = {}
          for c = 1, 3 do centres[m][c] = { 5 + rnd(900) / 10, 5 + rnd(900) / 10 } end
        end
        local points = {}
        for i = 1, 20 + rnd(40) do
          local m = 1 + rnd(mapCount)
          local c = centres[m][1 + rnd(3)]
          local x = c[1] + (rnd(81) - 40) / 10
          local y = c[2] + (rnd(81) - 40) / 10
          points[i] = { maps[m], x, y, set * 1000 + i }
        end
        assertSame(reference(ns, db, points, radius), Hubs.cluster(db, points, radius))
      end
    end)

    it("joins the first hub when a point is equidistant from two", function()
      -- Darkshore 6000x4000: 1 x-unit = 60 yd. Hubs 120 yd apart, radius 70.
      local points = { { 1439, 10, 50, "a" }, { 1439, 12, 50, "b" }, { 1439, 11, 50, "c" } }
      local hubs = Hubs.cluster(db, points, 70)
      assert.equals(2, #hubs)
      assert.same({ "a", "c" }, hubs[1].members)
      assert.same({ "b" }, hubs[2].members)
      assertSame(reference(ns, db, points, 70), hubs)
    end)

    it("joins a point exactly at the radius", function()
      -- 1 y-unit = 40 yd
      local points = { { 1439, 10, 50, "a" }, { 1439, 10, 51, "b" } }
      assert.equals(1, #Hubs.cluster(db, points, 40))
      assert.equals(2, #Hubs.cluster(db, points, 39.99))
    end)

    it("still finds a centroid that drifted across a grid cell boundary", function()
      -- radius 100 -> cell 101 yd = 1.68 x-units; the centroid moves from 10 to 10.75
      -- (cell 5 -> 6), and 12.4 is only in range of the drifted centroid.
      local points = { { 1439, 10, 50, "a" }, { 1439, 11.5, 50, "b" }, { 1439, 12.4, 50, "c" } }
      local hubs = Hubs.cluster(db, points, 100)
      assert.equals(1, #hubs)
      assert.same({ "a", "b", "c" }, hubs[1].members)
      assertSame(reference(ns, db, points, 100), hubs)
    end)
  end)
end)
