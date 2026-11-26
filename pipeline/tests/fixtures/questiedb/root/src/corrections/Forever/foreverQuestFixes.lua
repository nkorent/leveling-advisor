-- Hand-written test fixture shaped like QuestieDB's Forever/foreverQuestFixes.lua (not a copy).
---@class ForeverQuestFixes
local ForeverQuestFixes = QuestieLoader:CreateModule("ForeverQuestFixes")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
---@type QuestieProfessions
local QuestieProfessions = QuestieLoader:ImportModule("QuestieProfessions")

-- Static Corrections: shared by all characters and folded in during Generation.
function ForeverQuestFixes:Load()
    local questKeys = QuestieDB.questKeys
    local profKeys = QuestieProfessions.professionKeys
    local specialFlags = QuestieDB.specialFlags

    return {
        [100] = { -- Layered Quest
            [questKeys.questLevel] = 13,
            [questKeys.preQuestSingle_add] = {6},
        },
        [200] = { -- Ops Quest
            [questKeys.requiredMinRep_add] = {72, 3000},
            [questKeys.specialFlags] = specialFlags.REPEATABLE,
        },
        [201] = { -- Rejected Ops Quest
            [questKeys.preQuestGroup] = {7},
            [questKeys.preQuestGroup_add] = {8},
            [questKeys.exclusiveTo_add] = {9},
            [questKeys.exclusiveTo_remove] = {9},
            [questKeys.requiredSkill_add] = {profKeys.FIRST_AID, 75},
            [questKeys.requiredLevel] = 11,
        },
        [800] = { -- Gated Quest
            [questKeys.requiredRanks] = {{171, 225}},
            [questKeys.disabledByQuest] = 420,
        },
        [803] = { -- Forever Literal Quest: a Forever layer writing the classic Alliance races
            [questKeys.requiredRaces] = 77,
        },
    }
end

-- Dynamic Corrections: selected from character/game facts such as faction, race or class.
function ForeverQuestFixes:LoadDynamic()
    local questKeys = QuestieDB.questKeys

    local questFixesHorde = {
        [402] = {
            [questKeys.startedBy] = {{42}},
        },
        [804] = {
            [questKeys.requiredRaces] = 178,
        },
    }

    local questFixesAlliance = {
        [402] = {
            [questKeys.startedBy] = {{42}},
        },
        [804] = {
            [questKeys.requiredRaces] = 77,
        },
    }

    if UnitFactionGroup("Player") == "Horde" then
        return questFixesHorde
    else
        return questFixesAlliance
    end
end
