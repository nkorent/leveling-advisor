local H = require("spec.helpers.engine")

-- Level fit (0.3.0): every candidate carries its difficulty colour (`fit`), and the quests that
-- are too high for now get the status `later`: an eligible orange quest, every `soon` quest and
-- an in-progress quest that is orange or red. A complete quest is never later.
describe("Candidates level fit", function()
  local ns, db
  local S18, with = H.states.S18, H.with

  before_each(function()
    ns = H.load()
    db = ns.DB.new(H.data())
  end)

  local function dbWith(edit)
    local data = H.data()
    edit(data.quests)
    return ns.DB.new(data)
  end

  local function cand(d, s, id)
    return H.candidateFor(ns.Candidates.build(d, s), id)
  end

  it("an eligible orange quest is later (991 is level 21 at 18)", function()
    local c = cand(db, S18, 991)
    assert.same({ "later", "orange", "eligible" }, { c.status, c.fit, c.baseStatus })
  end)

  it("a soon quest is later, class quests too", function()
    local d = dbWith(function(q)
      q[4763][5] = 19 -- requiredLevel 19 at level 18
      q[5061][5] = 19 -- the druid class quest
    end)
    for _, id in ipairs({ 4763, 5061 }) do
      local c = cand(d, S18, id)
      assert.same({ "later", "soon" }, { c.status, c.baseStatus }, "quest " .. id)
    end
    -- a soon quest of a fitting colour is later all the same
    assert.equals("yellow", cand(d, S18, 4763).fit)
  end)

  it("yellow and green quests stay eligible", function()
    local yellow, green = cand(db, S18, 4763), cand(db, S18, 1081)
    assert.same({ "eligible", "yellow" }, { yellow.status, yellow.fit })
    assert.same({ "eligible", "green" }, { green.status, green.fit })
  end)

  it("an in-progress quest is later when it is orange or red", function()
    -- 991 is level 21 (orange at 18), 1275 level 24 (red at 18)
    local s = with(S18, { log = { [966] = { complete = false }, [991] = { complete = false },
      [1275] = { complete = false } } })
    local c = ns.Candidates.build(db, s)
    assert.same({ "later", "orange", "progress" },
      { H.candidateFor(c, 991).status, H.candidateFor(c, 991).fit, H.candidateFor(c, 991).baseStatus })
    assert.same({ "later", "red" }, { H.candidateFor(c, 1275).status, H.candidateFor(c, 1275).fit })
    -- a yellow quest in the log stays in progress
    assert.same({ "progress", "yellow" }, { H.candidateFor(c, 966).status, H.candidateFor(c, 966).fit })
  end)

  it("a complete quest is never later, whatever its colour", function()
    local s = with(S18, { log = { [991] = { complete = true }, [1275] = { complete = true } } })
    local c = ns.Candidates.build(db, s)
    assert.same({ "complete", "orange" }, { H.candidateFor(c, 991).status, H.candidateFor(c, 991).fit })
    assert.same({ "complete", "red" }, { H.candidateFor(c, 1275).status, H.candidateFor(c, 1275).fit })
  end)

  it("the colour uses the player's real grey level", function()
    -- 1081 is level 15: green with the formula's grey level (12), grey when the game says 15
    assert.equals("green", cand(db, S18, 1081).fit)
    local s = with(S18, { greyAtOrBelow = 15, log = { [1081] = { complete = false } } })
    assert.equals("grey", cand(db, s, 1081).fit)
  end)

  describe("recommendable", function()
    local R
    before_each(function() R = ns.Candidates.recommendable end)

    it("eligible and in-progress quests only when yellow or green", function()
      assert.is_true(R({ status = "eligible", fit = "yellow" }))
      assert.is_true(R({ status = "eligible", fit = "green" }))
      assert.is_true(R({ status = "progress", fit = "yellow" }))
      assert.is_true(R({ status = "progress", fit = "green" }))
      assert.is_false(R({ status = "progress", fit = "grey" }))
      assert.is_false(R({ status = "eligible", fit = "orange" }))
      assert.is_false(R({ status = "eligible" })) -- no colour, no recommendation
    end)

    it("a complete quest at any colour (it stays a turn-in)", function()
      for _, fit in ipairs({ "yellow", "green", "orange", "red", "grey" }) do
        assert.is_true(R({ status = "complete", fit = fit }), fit)
      end
    end)

    it("never a later or soon quest", function()
      assert.is_false(R({ status = "later", fit = "yellow" }))
      assert.is_false(R({ status = "soon", fit = "yellow" }))
    end)

    it("a grey quest in the log is not recommended, and not later either", function()
      local s = with(S18, { greyAtOrBelow = 15, log = { [1081] = { complete = false } } })
      local c = cand(db, s, 1081)
      assert.equals("progress", c.status)
      assert.is_false(R(c))
    end)
  end)
end)
