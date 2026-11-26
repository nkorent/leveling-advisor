-- Hand-written test fixture shaped like QuestieDB's Forever/legacy/classicQuestFixes.lua (not a copy).
---@class QuestieQuestFixes
local QuestieQuestFixes = QuestieLoader:CreateModule("QuestieQuestFixes")
-------------------------
--Import modules.
-------------------------
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
---@type QuestieCorrections
local QuestieCorrections = QuestieLoader:ImportModule("QuestieCorrections")
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

QuestieCorrections.itemObjectiveFirst[200] = true

function QuestieQuestFixes:Load()
    local questKeys = QuestieDB.questKeys
    local zoneIDs = ZoneDB.zoneIDs
    local raceIDs = QuestieDB.raceKeys
    local classIDs = QuestieDB.classKeys

    return {
        [100] = { -- Layered Quest
            [questKeys.questLevel] = 9,
            [questKeys.preQuestSingle_add] = {2},
        },
        [200] = { -- Ops Quest
            [questKeys.objectives] = {{{1001, l10n("Slay the thing"), Questie.ICON_TYPE_SLAY}}, nil, {{2001}}},
            [questKeys.zoneOrSort] = zoneIDs.ELWYNN_FOREST,
        },
        [600] = { -- Unresolved Fix Quest
            [questKeys.sourceItemId] = UNKNOWN_ITEMS.SOMETHING,
            [questKeys.requiredLevel] = 11,
        },
        [801] = { -- Spell Quest
            [questKeys.requiredSpell] = 12345,
        },
        [805] = { -- Unresolved Gate Quest: a gating field the sandbox cannot resolve
            [questKeys.availableUntilCompleted] = UNKNOWN_QUESTS.SOMETHING,
        },
    }
end

function QuestieQuestFixes:LoadFactionFixes()
    local questKeys = QuestieDB.questKeys
    local playerClass = UnitClassBase("player")

    local questFixesHorde = {
        [400] = { -- Faction Quest
            [questKeys.startedBy] = {{31}},
            [questKeys.requiredLevel] = 12,
            [questKeys.preQuestSingle] = {401},
        },
        [402] = {
            [questKeys.startedBy] = {{40}},
        },
        [403] = {
            [questKeys.nextQuestInChain] = ({
                ["MAGE"] = 1,
            })[playerClass],
        },
    }

    local questFixesAlliance = {
        [400] = { -- Faction Quest
            [questKeys.startedBy] = {{30}},
            [questKeys.requiredLevel] = 12,
        },
        [402] = {
            [questKeys.startedBy] = {{41}},
        },
    }

    if UnitFactionGroup("Player") == "Horde" then
        return questFixesHorde
    else
        return questFixesAlliance
    end
end
