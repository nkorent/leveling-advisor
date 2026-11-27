-- Hand-written test fixture shaped like QuestieDB's trace layer (not a copy).
---@class ForeverItemTraces
local ForeverItemTraces = QuestieLoader:CreateModule("ForeverItemTraces")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

function ForeverItemTraces:Load()
    local itemKeys = QuestieDB.itemKeys

    return {
        [2001] = {
            [itemKeys.npcDrops_remove] = {10},
        },
        [2002] = {
            [itemKeys.npcDrops_add] = {12},
        },
    }
end
