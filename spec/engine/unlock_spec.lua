local H = require("spec.helpers.engine")

describe("Unlock.path", function()
  local ns
  before_each(function() ns = H.load() end)

  -- Contract A quest record: a both-factions level-20 quest (required 18) given in Durotar.
  -- o: faction, level, requiredLevel, xp, raceMask, classMask, all, any, exclusiveTo,
  -- breadcrumbOf, requiredMaxLevel, unavailableAfter; noGiver drops the giver (no-data).
  local function Q(name, o)
    o = o or {}
    local r = {}
    r[1] = name; r[2] = o.faction or 3; r[3] = o.raceMask; r[4] = o.classMask
    r[5] = o.requiredLevel or 18; r[6] = o.level or 20; r[7] = 1; r[8] = 1411; r[9] = 0
    if not o.noGiver then r[11] = { 1, 3001, 1411, 50, 50 } end
    r[17] = o.xp or 1000; r[18] = 1
    if o.all or o.any then r[19] = { all = o.all, any = o.any } end
    r[20] = o.exclusiveTo; r[21] = o.breadcrumbOf; r[24] = o.requiredMaxLevel; r[25] = o.unavailableAfter
    return r
  end

  -- Contract A questStubs record. o: faction, raceMask, classMask, all.
  local function stub(name, o)
    o = o or {}
    return { name, 20, 18, o.faction, o.raceMask, o.classMask, o.all and { all = o.all } or nil,
      { kind = 3, name = "Damp Note" }, "no-giver-coords" }
  end

  -- A level-20 Horde orc warrior; o overrides fields.
  local function player(o)
    return H.with({
      faction = "Horde", raceMask = 2, classMask = 1, classFile = "WARRIOR",
      level = 20, mapID = 1411, x = 50, y = 50,
      completed = {}, log = {}, ignored = {}, recordedXP = {},
      settings = { elite = true, dungeons = true },
    }, o)
  end

  local db
  local function path(quests, id, state, stubs)
    db = ns.DB.new({ quests = quests, questStubs = stubs })
    return ns.Unlock.path(db, id, state or player())
  end

  local function field(p, key)
    local out = {}
    for i, s in ipairs(p.steps) do out[i] = s[key] end
    return out
  end

  local A, B, C, D, E, X, Y, Z = 101, 102, 103, 104, 105, 201, 202, 203

  it("linear chain orders earliest first", function()
    local p = path({ [A] = Q("A"), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { B } }) }, C)
    assert.same({ A, B }, field(p, "questID"))
    assert.same({ 1, 2 }, field(p, "number"))
    assert.same({ "A", "B" }, field(p, "name"))
    assert.equals(C, p.questID)
    assert.equals(2, p.total)
    assert.is_nil(p.steps[1].group)
    assert.same({ kind = 1, id = 3001, mapID = 1411, x = 50, y = 50 }, p.steps[1].giver)
  end)

  it("states: done, start, locked", function()
    local quests = { [A] = Q("A"), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { B } }),
      [D] = Q("D", { all = { C } }) }
    local p = path(quests, C, player({ completed = { [A] = true } }))
    assert.same({ "done", "start" }, field(p, "status"))
    assert.equals("completed", p.steps[1].reason)
    assert.equals(2, p.first)
    assert.equals(1, p.done)
    assert.equals(1, p.remaining)
    assert.is_false(p.blocked)

    p = path(quests, D, player({ completed = { [A] = true } }))
    assert.same({ "done", "start", "locked" }, field(p, "status"))
    assert.equals("prereq", p.steps[3].reason)
    assert.equals(2, p.first)
    assert.equals(2, p.remaining)
  end)

  it("a step a level or two above the player is locked by level", function()
    local p = path({ [A] = Q("A", { requiredLevel = 21, level = 22 }), [B] = Q("B", { all = { A } }) }, B)
    assert.equals("locked", p.steps[1].status)
    assert.equals("level", p.steps[1].reason)
    assert.is_nil(p.first)
  end)

  it("parallel prerequisites form a needs-all group", function()
    local p = path({ [A] = Q("A"), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { A } }),
      [D] = Q("D", { all = { B, C } }) }, D)
    assert.same({ A, B, C }, field(p, "questID"))
    assert.is_nil(p.steps[1].group)
    assert.same({ kind = "all", id = 2, size = 2 }, p.steps[2].group)
    assert.same({ kind = "all", id = 2, size = 2 }, p.steps[3].group)
    assert.same({ 1, 2, 3 }, field(p, "number"))
    assert.equals(3, p.total)
  end)

  it("any-list unsatisfied becomes one-of group counted once", function()
    local p = path({ [X] = Q("X"), [Y] = Q("Y"), [E] = Q("E", { any = { X, Y } }) }, E)
    assert.same({ X, Y }, field(p, "questID"))
    assert.equals("any", p.steps[1].group.kind)
    assert.equals(2, p.steps[1].group.size)
    assert.same(p.steps[1].group, p.steps[2].group)
    assert.same({ 1, 1 }, field(p, "number"))
    assert.equals(1, p.total)
    assert.equals(1, p.remaining)
  end)

  it("any-list satisfied adds nothing", function()
    local quests = { [X] = Q("X"), [Y] = Q("Y"), [E] = Q("E", { any = { X, Y } }) }
    assert.is_nil(path(quests, E, player({ completed = { [X] = true } })))
  end)

  it("puts an any-group one layer after the required steps before it", function()
    local p = path({ [A] = Q("A"), [B] = Q("B", { all = { A } }), [X] = Q("X"), [Y] = Q("Y"),
      [E] = Q("E", { all = { B }, any = { X, Y } }) }, E)
    assert.same({ A, B, X, Y }, field(p, "questID"))
    assert.same({ 1, 2, 3, 3 }, field(p, "number"))
    assert.equals(3, p.total)
  end)

  it("shares one group between identical any-lists", function()
    local p = path({ [X] = Q("X"), [Y] = Q("Y"), [A] = Q("A", { any = { X, Y } }), [B] = Q("B", { any = { X, Y } }),
      [E] = Q("E", { all = { A, B } }) }, E)
    assert.same({ X, Y, A, B }, field(p, "questID"))
    assert.equals("any", p.steps[1].group.kind)
    assert.same({ kind = "all", id = 2, size = 2 }, p.steps[3].group)
    assert.equals(3, p.total)
  end)

  it("shares a group between any-lists that are the same set in another order", function()
    local p = path({ [X] = Q("X"), [Y] = Q("Y"), [A] = Q("A", { any = { X, Y } }), [B] = Q("B", { any = { Y, X } }),
      [E] = Q("E", { all = { A, B } }) }, E)
    assert.same({ X, Y, A, B }, field(p, "questID"))
    assert.equals(3, p.total)
  end)

  it("gives overlapping (not identical) any-lists a group each, every option shown", function()
    local quests = { [X] = Q("X"), [Y] = Q("Y"), [Z] = Q("Z"), [A] = Q("A", { any = { X, Y } }),
      [B] = Q("B", { any = { Y, Z } }), [E] = Q("E", { all = { A, B } }) }
    local p = path(quests, E)
    assert.same({ X, Y, Y, Z, A, B }, field(p, "questID"))
    assert.same({ kind = "any", id = 1, size = 2 }, p.steps[1].group)
    assert.same({ kind = "any", id = 2, size = 2 }, p.steps[3].group)
    assert.equals(4, p.total)
    assert.equals(0, p.done)

    -- X done satisfies A's list only: B still needs Y or Z (A is now a root, in layer 1
    -- ahead of the group)
    p = path(quests, E, player({ completed = { [X] = true } }))
    assert.same({ A, Y, Z, B }, field(p, "questID"))
    assert.same({ kind = "any", id = 1, size = 2 }, p.steps[2].group)
    assert.equals(3, p.total)
    assert.equals(0, p.done)
  end)

  it("adds no group when an option is already a required step", function()
    local p = path({ [X] = Q("X"), [Y] = Q("Y"), [A] = Q("A", { any = { X, Y } }),
      [E] = Q("E", { all = { A, X } }) }, E)
    assert.same({ X, A }, field(p, "questID"))
    assert.is_nil(p.steps[1].group)
    assert.equals(2, p.total)
  end)

  it("blocks an any-group only when all its options are blocked", function()
    local quests = { [X] = Q("X", { faction = 1 }), [Y] = Q("Y"), [E] = Q("E", { any = { X, Y } }) }
    local p = path(quests, E)
    assert.same({ "blocked", "start" }, field(p, "status"))
    assert.is_false(p.blocked)
    assert.equals(2, p.first)

    quests[Y] = Q("Y", { faction = 1 })
    assert.is_true(path(quests, E).blocked)
  end)

  it("stub step is unknown, never start", function()
    local p = path({ [E] = Q("E", { all = { A } }) }, E, nil, { [A] = stub("Damp Note") })
    local s = p.steps[1]
    assert.equals("unknown", s.status)
    assert.equals("stub", s.reason)
    assert.equals("Damp Note", s.name)
    assert.equals(20, s.level)
    assert.is_nil(s.giver)
    assert.equals(db:stub(A), s.stub)
    assert.is_nil(p.first)
    assert.is_false(p.blocked)
  end)

  it("walks a stub's own prerequisites", function()
    local p = path({ [A] = Q("A"), [E] = Q("E", { all = { B } }) }, E, nil, { [B] = stub("S", { all = { A } }) })
    assert.same({ A, B }, field(p, "questID"))
    assert.same({ "start", "unknown" }, field(p, "status"))
  end)

  it("stub of the other faction blocks the path", function()
    local p = path({ [E] = Q("E", { all = { A } }) }, E, nil, { [A] = stub("S", { faction = 1 }) })
    assert.equals("blocked", p.steps[1].status)
    assert.equals("faction", p.steps[1].reason)
    assert.is_true(p.blocked)
    assert.is_nil(p.first)
  end)

  it("stub with a race or class mask that excludes the player is blocked", function()
    local stubs = { [A] = stub("S", { faction = 3, raceMask = 1 }) }
    local p = path({ [E] = Q("E", { all = { A } }) }, E, nil, stubs)
    assert.same({ "blocked", "race" }, { p.steps[1].status, p.steps[1].reason })

    stubs[A] = stub("S", { faction = 2, raceMask = 2, classMask = 4 })
    p = path({ [E] = Q("E", { all = { A } }) }, E, nil, stubs)
    assert.same({ "blocked", "class" }, { p.steps[1].status, p.steps[1].reason })

    stubs[A] = stub("S", { faction = 2, raceMask = 2 + 16, classMask = 1 })
    p = path({ [E] = Q("E", { all = { A } }) }, E, nil, stubs)
    assert.same({ "unknown", "stub" }, { p.steps[1].status, p.steps[1].reason })
  end)

  it("missing prerequisite", function()
    local p = path({ [E] = Q("E", { all = { A } }) }, E)
    local s = p.steps[1]
    assert.equals(A, s.questID)
    assert.equals("unknown", s.status)
    assert.equals("missing", s.reason)
    assert.is_nil(s.name)
    assert.is_nil(s.stub)
    assert.is_false(p.blocked)
  end)

  it("grey prerequisite is still startable", function()
    local p = path({ [A] = Q("A", { requiredLevel = 5, level = 8 }), [E] = Q("E", { all = { A } }) }, E)
    assert.equals("start", p.steps[1].status)
    assert.equals("grey", p.steps[1].reason)
    assert.equals(1, p.first)
  end)

  it("in-log step is progress", function()
    local p = path({ [A] = Q("A"), [E] = Q("E", { all = { A } }) }, E, player({ log = { [A] = { complete = false } } }))
    assert.equals("progress", p.steps[1].status)
    assert.equals("in-log", p.steps[1].reason)
    assert.equals(1, p.remaining)
    assert.is_nil(p.first)
  end)

  it("other-faction prerequisite is blocked", function()
    local p = path({ [A] = Q("A", { faction = 1 }), [E] = Q("E", { all = { A } }) }, E)
    assert.same({ "blocked", "faction" }, { p.steps[1].status, p.steps[1].reason })
    assert.is_true(p.blocked)
  end)

  describe("no place to start on a chain the character cannot finish", function()
    it("a blocked step anywhere in the path drops first; the open step keeps its start status", function()
      -- E needs A (startable) and B (Alliance only): Horde cannot finish the chain
      local p = path({ [A] = Q("A"), [B] = Q("B", { faction = 1 }), [E] = Q("E", { all = { A, B } }) }, E)
      assert.same({ "start", "blocked" }, field(p, "status"))
      assert.is_true(p.blocked)
      assert.is_nil(p.first)
      assert.equals(2, p.remaining)

      -- blocked deeper in the chain: A <- B (Alliance only) <- C, and E needs A and C
      p = path({ [A] = Q("A"), [B] = Q("B", { faction = 1 }), [C] = Q("C", { all = { B } }),
        [E] = Q("E", { all = { A, C } }) }, E)
      assert.is_true(p.blocked)
      assert.is_nil(p.first)
    end)

    it("the quest itself blocked for this character blocks the path and drops first", function()
      -- E is a paladin quest (class mask 2); the player is a warrior
      local quests = { [A] = Q("A"), [E] = Q("E", { all = { A }, classMask = 2 }) }
      local p = path(quests, E)
      assert.same({ "start" }, field(p, "status"))
      assert.is_true(p.blocked)
      assert.is_nil(p.first)

      -- Alliance only, other race
      quests[E] = Q("E", { all = { A }, faction = 1 })
      assert.is_true(path(quests, E).blocked)
      assert.is_nil(path(quests, E).first)
      quests[E] = Q("E", { all = { A }, raceMask = 1 })
      assert.is_true(path(quests, E).blocked)

      -- ruled out by a quest outside its path
      quests[E] = Q("E", { all = { A }, exclusiveTo = { Z } })
      p = path(quests, E, player({ completed = { [Z] = true } }))
      assert.is_true(p.blocked)
      assert.is_nil(p.first)
    end)

    it("the quest itself locked, ignored, done or in the log does not block the path", function()
      local quests = { [A] = Q("A"), [E] = Q("E", { all = { A } }) }
      local p = path(quests, E, player({ ignored = { [E] = true } }))
      assert.is_false(p.blocked)
      assert.equals(1, p.first)

      -- another class's quest, but completed or in the log: the server let it through
      quests[E] = Q("E", { all = { A }, classMask = 2 })
      for _, st in ipairs({ player({ completed = { [E] = true } }), player({ log = { [E] = { complete = false } } }) }) do
        p = path(quests, E, st)
        assert.is_false(p.blocked)
        assert.is_nil(p.first)
      end
    end)

    it("the quest itself excluded only by a quest of its own path is a conflict, not blocked (R3)", function()
      local quests = { [A] = Q("A"), [B] = Q("B", { all = { A } }), [E] = Q("E", { all = { B }, exclusiveTo = { A } }) }
      local p = path(quests, E, player({ completed = { [A] = true } }))
      assert.is_false(p.blocked)
      assert.equals(2, p.first)
    end)
  end)

  -- Status of a DB step by the reason Eligibility rejects it, and what that does to the path.
  it("maps each Eligibility reason to a step status", function()
    local cases = {
      { "exclusive", { exclusiveTo = { Z } }, "blocked" },
      { "unavailable", { unavailableAfter = { Z } }, "blocked" },
      { "breadcrumb", { breadcrumbOf = Z }, "blocked" },
      { "max-level", { requiredMaxLevel = 15 }, "blocked" },
      { "too-high", { requiredLevel = 20, level = 25 }, "locked" },
      { "no-data", { noGiver = true }, "unknown" },
    }
    for _, c in ipairs(cases) do
      local reason, o, want = c[1], c[2], c[3]
      local quests = { [A] = Q("A"), [B] = Q("B", o), [E] = Q("E", { all = { A, B } }) }
      local p = path(quests, E, player({ completed = { [Z] = true } }))
      assert.same({ A, B }, field(p, "questID"), reason)
      assert.same({ want, reason }, { p.steps[2].status, p.steps[2].reason }, reason)
      assert.equals(want == "blocked", p.blocked, reason)
      if want == "blocked" then
        assert.is_nil(p.first, reason)
      else
        assert.equals(1, p.first, reason)
      end
    end
  end)

  it("ignores the player's ignore list: an ignored other-faction prerequisite is blocked, not start", function()
    local quests = { [A] = Q("A", { faction = 1 }), [E] = Q("E", { all = { A } }) }
    local p = path(quests, E, player({ ignored = { [A] = true } }))
    assert.same({ "blocked", "faction" }, { p.steps[1].status, p.steps[1].reason })
    assert.is_nil(p.first)
    assert.is_true(p.blocked)

    quests[A] = Q("A")
    p = path(quests, E, player({ ignored = { [A] = true } }))
    assert.equals("start", p.steps[1].status)
    assert.is_nil(p.steps[1].reason)
  end)

  describe("ancestors of a done or in-log step (R2)", function()
    -- A (Alliance only) <- B <- C <- D
    local function chain()
      return { [A] = Q("A", { faction = 1 }), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { B } }),
        [D] = Q("D", { all = { C } }) }
    end

    it("are done (implied), never start or blocked", function()
      local p = path(chain(), C, player({ completed = { [B] = true } }))
      assert.same({ "done", "done" }, field(p, "status"))
      assert.same({ "implied", "completed" }, field(p, "reason"))
      assert.is_false(p.blocked)
      assert.is_nil(p.first)
      assert.equals(2, p.done)
      assert.equals(0, p.remaining)
      assert.equals(0, p.xp)

      p = path(chain(), D, player({ completed = { [B] = true } }))
      assert.same({ "done", "done", "start" }, field(p, "status"))
      assert.equals(3, p.first)
      assert.is_false(p.blocked)
      assert.equals(1, p.remaining)
    end)

    it("an in-log step implies its ancestors too", function()
      local p = path(chain(), D, player({ log = { [B] = { complete = false } } }))
      assert.same({ "done", "progress", "locked" }, field(p, "status"))
      assert.same({ "implied", "in-log", "prereq" }, field(p, "reason"))
      assert.is_false(p.blocked)
      assert.equals(2, p.remaining)
    end)

    it("the quest itself completed or in the log makes every step done", function()
      for _, st in ipairs({ player({ completed = { [D] = true } }), player({ log = { [D] = { complete = true } } }) }) do
        local p = path(chain(), D, st)
        assert.same({ "done", "done", "done" }, field(p, "status"))
        assert.same({ "implied", "implied", "implied" }, field(p, "reason"))
        assert.equals(0, p.remaining)
        assert.is_false(p.blocked)
        assert.is_nil(p.first)
      end
    end)

    it("the any-list of a done, in-log or implied owner adds no group", function()
      local quests = { [X] = Q("X"), [Y] = Q("Y"), [A] = Q("A", { any = { X, Y } }), [B] = Q("B", { all = { A } }),
        [E] = Q("E", { all = { B } }) }
      assert.same({ A, B }, field(path(quests, E, player({ completed = { [A] = true } })), "questID"))
      assert.same({ A, B }, field(path(quests, E, player({ log = { [A] = { complete = false } } })), "questID"))
      local p = path(quests, E, player({ completed = { [B] = true } }))
      assert.same({ A, B }, field(p, "questID"))
      assert.same({ "done", "done" }, field(p, "status"))
      -- the quest's own any-list, the quest in the log
      quests[E] = Q("E", { all = { B }, any = { X, Y } })
      p = path(quests, E, player({ log = { [E] = { complete = false } } }))
      assert.same({ A, B }, field(p, "questID"))
    end)
  end)

  describe("a step excluded by another quest (R3)", function()
    it("is unknown (conflict) when the excluder is a step of the same path", function()
      local quests = { [A] = Q("A", { exclusiveTo = { B } }), [B] = Q("B", { exclusiveTo = { A } }),
        [E] = Q("E", { all = { A, B } }) }
      local p = path(quests, E, player({ completed = { [A] = true } }))
      assert.same({ A, B }, field(p, "questID"))
      assert.same({ "done", "unknown" }, field(p, "status"))
      assert.equals("conflict", p.steps[2].reason)
      assert.is_false(p.blocked)
      assert.is_nil(p.first)

      -- the excluder in the log counts too
      p = path(quests, E, player({ log = { [A] = { complete = false } } }))
      assert.same({ "unknown", "conflict" }, { p.steps[2].status, p.steps[2].reason })
    end)

    it("stays blocked when the excluder is outside the path", function()
      local quests = { [A] = Q("A"), [B] = Q("B", { exclusiveTo = { Z } }), [Z] = Q("Z"),
        [E] = Q("E", { all = { A, B } }) }
      local p = path(quests, E, player({ completed = { [Z] = true } }))
      assert.same({ "blocked", "exclusive" }, { p.steps[2].status, p.steps[2].reason })
      assert.is_true(p.blocked)

      -- excluded both from inside and from outside the path: the outside one decides
      quests[B] = Q("B", { exclusiveTo = { A, Z } })
      p = path(quests, E, player({ completed = { [A] = true, [Z] = true } }))
      assert.same({ "blocked", "exclusive" }, { p.steps[2].status, p.steps[2].reason })
      assert.is_true(p.blocked)
    end)
  end)

  it("cycle terminates", function()
    local p = path({ [A] = Q("A", { all = { B } }), [B] = Q("B", { all = { A } }) }, A)
    assert.same({ B }, field(p, "questID"))

    p = path({ [A] = Q("A", { all = { C } }), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { B } }),
      [E] = Q("E", { all = { C } }) }, E)
    local seen = {}
    for _, s in ipairs(p.steps) do
      assert.is_nil(seen[s.questID]); seen[s.questID] = true
    end
    assert.equals(3, #p.steps)
    assert.same({ A, B, C }, field(p, "questID"))
    assert.same({ 1, 2, 3 }, field(p, "number"))
    -- the edge back into the cycle (A needs C) adds no layer: A starts with D, a step outside it
    p = path({ [A] = Q("A", { all = { C } }), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { B } }),
      [D] = Q("D"), [E] = Q("E", { all = { C, D } }) }, E)
    assert.same({ A, D, B, C }, field(p, "questID"))
    assert.same({ "all", 2 }, { p.steps[1].group.kind, p.steps[1].group.size })
    assert.equals(p.steps[1].group, p.steps[2].group)
    assert.is_nil(p.steps[3].group)
  end)

  it("xp sums not-done DB steps", function()
    local quests = { [A] = Q("A", { xp = 500 }), [B] = Q("B", { all = { A }, xp = 700 }),
      [X] = Q("X", { faction = 1, xp = 900 }), [Y] = Q("Y", { xp = 300 }), [Z] = Q("Z", { xp = 100 }),
      [E] = Q("E", { all = { B, C }, any = { X, Y, Z } }) }
    local state = player({ completed = { [A] = true }, recordedXP = { [B] = { [20] = 650 } } })
    local p = path(quests, E, state, { [C] = stub("S") })
    -- A is done, B uses its recorded XP, the stub C counts nothing, the any-group counts Y only
    assert.equals(650 + 300, p.xp)
    assert.equals(ns.XP.estimate(db:quest(Y), 20, state.recordedXP), 300)
  end)

  it("quest without prerequisites returns nil", function()
    assert.is_nil(path({ [A] = Q("A") }, A))
    assert.is_nil(path({ [A] = Q("A") }, 999))
    assert.is_nil(path({ [A] = Q("A") }, B, nil, { [B] = stub("S") }))
  end)

  it("returns the path of a stub", function()
    local p = path({ [A] = Q("A") }, B, nil, { [B] = stub("S", { all = { A } }) })
    assert.same({ A }, field(p, "questID"))
  end)

  it("keeps at most 64 steps, dropping the ancestors farthest from the quest", function()
    local quests = { [1] = Q("Q1") }
    for i = 2, 100 do quests[i] = Q("Q" .. i, { all = { i - 1 } }) end
    local p = path(quests, 100)
    assert.equals(64, #p.steps)
    assert.equals(64, p.total)
    assert.equals(36, p.steps[1].questID)
    assert.equals(99, p.steps[64].questID)
  end)

  it("an any-list adds no option once 64 steps are taken, and only the options that fit", function()
    -- 64 required steps (36..99 of a 100-quest chain) and step 50 waits on X or Y as well
    local quests = { [1] = Q("Q1"), [X] = Q("X"), [Y] = Q("Y") }
    for i = 2, 100 do quests[i] = Q("Q" .. i, { all = { i - 1 } }) end
    quests[50] = Q("Q50", { all = { 49 }, any = { X, Y } })
    local p = path(quests, 100)
    assert.equals(64, #p.steps)
    for _, s in ipairs(p.steps) do assert.is_true(s.questID ~= X and s.questID ~= Y) end
    -- 63 required steps: one option still fits, the second does not
    quests = { [1] = Q("Q1"), [X] = Q("X"), [Y] = Q("Y") }
    for i = 2, 64 do quests[i] = Q("Q" .. i, { all = { i - 1 } }) end
    quests[64] = Q("Q64", { all = { 63 }, any = { X, Y } })
    p = path(quests, 64)
    assert.equals(64, #p.steps)
    local options = 0
    for _, s in ipairs(p.steps) do
      if s.questID == X or s.questID == Y then options = options + 1 end
    end
    assert.equals(1, options)
  end)

  -- "Chain n/m" (R7): n counts the quests the Unlock Path counts, m adds the longest chain of
  -- quests that need this one.
  describe("Unlock.position", function()
    local function positions(quests, ids, state, stubs)
      db = ns.DB.new({ quests = quests, questStubs = stubs })
      local out = {}
      for i, id in ipairs(ids) do
        local pos = ns.Unlock.position(db, id, state or player())
        out[i] = pos and (pos.index .. "/" .. pos.length) or "nil"
      end
      return out
    end

    it("a linear chain: each quest's place in it", function()
      local quests = { [A] = Q("A"), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { B } }) }
      assert.same({ "1/3", "2/3", "3/3" }, positions(quests, { A, B, C }))
      assert.same({ index = 2, length = 3 }, ns.Unlock.position(db, B, player()))
    end)

    it("the length follows the longest chain of followers", function()
      -- B and C both need A; D needs C: A -> C -> D
      local quests = { [A] = Q("A"), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { A } }),
        [D] = Q("D", { all = { C } }) }
      assert.same({ "1/3", "2/2", "2/3", "3/3" }, positions(quests, { A, B, C, D }))
    end)

    it("a follower through an any-list or a stub counts", function()
      local quests = { [A] = Q("A"), [E] = Q("E", { any = { A, X } }) }
      assert.same({ "1/2" }, positions(quests, { A }))
      -- A -> stub S -> E: the Unlock Path of E walks through the stub, so the length does too
      quests = { [A] = Q("A"), [E] = Q("E", { all = { C } }) }
      assert.same({ "1/3", "3/3" }, positions(quests, { A, E }, nil, { [C] = stub("S", { all = { A } }) }))
    end)

    it("a quest with no prerequisites and no followers is not a chain", function()
      assert.same({ "nil", "nil" }, positions({ [A] = Q("A"), [B] = Q("B") }, { A, B }))
      assert.same({ "nil" }, positions({ [A] = Q("A") }, { 999 }))
    end)

    it("n is the count the Unlock Path shows, an any-group once", function()
      local quests = { [X] = Q("X"), [Y] = Q("Y"), [A] = Q("A"), [B] = Q("B", { all = { A } }),
        [E] = Q("E", { all = { B }, any = { X, Y } }) }
      for _, s in ipairs({ player(), player({ completed = { [X] = true } }) }) do
        db = ns.DB.new({ quests = quests })
        local p = ns.Unlock.path(db, E, s)
        local pos = ns.Unlock.position(db, E, s)
        assert.equals(p.total + 1, pos.index)
        assert.equals(pos.index, pos.length)
      end
      -- unsatisfied: A, B and the X/Y group; satisfied: A and B
      assert.same({ "4/4" }, positions(quests, { E }))
      assert.same({ "3/3" }, positions(quests, { E }, player({ completed = { [X] = true } })))
      -- X itself: no prerequisites, E needs it
      assert.same({ "1/2" }, positions(quests, { X }))
    end)

    it("a cycle terminates", function()
      local quests = { [A] = Q("A", { all = { B } }), [B] = Q("B", { all = { A } }) }
      local got = positions(quests, { A, B })
      assert.equals(2, #got)
      quests = { [A] = Q("A", { all = { C } }), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { B } }),
        [E] = Q("E", { all = { C } }) }
      got = positions(quests, { E, A, B, C })
      assert.equals("4/4", got[1])
    end)

    it("the chain after the quest holds at most 64 steps", function()
      local quests = { [1] = Q("Q1") }
      for i = 2, 100 do quests[i] = Q("Q" .. i, { all = { i - 1 } }) end
      -- 1: 99 quests follow, 64 count; 64: 63 before, 36 after; 100: the path keeps 64
      assert.same({ "1/65", "64/100", "65/65" }, positions(quests, { 1, 64, 100 }))
    end)

    it("builds the followers once per database", function()
      local quests = { [A] = Q("A"), [B] = Q("B", { all = { A } }), [C] = Q("C", { all = { B } }) }
      db = ns.DB.new({ quests = quests })
      local calls, questIDs = 0, db.questIDs
      db.questIDs = function(self) calls = calls + 1; return questIDs(self) end
      for _, s in ipairs({ player(), player({ completed = { [A] = true } }) }) do
        for _, id in ipairs({ A, B, C }) do ns.Unlock.position(db, id, s) end
      end
      assert.equals(1, calls)
      assert.same({ index = 1, length = 3 }, ns.Unlock.position(db, A, player()))
    end)
  end)
end)
