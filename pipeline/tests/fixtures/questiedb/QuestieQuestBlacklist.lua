-- Hand-written test fixture shaped like Questie master's QuestieQuestBlacklist.lua (not a copy).
---@class QuestieQuestBlacklist
local QuestieQuestBlacklist = QuestieLoader:CreateModule("QuestieQuestBlacklist")
---@type ContentPhases
local ContentPhases = QuestieLoader:ImportModule("ContentPhases")
---@type Expansions
local Expansions = QuestieLoader:ImportModule("Expansions")

local HIDE_ON_MAP = "HIDE_ON_MAP"

QuestieQuestBlacklist.HIDE_ON_MAP = HIDE_ON_MAP

function QuestieQuestBlacklist:Load()
    local questsToBlacklist = {
        [500] = Questie.IsForever,
        [501] = not Questie.IsForever,
        [502] = Expansions.Current >= Expansions.Cata or HIDE_ON_MAP,
        [503] = true,
        [504] = Questie.IsClassic,
        [505] = Expansions.Current == Expansions.Era or Expansions.Current >= Expansions.Wotlk,
        [99999] = true, -- not in the data
    }

    if Questie.IsSoD then
        questsToBlacklist = ContentPhases.BlacklistSoDQuestsByPhase(questsToBlacklist, ContentPhases.activePhases.SoD)
    elseif Questie.IsTBC then
        questsToBlacklist = ContentPhases.BlacklistTbcQuestsByPhase(questsToBlacklist, ContentPhases.activePhases.TBC)
    end

    return questsToBlacklist
end
