-- Hand-written test fixture shaped like QuestieDB's trace layer (not a copy).
---@class ForeverObjectTraces
local ForeverObjectTraces = QuestieLoader:CreateModule("ForeverObjectTraces")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

function ForeverObjectTraces:Load()
    local objectKeys = QuestieDB.objectKeys

    return {
        [5000] = {
            [objectKeys.questStarts_add] = {300},
        },
    }
end
