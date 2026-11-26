local _, ns = ...

-- Builds the candidate quest list: every eligible or soon quest plus every
-- logged quest the DB knows. Entries: { quest, status, xp }, by quest ID.
local Candidates = {}
ns.Candidates = Candidates

local function isGroupQuest(q)
  return q.elite or (q.groupSize or 0) >= 2
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
        out[#out + 1] = {
          quest = quest, status = status,
          xp = ns.XP.estimate(quest, state.level, state.recordedXP),
        }
      end
    end
  end
  return out
end
