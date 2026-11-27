-- Hand-written test fixture shaped like QuestieDB's Forever/legacy/classicItemFixes.lua (not a copy).
---@class QuestieItemFixes
local QuestieItemFixes = QuestieLoader:CreateModule("QuestieItemFixes")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

function QuestieItemFixes:Load()
    local itemKeys = QuestieDB.itemKeys
    local itemClasses = QuestieDB.itemClasses

    return {
        [2001] = { -- Gnoll Paw
            [itemKeys.npcDrops_add] = {11},
            [itemKeys.class] = itemClasses.QUEST,
        },
    }
end

-- some quest items are shared across factions but require different sources for each faction
function QuestieItemFixes:LoadFactionFixes()
    local itemKeys = QuestieDB.itemKeys

    local itemFixesHorde = {
        [2004] = { -- Faction Spice
            [itemKeys.npcDrops] = {31},
        },
    }

    local itemFixesAlliance = {
        [2004] = { -- Faction Spice
            [itemKeys.npcDrops] = {30},
        },
    }

    if UnitFactionGroup("Player") == "Horde" then
        return itemFixesHorde
    else
        return itemFixesAlliance
    end
end
