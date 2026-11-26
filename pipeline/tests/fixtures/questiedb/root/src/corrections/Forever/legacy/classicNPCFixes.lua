-- Hand-written test fixture shaped like QuestieDB's Forever/legacy/classicNPCFixes.lua (not a copy).
---@class QuestieNPCFixes
local QuestieNPCFixes = QuestieLoader:CreateModule("QuestieNPCFixes")
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
local Phasing = QuestieLoader:ImportModule("Phasing")

function QuestieNPCFixes:Load()
    local npcKeys = QuestieDB.npcKeys
    local zoneIDs = ZoneDB.zoneIDs
    local npcFlags = QuestieDB.npcFlags

    return {
        [10] = { -- Starter Ten
            [npcKeys.spawns] = {[zoneIDs.STORMWIND_CITY] = {{51.0, 51.0}}},
            [npcKeys.npcFlags] = npcFlags.QUEST_GIVER,
        },
    }
end

function QuestieNPCFixes:LoadFactionFixes()
    local npcKeys = QuestieDB.npcKeys
    local zoneIDs = ZoneDB.zoneIDs

    local npcFixesHorde = {
        [13] = {
            [npcKeys.spawns] = {[zoneIDs.ORGRIMMAR] = {{49.4, 50.0}}},
        },
    }

    local npcFixesAlliance = {
        [13] = {
            [npcKeys.spawns] = {[zoneIDs.STORMWIND_CITY] = {{39.1, 84.4}}},
        },
    }

    if UnitFactionGroup("Player") == "Horde" then
        return npcFixesHorde
    else
        return npcFixesAlliance
    end
end
