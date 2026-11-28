local _, ns = ...

-- Decides whether the player can take a quest. When data is missing or in
-- doubt, the quest is excluded.
-- Check order: completed, in-log, ignored, no-data, faction, race, class,
-- exclusive, unavailable, breadcrumb, prereq, level, max-level, too-high, grey.
local Eligibility = {}
ns.Eligibility = Eligibility

local STATE_FACTION = { Alliance = 1, Horde = 2 }
-- Contract A faction id by Contract B state.faction (shared with Unlock, Travel,
-- ZoneScore and Dungeons).
Eligibility.FACTION_ID = STATE_FACTION

-- True when a record's faction id `f` belongs to the other side: 1 or 2 and not
-- the player's. 3 (both) and nil (any) are never "other"; with an unknown player
-- faction (factionID nil) every 1 or 2 is.
function Eligibility.otherFaction(f, factionID)
  return (f == 1 or f == 2) and f ~= factionID
end

-- Plain-arithmetic bit test; stateMask is a single bit. nil mask = any.
local function maskAllows(mask, stateMask)
  if mask == nil then return true end
  if stateMask == nil or stateMask <= 0 then return false end
  return math.floor(mask / stateMask) % 2 == 1
end
Eligibility.maskAllows = maskAllows

function Eligibility.logState(state, id)
  local entry = state.log and state.log[id]
  if not entry then return nil end
  return entry.complete and "complete" or "progress"
end

local function done(state, id)
  return (state.completed and state.completed[id]) or Eligibility.logState(state, id) ~= nil
end

function Eligibility.check(db, quest, state)
  local id = quest.id
  local completed = state.completed or {}
  if completed[id] then return nil, "completed" end
  if Eligibility.logState(state, id) then return nil, "in-log" end
  if state.ignored and state.ignored[id] then return nil, "ignored" end

  if quest.faction == nil or quest.requiredLevel == nil or quest.level == nil
      or quest.giver == nil or quest.giver.mapID == nil then
    return nil, "no-data"
  end

  local f = STATE_FACTION[state.faction]
  if f == nil or (quest.faction ~= 3 and quest.faction ~= f) then return nil, "faction" end
  if not maskAllows(quest.raceMask, state.raceMask) then return nil, "race" end
  if not maskAllows(quest.classMask, state.classMask) then return nil, "class" end

  for _, other in ipairs(quest.exclusiveTo or {}) do
    if done(state, other) then return nil, "exclusive" end
  end
  -- unavailableAfter (QuestieDB availableUntilCompleted / disabledByQuest): one-way, so Route's
  -- mutual-exclusion pruning never reads it; done or in the log ends the quest
  for _, other in ipairs(quest.unavailableAfter or {}) do
    if done(state, other) then return nil, "unavailable" end
  end
  if quest.breadcrumbOf and done(state, quest.breadcrumbOf) then
    return nil, "breadcrumb"
  end

  local prereq = quest.prereq
  if prereq then
    for _, p in ipairs(prereq.all or {}) do
      if not completed[p] then return nil, "prereq" end
    end
    local any = prereq.any or {}
    if #any > 0 then
      local ok = false
      for _, p in ipairs(any) do
        if completed[p] then ok = true; break end
      end
      if not ok then return nil, "prereq" end
    end
  end

  if quest.requiredLevel > state.level + ns.Tuning.SOON_LEVELS then return nil, "level" end

  if quest.requiredMaxLevel and state.level > quest.requiredMaxLevel then
    return nil, "max-level"
  end

  -- ceiling: Classic has quests 10+ levels above their required level, and Forever's book
  -- turn-ins are r1/q45; never offer one the player is far too low for
  if quest.level > state.level + ns.Tuning.MAX_LEVELS_ABOVE then return nil, "too-high" end

  local grey = state.greyAtOrBelow or ns.Difficulty.greyAtOrBelow(state.level)
  if quest.level <= grey then return nil, "grey" end

  if quest.requiredLevel > state.level then return "soon" end
  return "eligible"
end
