-- Hand-written test fixture shaped like QuestieDB's trace layer (not a copy).
---@class ForeverQuestTraces
local ForeverQuestTraces = QuestieLoader:CreateModule("ForeverQuestTraces")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

function ForeverQuestTraces:Load()
    local questKeys = QuestieDB.questKeys

    return {
        [100] = {
            [questKeys.questLevel] = 11,
            [questKeys.preQuestSingle_add] = {4},
        },
        [200] = {
            [questKeys.startedBy_remove] = {{11}},
            [questKeys.finishedBy_add] = {nil,{630696}},
        },
        [301] = {
            [questKeys.startedBy_add] = {{20}},
        },
    }
end
