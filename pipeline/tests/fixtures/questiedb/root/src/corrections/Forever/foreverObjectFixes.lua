-- Hand-written test fixture shaped like QuestieDB's Forever/foreverObjectFixes.lua (not a copy).
---@class ForeverObjectFixes
local ForeverObjectFixes = QuestieLoader:CreateModule("ForeverObjectFixes")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

function ForeverObjectFixes:Load()
    local objectKeys = QuestieDB.objectKeys
    local zoneIDs = ZoneDB.zoneIDs

    return {
        [5000] = { -- Wanted Poster
            [objectKeys.spawns_add] = {[zoneIDs.ELWYNN_FOREST] = {{40.5, 60.5}}},
        },
    }
end

function ForeverObjectFixes:LoadDynamic()
    local objectKeys = QuestieDB.objectKeys

    return {
    }
end
