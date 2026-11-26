-- Hand-written test fixture shaped like QuestieDB's Forever/foreverNPCFixes.lua (not a copy).
---@class ForeverNpcFixes
local ForeverNpcFixes = QuestieLoader:CreateModule("ForeverNpcFixes")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

function ForeverNpcFixes:Load()
    local npcKeys = QuestieDB.npcKeys
    local zoneIDs = ZoneDB.zoneIDs

    return {
        [10] = { -- Starter Ten
            [npcKeys.spawns_remove] = {[zoneIDs.STORMWIND_CITY] = {{51.0, 51.0}}},
        },
    }
end

function ForeverNpcFixes:LoadDynamic()
    local npcKeys = QuestieDB.npcKeys

    return {
        -- [npcId] = { [npcKeys.name] = "Character-specific name" },
    }
end
