-- Hand-written test fixture shaped like QuestieDB's Forever/foreverItemFixes.lua (not a copy).
---@class ForeverItemFixes
local ForeverItemFixes = QuestieLoader:CreateModule("ForeverItemFixes")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

function ForeverItemFixes:Load()
    local itemKeys = QuestieDB.itemKeys

    return {
        [2002] = { -- Forever Charm
            [itemKeys.name] = "Forever Charm of Testing",
        },
        [2003] = { -- a nameless row for an item that does not exist: skipped
            [itemKeys.npcDrops] = {10},
        },
        [9000] = { -- Starting Letter: shown only at its vendor
            [itemKeys.objectDrops] = {},
        },
    }
end

function ForeverItemFixes:LoadDynamic()
    local itemKeys = QuestieDB.itemKeys

    return {
    }
end
