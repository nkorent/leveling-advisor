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
    assert.same({ "turnin", "here", "class", "next" }, keys(s))
    assert.same({ 4730 }, ids(s[1])); assert.same({ 4763, 7003 }, ids(s[2]))   -- 50.9 yd, 126 yd
    assert.same({ 5061 }, ids(s[3])); assert.same({ 1010, 1007, 1100 }, ids(s[4]))
    assert.equals("Ready to Turn In", s[1].title)
    assert.equals("complete", s[1].rows[1].state); assert.equals("yellow", s[2].rows[1].color)
    assert.near(50.9, s[2].rows[1].yards, 0.1)
    assert.is_true(s[4].rows[3].tags.unverified)
    assert.equals("DRUID", s[3].rows[1].tags.class)
  end)

  it("dungeon quests stay out of every section", function()
    -- At S20, 1275 and 1199 (BFD) and 1486 (Wailing Caverns) are eligible and their givers
    -- stand within Right Here range of the player, so only the dungeon rule keeps them out.
    local S20 = H.states.S20
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
    -- a repeated ID would sit next to its twin once sorted
    assert.same({ 1007, 1010, 1100, 4730, 4763, 5061, 7003 }, sorted)
  end)

  it("unknown position gives nil yards without error", function()
    local s = with(S18, {}); s.x, s.y = nil, nil   -- with() skips nil overrides
    local secs
    assert.has_no.errors(function() secs = build(s) end)
    local missing = {}
    for _, sec in ipairs(secs) do
      for _, r in ipairs(sec.rows) do missing[#missing + 1] = (r.yards == nil) end
    end
    -- no "Right Here" without a position; the five other rows all lack yards
    assert.same({ true, true, true, true, true }, missing)
  end)
end)
