local H = require("spec.helpers.engine")

describe("Sections", function()
  local ns = H.load()
  local db = ns.DB.new(H.data())
  local S18, with, ids, keys, find = H.states.S18, H.with, H.ids, H.keys, H.find
  local Candidates, ZoneScore, Sections = ns.Candidates, ns.ZoneScore, ns.Sections

  local function build(s)
    local c = Candidates.build(db, s)
    return Sections.build(db, s, c, ZoneScore.rank(db, s, c))
  end

  it("S18 sections", function()
    local c = Candidates.build(db, S18); local s = Sections.build(db, S18, c, ZoneScore.rank(db, S18, c))
    assert.same({ "turnin", "here", "class", "next", "later" }, keys(s))
    assert.same({ 991 }, ids(s[5])) -- level 21, orange at 18
    assert.same({ 4730 }, ids(s[1])); assert.same({ 4763, 7003 }, ids(s[2]))   -- 50.9 yd, 126 yd
    assert.same({ 5061 }, ids(s[3])); assert.same({ 1010, 1007, 1100 }, ids(s[4]))
    assert.equals("Ready to Turn In", s[1].title)
    assert.equals("complete", s[1].rows[1].state); assert.equals("yellow", s[2].rows[1].color)
    assert.near(50.9, s[2].rows[1].yards, 0.1)
    assert.is_true(s[4].rows[3].tags.unverified)
    assert.equals("DRUID", s[3].rows[1].tags.class)
  end)

  it("dungeon quests stay out of every section", function()
    -- At level 22, 1275 and 1199 (BFD) and 1486 (Wailing Caverns) are eligible and yellow, and
    -- their givers stand within Right Here range of the player, so only the dungeon rule keeps
    -- them out. (At 20, BFD's level-24 quests are orange: Later, which leaves dungeon quests to
    -- the dungeon card as well.)
    local S20 = H.states.S22
    local c = Candidates.build(db, S20)
    for _, id in ipairs({ 1275, 1199, 1486 }) do
      local cand = H.candidateFor(c, id)
      assert.equals("eligible", cand.status)
      local yards = ns.Geo.distance(db, { S20.mapID, S20.x, S20.y },
        { cand.quest.giver.mapID, cand.quest.giver.x, cand.quest.giver.y })
      assert.is_true(yards <= ns.Tuning.RIGHT_HERE_YD, id .. " is " .. yards .. " yd away")
    end
    local secs = Sections.build(db, S20, c, ZoneScore.rank(db, S20, c))
    for _, sec in ipairs(secs) do
      for _, row in ipairs(sec.rows) do
        assert.is_false(db:quest(row.questID).dungeonQuest, sec.key .. " lists dungeon quest " .. row.questID)
      end
    end
    assert.is_truthy(find(secs, "here"))
  end)

  it("chains section lists started chains", function()
    local s = with(S18, { completed = { [4762] = true, [965] = true, [966] = true }, log = { [4730] = { complete = true } } })
    local secs = build(s)
    local chains = find(secs, "chains"); assert.same({ 967 }, ids(chains))
    -- picked by the outof.games chain (step 3 of 6); the row's "Chain n/m" is the UI's, from
    -- Unlock.position (R7), so the row carries no chain numbers
    assert.is_nil(chains.rows[1].tags.chain)
  end)

  it("each quest appears in at most one section", function()
    local flat = H.rowIDs(build(S18))
    local sorted = {}
    for i, id in ipairs(flat) do sorted[i] = id end
    table.sort(sorted)
    -- a repeated ID would sit next to its twin once sorted (991 is the Later row)
    assert.same({ 991, 1007, 1010, 1100, 4730, 4763, 5061, 7003 }, sorted)
  end)

  it("unknown position gives nil yards without error", function()
    local s = with(S18, {}); s.x, s.y = nil, nil   -- with() skips nil overrides
    local secs
    assert.has_no.errors(function() secs = build(s) end)
    local missing = {}
    for _, sec in ipairs(secs) do
      for _, r in ipairs(sec.rows) do missing[#missing + 1] = (r.yards == nil) end
    end
    -- no "Right Here" without a position; the six other rows (Later's 991 too) all lack yards
    assert.same({ true, true, true, true, true, true }, missing)
  end)
end)

-- Level fit (0.3.0): the recommended sections hold yellow and green quests only; orange, soon
-- and logged orange/red quests go to the Later section, which comes last.
describe("Sections level fit", function()
  local ns = H.load()
  local S18, with, ids, keys, find = H.states.S18, H.with, H.ids, H.keys, H.find
  local RECOMMENDED = { "turnin", "here", "class", "chains", "next" }

  local function copyRec(r)
    local out = {}
    for k, v in pairs(r) do out[k] = v end
    return out
  end

  local function dbWith(edit)
    local data = H.data()
    edit(data.quests)
    return ns.DB.new(data)
  end

  local function build(d, s)
    local c = ns.Candidates.build(d, s)
    return ns.Sections.build(d, s, c, ns.ZoneScore.rank(d, s, c))
  end

  local function sectionOf(secs, questID)
    for _, sec in ipairs(secs) do
      for _, row in ipairs(sec.rows) do
        if row.questID == questID then return sec.key, row end
      end
    end
    return nil
  end

  it("no later quest in here, class, chains or next", function()
    -- 8501: an orange quest at the player's feet (Right Here); 5061: a soon class quest;
    -- 967: an orange chain step (Continue Your Chains); 991: an orange quest with the most XP in
    -- the next zone (For Your Next Zone)
    local d = dbWith(function(q)
      q[8501] = copyRec(q[4763]); q[8501][19] = nil; q[8501][6] = 21
      q[5061][5] = 19
      q[967][6] = 21
      q[991][17] = 9999
    end)
    local s = with(S18, { completed = { [4762] = true, [965] = true, [966] = true },
      log = { [4730] = { complete = true } } })
    local secs = build(d, s)
    for _, id in ipairs({ 8501, 5061, 967, 991 }) do
      local key = sectionOf(secs, id)
      assert.equals("later", key, "quest " .. id)
    end
    for _, key in ipairs(RECOMMENDED) do
      for _, row in ipairs(find(secs, key) and find(secs, key).rows or {}) do
        assert.is_true(row.color == "yellow" or row.color == "green" or key == "turnin",
          key .. " row " .. row.questID .. " is " .. row.color)
        assert.is_nil(row.later)
      end
    end
  end)

  it("the later section is last, with its title and goodAt", function()
    local db = ns.DB.new(H.data())
    local secs = build(db, S18)
    assert.same({ "turnin", "here", "class", "next", "later" }, keys(secs))
    local later = secs[#secs]
    assert.equals("Later — too high for now", later.title)
    assert.same({ 991 }, ids(later))
    local row = later.rows[1]
    assert.same({ true, 19, "orange", "available", false }, { row.later, row.goodAt, row.color, row.state, row.soon })
  end)

  it("a soon quest is good once the player can take it", function()
    -- 5061 is level 16 but needs level 19: good at 19, not at 14
    local d = dbWith(function(q) q[5061][5] = 19 end)
    local _, row = sectionOf(build(d, S18), 5061)
    assert.same({ true, true, 19, "available" }, { row.later, row.soon, row.goodAt, row.state })
  end)

  it("a logged orange quest is a later row in progress; a complete one stays in Turn In", function()
    local d = ns.DB.new(H.data())
    local key, row = sectionOf(build(d, with(S18, { log = { [991] = { complete = false } } })), 991)
    assert.equals("later", key)
    assert.same({ true, 19, "progress", false }, { row.later, row.goodAt, row.state, row.soon })
    key, row = sectionOf(build(d, with(S18, { log = { [991] = { complete = true } } })), 991)
    assert.equals("turnin", key)
    assert.is_nil(row.later)
  end)

  it("keeps dungeon quests not in the log out of Later, but lists a logged one", function()
    -- 1486 (Wailing Caverns) is level 21, orange at 18; 1275 (BFD) level 24, red
    local d = ns.DB.new(H.data())
    assert.equals("later", H.candidateFor(ns.Candidates.build(d, S18), 1486).status)
    local secs = build(d, with(S18, { log = { [1275] = { complete = false } } }))
    assert.is_nil(sectionOf(secs, 1486))
    assert.equals("later", (sectionOf(secs, 1275)))
  end)

  it("sorts Later by quest level, then distance, and keeps 12 rows", function()
    -- 14 copies east of the player (38, 41), each a step farther: even ones level 21, odd 22
    local d = dbWith(function(q)
      for i = 1, 14 do
        local r = copyRec(q[7001])
        r[3] = nil
        r[6] = (i % 2 == 0) and 21 or 22
        r[11] = { 1, 4000 + i, 1439, 38 + i, 41 }
        q[8600 + i] = r
      end
    end)
    local s = with(S18, { completed = { [4762] = true, [965] = true, [991] = true } })
    assert.equals(12, ns.Tuning.SECTION_LIMITS.later)
    assert.same({ 8602, 8604, 8606, 8608, 8610, 8612, 8614, 8601, 8603, 8605, 8607, 8609 },
      ids(find(build(d, s), "later")))
  end)
end)
