local E = require("spec.helpers.engine")

describe("Tuning", function()
  local T
  before_each(function() T = E.load().Tuning end)

  it("exposes the starting constants", function()
    assert.equals(150, T.HUB_RADIUS_YD)
    assert.equals(3, T.SECTION_LIMITS.next)
    assert.equals(6, T.SECTION_LIMITS.here)
    assert.equals(4, T.SECTION_LIMITS.chains)
    assert.equals(500, T.LINK_XP.boat)
    assert.same({3000, 2000}, T.DEFAULT_ZONE_YARDS)
  end)
end)

describe("Tuning invariants", function()
  it("holds the values the engine relies on", function()
    local T = E.load().Tuning
    assert.is_true(T.ROUTE_IMPROVE_MIN_GAIN_YD > 0)
    assert.is_true(T.ROUTE_IMPROVE_MAX_PASSES >= 1)
    assert.is_true(T.ROUTE_IMPROVE_MAX_CANDIDATES > 0)
    assert.is_true(T.HUB_RADIUS_YD > 0)
    assert.is_true(T.RIGHT_HERE_YD > 0)
  end)
end)

describe("spec helpers", function()
  it("with() shallow-copies and overrides without mutating base", function()
    local base = { a = 1, nested = { x = 1 } }
    local s = E.with(base, { a = 2, nested = { y = 2 } })
    assert.equals(2, s.a)
    assert.equals(1, base.a)
    assert.is_nil(s.nested.x)
    assert.equals(2, s.nested.y)
  end)

  it("stepOf() returns the first step containing the action", function()
    local steps = {
      { actions = { { 1, "pickup" } } },
      { actions = { { 2, "pickup" }, { 1, "turnin" } } },
      { actions = { { 1, "turnin" } } },
    }
    assert.equals(2, E.stepOf(steps, 1, "turnin"))
    assert.equals(1, E.stepOf(steps, 1, "pickup"))
    assert.is_nil(E.stepOf(steps, 9, "pickup"))
  end)

  it("ids(), keys(), find(), pickupIDs() read named fields", function()
    local sections = { { key = "here", rows = { { questID = 5 }, { questID = 7 } } }, { key = "next", rows = {} } }
    assert.same({5, 7}, E.ids(sections[1]))
    assert.same({"here", "next"}, E.keys(sections))
    assert.equals(sections[2], E.find(sections, "next"))
    assert.is_nil(E.find(sections, "nope"))
    assert.same({3, 4}, E.pickupIDs({ pickups = { { questID = 3 }, { questID = 4 } } }))
  end)
end)
