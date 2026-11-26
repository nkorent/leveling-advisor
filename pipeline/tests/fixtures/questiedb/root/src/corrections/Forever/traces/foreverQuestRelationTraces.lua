-- Hand-written test fixture shaped like QuestieDB's relation trace layer (not a copy).
---@class ForeverQuestRelationTraces
local ForeverQuestRelationTraces = QuestieLoader:CreateModule("ForeverQuestRelationTraces")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

function ForeverQuestRelationTraces:Load()
    local questKeys = QuestieDB.questKeys

    return {
        -- [5] = { -- an accepted relation this module does not apply
            -- already in QuestieDB; Assumption: offered right after 18 was turned in
            -- [questKeys.preQuestSingle] = {18},
        -- },
        [100] = {
            [questKeys.questLevel] = 12,
            [questKeys.preQuestSingle_add] = {5},
        },
        [200] = {
            [questKeys.exclusiveTo_add] = {301},
            [questKeys.exclusiveTo_remove] = {299},
        },
    }
end
