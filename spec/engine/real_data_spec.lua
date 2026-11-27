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

  it("stubs cover excluded prerequisites", function()
    local stub = db:stub(6564)
    assert.is_truthy(stub)
    assert.is_truthy(stub.name and stub.name ~= "")
    local total, missing = 0, 0
    for _, id in ipairs(db:questIDs()) do
      local q = db:quest(id)
      for _, list in ipairs({ q.prereq.all, q.prereq.any }) do
        for _, pid in ipairs(list) do
          total = total + 1
          if not db:quest(pid) and not db:stub(pid) then missing = missing + 1 end
        end
      end
    end
    print(("prerequisite ids with neither quest nor stub: %d of %d"):format(missing, total))
    assert.is_true(total > 0)
    assert.is_true(missing < total * 0.05, "unresolved prerequisites: " .. missing .. " of " .. total)
  end)

  -- Task 8: what each objective dot is, and required item counts from the objective text
  it("quest 33 (Wolves Across the Border): Tough Wolf Meat x8, its points carry that objective", function()
    local q = db:quest(33)
    assert.equals(1, #q.objectives)
    local o = q.objectives[1]
    assert.same({ 3, 750, "Tough Wolf Meat", 8 }, { o.kind, o.id, o.name, o.count })
    assert.same({ "Timber Wolf", "Young Wolf", "Ragged Timber Wolf" }, o.from)
    assert.same({ 1, true }, { o.fromKind, o.fromMore })
    assert.equals(2, #q.points)
    for _, p in ipairs(q.points) do assert.equals(o, p.objective) end
    assert.same({ { 750, 8 } }, q.items.required)
  end)

  it("quest 587 (Up to Snuff) needs 15 Snuff, quest 1275 eight brain stems", function()
    local q = db:quest(587)
    assert.same({ { 3910, 15 } }, q.items.required)
    assert.same({ 3, 3910, "Snuff", 15 }, { q.objectives[1].kind, q.objectives[1].id, q.objectives[1].name,
      q.objectives[1].count })
    assert.equals(q.objectives[1], q.points[1].objective)
    local b = db:quest(1275)
    assert.same({ "Corrupted Brain Stem", 8 }, { b.objectives[1].name, b.objectives[1].count })
    assert.same({ { 5952, 8 } }, b.items.required)
  end)

  it("objective data is consistent: indices in range, no made-up required count of 1", function()
    local quests, withObjectives, points, indexed = 0, 0, 0, 0
    for _, id in ipairs(db:questIDs()) do
      local q = db:quest(id)
      local r = ns.Data.quests[id]
      quests = quests + 1
      if #q.objectives > 0 then withObjectives = withObjectives + 1 end
      for i, p in ipairs(q.points) do
        points = points + 1
        local raw = r[13][i][4]
        if raw then
          indexed = indexed + 1
          assert.is_truthy(q.objectives[raw], "quest " .. id .. " point " .. i)
        end
      end
      for _, o in ipairs(q.objectives) do
        assert.is_truthy(o.kind >= 1 and o.kind <= 4, "quest " .. id)
        assert.is_true(o.count == nil or (o.count >= 1 and o.count % 1 == 0), "quest " .. id)
        assert.is_true(o.from == nil or (#o.from >= 1 and #o.from <= 3), "quest " .. id)
      end
    end
    print(("objectives: %d of %d quests; %d of %d points indexed"):format(withObjectives, quests, indexed, points))
    assert.is_true(withObjectives > 2000)
    assert.is_true(indexed > points * 0.95)
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

  -- Level fit (0.3.0): only yellow and green quests are recommended. The characters here have
  -- empty logs, so no row is a turn-in (a complete quest stays in Turn In at any colour).
  local RECOMMENDED = { turnin = true, here = true, class = true, chains = true, next = true }
  local FITS = { yellow = true, green = true }

  local function fitOf(s, id)
    local q = quest(id)
    return ns.Difficulty.color(q.level, s.level, s.greyAtOrBelow)
  end

  -- Counts and checks the recommended rows, the route steps and the dungeon pickups of one run.
  local function checkFit(s, rec, steps, what)
    local n = { rows = 0, actions = 0, pickups = 0, later = 0 }
    for _, sec in ipairs(rec.sections) do
      for _, row in ipairs(sec.rows) do
        local fit = fitOf(s, row.questID)
        if RECOMMENDED[sec.key] then
          n.rows = n.rows + 1
          assert.is_true(FITS[fit], what .. ": " .. sec.key .. " row " .. row.questID .. " is " .. fit)
          assert.is_nil(row.later, what .. ": " .. sec.key .. " row " .. row.questID)
        else
          assert.equals("later", sec.key, what)
          n.later = n.later + 1
          assert.is_true(row.later, what .. ": later row " .. row.questID)
          assert.is_true(row.soon or fit == "orange", what .. ": later row " .. row.questID .. " is " .. fit)
          assert.equals(math.max(quest(row.questID).level - 2, quest(row.questID).requiredLevel), row.goodAt, what)
        end
      end
    end
    for i, step in ipairs(steps) do
      for _, a in ipairs(step.actions) do
        n.actions = n.actions + 1
        local fit = fitOf(s, a[1])
        assert.is_true(FITS[fit], what .. ": route step " .. i .. " " .. a[2] .. " " .. a[1] .. " is " .. fit)
      end
    end
    for _, p in ipairs(rec.dungeon and rec.dungeon.pickups or {}) do
      n.pickups = n.pickups + 1
      local fit = fitOf(s, p.questID)
      assert.is_true(FITS[fit], what .. ": dungeon pickup " .. p.questID .. " is " .. fit)
    end
    return n
  end

  it("Booty Bay: a level-38 Horde warrior is recommended no orange, red or grey quest", function()
    local s = {
      faction = "Horde", raceMask = 2, classFile = "WARRIOR", classMask = 1,
      level = 38, mapID = 1434, x = 27, y = 77,
      completed = {}, log = {}, ignored = {}, recordedXP = {},
      settings = { elite = true, dungeons = true },
    }
    local rec = ns.Engine.compute(db, s)
    local steps = ns.Engine.route(db, s, 1434, rec)
    local n = checkFit(s, rec, steps, "Booty Bay")
    assert.is_true(n.rows > 0 and n.actions > 0, "rows " .. n.rows .. ", route actions " .. n.actions)
    -- the first step is not a level-41+ quest (the owner was sent to level-43 quests here)
    for _, a in ipairs(steps[1].actions) do
      assert.is_true(quest(a[1]).level <= 40, "first step: " .. a[1] .. " is level " .. quest(a[1]).level)
    end
    -- the orange quests of Booty Bay wait in Later (606 Scaring Shaky, level 41)
    assert.is_true(n.later > 0)
    local laterIDs = {}
    for _, sec in ipairs(rec.sections) do
      if sec.key == "later" then
        for _, row in ipairs(sec.rows) do laterIDs[row.questID] = row end
      end
    end
    assert.equals("Later — too high for now", rec.sections[#rec.sections].title)
    assert.equals(39, laterIDs[606] and laterIDs[606].goodAt)
  end)

  it("level fit on the grid: no recommended row, top-zone route step or dungeon pickup is orange, red or grey",
    function()
      local total = { rows = 0, actions = 0, pickups = 0, later = 0 }
      for _, r in ipairs(runs) do
        local top = r.rec.zones[1]
        local steps = top and ns.Engine.route(db, r.state, top.mapID, r.rec) or {}
        local n = checkFit(r.state, r.rec, steps, label(r.state))
        for k, v in pairs(n) do total[k] = total[k] + v end
        -- the steps of the player's own map too (computed in setup)
        checkFit(r.state, r.rec, r.steps, label(r.state) .. " (own map)")
      end
      print(("level fit: %d rows, %d route actions, %d dungeon pickups, %d later rows"):format(
        total.rows, total.actions, total.pickups, total.later))
      assert.is_true(total.rows > 100, "rows: " .. total.rows)
      assert.is_true(total.actions > 1000, "route actions: " .. total.actions)
      assert.is_true(total.pickups > 0, "dungeon pickups: " .. total.pickups)
      assert.is_true(total.later > 100, "later rows: " .. total.later)
    end)

  -- Unlock paths (Engine/Unlock.lua) on the shipped data.
  local function player(faction, raceMask, classFile, classMask, level, completed)
    return {
      faction = faction, raceMask = raceMask, classFile = classFile, classMask = classMask,
      level = level, mapID = 1413, x = 50, y = 50,
      completed = completed or {}, log = {}, ignored = {}, recordedXP = {},
      settings = { elite = true, dungeons = true },
    }
  end

  local function stepField(p, key)
    local out = {}
    for i, s in ipairs(p.steps) do out[i] = s[key] end
    return out
  end

  -- Each required step's position; fails on a required id listed twice. (An option may sit in
  -- two any-groups whose lists differ.)
  local function positions(p, what)
    local pos = {}
    for i, s in ipairs(p.steps) do
      if not (s.group and s.group.kind == "any") then
        assert.is_nil(pos[s.questID], what .. ": step " .. s.questID .. " listed twice")
        pos[s.questID] = i
      end
    end
    return pos
  end

  -- Every all-list prerequisite of a required step that is in the path comes before it
  -- (any-group options are exempt: their own prerequisites are not walked).
  local function assertOrdered(p, pos, what)
    for i, s in ipairs(p.steps) do
      local r = db:quest(s.questID) or db:stub(s.questID)
      if r and not (s.group and s.group.kind == "any") then
        for _, pid in ipairs(r.prereq.all) do
          if pos[pid] then
            assert.is_true(pos[pid] < i, what .. ": " .. pid .. " is not before " .. s.questID)
          end
        end
      end
    end
  end

  it("unlock path of 914 (Leaders of the Fang) for a level-17 Tauren druid", function()
    local p = ns.Unlock.path(db, 914, player("Horde", 32, "DRUID", 1024, 17, { [886] = true, [870] = true }))
    assert.same({ 886, 870, 877, 880, 1489, 1490 }, stepField(p, "questID"))
    assert.same({ "done", "done", "start", "locked", "locked", "locked" }, stepField(p, "status"))
    assert.equals(3, p.first)
    assert.equals(4, p.remaining)
  end)

  it("unlock path of 94972 (Tome of Twilight) holds every ancestor once, after its prerequisites", function()
    local p = ns.Unlock.path(db, 94972, player("Horde", 2, "WARRIOR", 1, 41))
    local want, n = {}, 0
    local function walk(id)
      local r = db:quest(id) or db:stub(id)
      for _, pid in ipairs(r and r.prereq.all or {}) do
        if not want[pid] then want[pid] = true; n = n + 1; walk(pid) end
      end
    end
    walk(94972)
    local pos = positions(p, "94972")
    for id in pairs(want) do assert.is_truthy(pos[id], "94972: ancestor " .. id .. " missing") end
    assert.equals(n, #p.steps)
    assertOrdered(p, pos, "94972")
    assert.equals(20, p.total)
  end)

  -- R7: "Chain n/m" counts the quests the Unlock Path counts ("20 quests before this one").
  it("chain positions of 94972 and 914 match their Unlock Paths", function()
    local s = player("Horde", 2, "WARRIOR", 1, 41)
    local pos = ns.Unlock.position(db, 94972, s)
    assert.equals(21, pos.index)
    assert.equals(ns.Unlock.path(db, 94972, s).total, pos.index - 1)
    assert.is_true(pos.length >= pos.index)
    pos = ns.Unlock.position(db, 914, player("Horde", 32, "DRUID", 1024, 17, { [886] = true, [870] = true }))
    assert.equals(7, pos.index)
  end)

  it("every shipped quest with an unlock path is at step path.total + 1 of its chain", function()
    local n = 0
    for _, s in ipairs({ player("Alliance", 8, "DRUID", 1024, 30), player("Horde", 16, "ROGUE", 8, 30) }) do
      for _, id in ipairs(db:questIDs()) do
        local p = ns.Unlock.path(db, id, s)
        local pos = ns.Unlock.position(db, id, s)
        local what = s.faction .. " quest " .. id
        if p then
          n = n + 1
          assert.is_truthy(pos, what)
          assert.equals(p.total + 1, pos.index, what)
        elseif pos then
          assert.equals(1, pos.index, what)
        end
        if pos then assert.is_true(pos.length >= pos.index and pos.length >= 2, what) end
      end
    end
    assert.is_true(n > 1000, "paths: " .. n)
  end)

  it("unlock path of 6565 shows the excluded quest 6564 as a named stub step", function()
    local p = ns.Unlock.path(db, 6565, player("Horde", 2, "WARRIOR", 1, 24))
    local step
    for _, s in ipairs(p.steps) do
      if s.questID == 6564 then step = s end
    end
    assert.is_truthy(step)
    assert.is_truthy(step.stub)
    assert.equals("unknown", step.status)
    assert.is_truthy(step.name and step.name ~= "")
  end)

  -- 1530 Call of Water needs all of 1528, 1529, 2985 and 2986, which exclude each other.
  it("unlock path of 1535 for a shaman past 1530: nothing behind it blocked or start (R2)", function()
    local s = player("Horde", 32, "SHAMAN", 64, 22, { [1528] = true, [1530] = true })
    assert.equals("eligible", (ns.Eligibility.check(db, quest(1535), s)))
    local p = ns.Unlock.path(db, 1535, s)
    assert.is_false(p.blocked)
    assert.is_nil(p.first)
    assert.equals(0, p.remaining)
    for _, step in ipairs(p.steps) do
      assert.equals("done", step.status, "step " .. step.questID)
    end
    local reason = {}
    for _, step in ipairs(p.steps) do reason[step.questID] = step.reason end
    assert.same({ [1528] = "completed", [1529] = "implied", [2985] = "implied", [2986] = "implied",
      [1530] = "completed" }, reason)
  end)

  it("unlock path of 1530 with one Call of Water variant done: the others conflict, not blocked (R3)", function()
    local p = ns.Unlock.path(db, 1530, player("Horde", 32, "SHAMAN", 64, 22, { [1528] = true }))
    assert.is_false(p.blocked)
    local byID = {}
    for _, step in ipairs(p.steps) do byID[step.questID] = step end
    assert.equals("done", byID[1528].status)
    for _, id in ipairs({ 1529, 2985, 2986 }) do
      assert.same({ "unknown", "conflict" }, { byID[id].status, byID[id].reason }, "step " .. id)
    end
  end)

  it("unlock paths of every shipped quest start only takeable steps, each step once and in order", function()
    local paths = 0
    for _, s in ipairs({ player("Alliance", 8, "DRUID", 1024, 30), player("Horde", 16, "ROGUE", 8, 30) }) do
      for _, id in ipairs(db:questIDs()) do
        local q = quest(id)
        if #q.prereq.all + #q.prereq.any > 0 then
          local p = ns.Unlock.path(db, id, s)
          local what = s.faction .. " quest " .. id
          if p then
            paths = paths + 1
            if p.first then assert.equals("start", p.steps[p.first].status, what) end
            for _, step in ipairs(p.steps) do
              if step.status == "start" then
                local sq = quest(step.questID)
                assert.is_truthy(sq, what .. ": start on a step outside the data")
                local got, why = ns.Eligibility.check(db, sq, s)
                assert.is_true(got == "eligible" or why == "grey" or why == "ignored",
                  what .. ": step " .. step.questID .. " is start but " .. tostring(got or why))
              end
            end
            assertOrdered(p, positions(p, what), what)
          end
        end
      end
    end
    assert.is_true(paths > 1000, "paths: " .. paths)
  end)

  it("never says where to start a chain the character cannot finish (anti-goal)", function()
    local s = player("Horde", 2 ^ 33, "WARLOCK", 256, 30)
    -- 92422 needs 356 and 99156; 99156 is not for Skyborne
    local p = ns.Unlock.path(db, 92422, s)
    assert.is_true(p.blocked)
    assert.is_nil(p.first)
    -- 3101 Consecrated Letter is a paladin quest
    p = ns.Unlock.path(db, 3101, player("Alliance", 1, "WARRIOR", 1, 10))
    assert.is_true(p.blocked)
    assert.is_nil(p.first)

    local OWN_BLOCKED = { faction = true, race = true, class = true, exclusive = true, unavailable = true,
      breadcrumb = true, ["max-level"] = true }
    local states = {}
    for _, level in ipairs({ 10, 30, 55 }) do
      states[#states + 1] = player("Alliance", 1, "WARRIOR", 1, level)
      states[#states + 1] = player("Alliance", 2 ^ 32, "HUNTER", 4, level)
      states[#states + 1] = player("Horde", 2, "WARRIOR", 1, level)
      states[#states + 1] = player("Horde", 2 ^ 33, "WARLOCK", 256, level)
    end
    local paths, blocked, bad = 0, 0, {}
    for _, st in ipairs(states) do
      for _, id in ipairs(db:questIDs()) do
        local path = ns.Unlock.path(db, id, st)
        if path then
          paths = paths + 1
          if path.blocked then blocked = blocked + 1 end
          local _, why = ns.Eligibility.check(db, quest(id), st)
          if path.first and (path.blocked or OWN_BLOCKED[why]) and #bad < 10 then
            bad[#bad + 1] = ("%s race %.0f level %d: quest %d (%s, blocked %s)"):format(st.faction, st.raceMask,
              st.level, id, tostring(why), tostring(path.blocked))
          end
        end
      end
    end
    assert.same({}, bad)
    assert.is_true(paths > 10000, "paths: " .. paths)
    assert.is_true(blocked > 1000, "blocked paths: " .. blocked)
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
