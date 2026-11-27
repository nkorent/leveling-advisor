local _, ns = ...

-- Builds the candidate quest list: every eligible or soon quest plus every
-- logged quest the DB knows. Entries: { quest, status, baseStatus, fit, xp },
-- by quest ID.
--   fit: the quest's difficulty colour for the player (Difficulty.color with
--        the player's real grey level): yellow, green, orange, red or grey.
--   status: the Eligibility status (eligible, soon) or the log state
--        (progress, complete), except that a quest too high for now is
--        "later": an eligible quest that is orange (or red), every soon quest
--        and an in-progress quest that is orange or red. A complete quest is
--        never later (it stays a turn-in at any level).
--   baseStatus: the status before the level-fit rule.
local Candidates = {}
ns.Candidates = Candidates

local FITTING = { yellow = true, green = true }

local function isGroupQuest(q)
  return q.elite or (q.groupSize or 0) >= 2
end

-- The quest's difficulty colour for the player.
function Candidates.fitOf(quest, state)
  return ns.Difficulty.color(quest.level, state.level, state.greyAtOrBelow)
end

-- Yellow and green: the colours the engine recommends.
function Candidates.fits(fit)
  return FITTING[fit] == true
end

local function isLater(status, fit)
  if status == "soon" then return true end
  if status == "eligible" or status == "progress" then return fit == "orange" or fit == "red" end
  return false
end

-- Whether the engine may recommend the candidate (sections other than Later,
-- zone scores, routes, dungeon pickups): an eligible or in-progress quest of a
-- fitting colour, or a complete quest (a turn-in, at any colour). A grey quest
-- in the log is neither recommended nor later.
function Candidates.recommendable(c)
  if c.status == "complete" then return true end
  if c.status == "eligible" or c.status == "progress" then return FITTING[c.fit] == true end
  return false
end

function Candidates.build(db, state)
  local out = {}
  local eliteOff = state.settings and state.settings.elite == false
  local ids = db:questIDs()
  table.sort(ids)
  for _, id in ipairs(ids) do
    local quest = db:quest(id)
    if quest then
      local status = ns.Eligibility.logState(state, id)
      if not status then
        status = ns.Eligibility.check(db, quest, state)
        if status and eliteOff and isGroupQuest(quest) and not quest.dungeonQuest then
          status = nil
        end
      end
      if status then
        local fit = Candidates.fitOf(quest, state)
        out[#out + 1] = {
          quest = quest, status = isLater(status, fit) and "later" or status, baseStatus = status,
          fit = fit, xp = ns.XP.estimate(quest, state.level, state.recordedXP),
        }
      end
    end
  end
  return out
end
