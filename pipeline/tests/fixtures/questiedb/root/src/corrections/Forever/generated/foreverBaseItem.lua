-- Hand-written test fixture shaped like QuestieDB's generated delta-base (not a copy).
local ForeverBaseItem = QuestieLoader:CreateModule("ForeverBaseItem")
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
function ForeverBaseItem:Load()
    local itemKeys = QuestieDB.itemKeys
    return {
        [2002] = { -- Forever Charm : https://wowhead.com/forever/item=2002
            [itemKeys.name] = "Forever Charm",
            [itemKeys.objectDrops] = {5000},
        },
        [2001] = { -- Gnoll Paw : https://wowhead.com/forever/item=2001
            [itemKeys.subClass] = 0,
        },
    }
end
