-- Hand-written test fixture shaped like QuestieDB's trace layer (not a copy).
---@class ForeverNpcTraces
local ForeverNpcTraces = QuestieLoader:CreateModule("ForeverNpcTraces")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

function ForeverNpcTraces:Load()
    local npcKeys = QuestieDB.npcKeys

    return {
        [10] = {
            [npcKeys.spawns_add] = {[1519] = {{52.0, 52.0}}},
            [npcKeys.questStarts_add] = {300},
        },
    }
end
