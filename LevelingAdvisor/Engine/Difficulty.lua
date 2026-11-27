local _, ns = ...

local Difficulty = {}
ns.Difficulty = Difficulty

-- Fallback grey threshold when PlayerState supplies none.
function Difficulty.greyAtOrBelow(level)
  if level == nil or level <= 5 then return 0 end
  if level < 40 then
    return level - math.floor(level / 10) - 5
  end
  return level - math.floor(level / 5) - 1
end

-- Quest difficulty color relative to the player.
function Difficulty.color(questLevel, playerLevel, greyAtOrBelow)
  if questLevel == nil or playerLevel == nil then return "grey" end
  if greyAtOrBelow == nil then greyAtOrBelow = Difficulty.greyAtOrBelow(playerLevel) end
  local d = questLevel - playerLevel
  if d >= 5 then return "red" end
  if d >= 3 then return "orange" end
  if d >= -2 then return "yellow" end
  if questLevel > greyAtOrBelow then return "green" end
  return "grey"
end

-- The first player level at which a quest is good: yellow (quest level - 2),
-- and not below the level it needs to be taken.
function Difficulty.goodAt(quest)
  local level = (quest.level or 0) - 2
  if quest.requiredLevel and quest.requiredLevel > level then return quest.requiredLevel end
  return level
end
