-- Hand-written test fixture shaped like QuestieDB's Forever/legacy/classicObjectFixes.lua (not a copy).
---@class QuestieObjectFixes
local QuestieObjectFixes = QuestieLoader:CreateModule("QuestieObjectFixes")
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

function QuestieObjectFixes:Load()
    local objectKeys = QuestieDB.objectKeys
    local zoneIDs = ZoneDB.zoneIDs

    return {
        [5000] = { -- Wanted Poster
            [objectKeys.zoneID] = zoneIDs.ELWYNN_FOREST,
        },
    }
end

function QuestieObjectFixes:LoadFactionFixes()
    local objectKeys = QuestieDB.objectKeys

    local objectFixesHorde = {
        [5000] = {
            [objectKeys.name] = "Wanted Poster (both factions)",
        },
    }

    local objectFixesAlliance = {
        [5000] = {
            [objectKeys.name] = "Wanted Poster (both factions)",
        },
    }

    if UnitFactionGroup("Player") == "Horde" then
        return objectFixesHorde
    else
        return objectFixesAlliance
    end
end
