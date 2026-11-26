local _, ns = ...

local XP = {}
ns.XP = XP

-- Scale factor for quest XP by how far the quest is below the player.
local FACTOR_BY_D = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }

function XP.factor(playerLevel, questLevel)
  if playerLevel == nil or questLevel == nil then return 1.0 end
  local d = playerLevel - questLevel
  if d <= 5 then return 1.0 end
  if d >= 10 then return 0.1 end
  return FACTOR_BY_D[d]
end

-- Estimated XP for a quest at playerLevel. A recorded value wins when present.
function XP.estimate(quest, playerLevel, recordedXP)
  local recorded = recordedXP and quest.id and recordedXP[quest.id]
  if recorded and recorded[playerLevel] ~= nil then
    return recorded[playerLevel]
  end
  if quest.xp == nil or quest.level == nil then return 0 end
  local v = quest.xp * XP.factor(playerLevel, quest.level)
  return math.floor(v / 5 + 0.5) * 5
end
