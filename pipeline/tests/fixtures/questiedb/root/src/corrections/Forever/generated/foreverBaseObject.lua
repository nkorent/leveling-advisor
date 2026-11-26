-- Hand-written test fixture shaped like QuestieDB's generated delta-base (not a copy).
local ForeverBaseObject = QuestieLoader:CreateModule("ForeverBaseObject")
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
function ForeverBaseObject:Load()
    local objectKeys = QuestieDB.objectKeys
    local zoneIDs = ZoneDB.zoneIDs
    return {
        [424005] = { -- Forever Crate : https://wowhead.com/forever/object=424005
            [objectKeys.name] = "Forever Crate",
            [objectKeys.questStarts] = {200},
            [objectKeys.spawns] = {[12] = {{41.0, 61.0}}},
        },
    }
end
