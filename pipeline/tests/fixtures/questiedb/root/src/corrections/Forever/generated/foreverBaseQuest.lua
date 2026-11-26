-- Hand-written test fixture shaped like QuestieDB's generated delta-base (not a copy).
local ForeverBaseQuest = QuestieLoader:CreateModule("ForeverBaseQuest")
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
function ForeverBaseQuest:Load()
    local questKeys = QuestieDB.questKeys
    local raceIDs = QuestieDB.raceKeys
    local zoneIDs = ZoneDB.zoneIDs
    return {
        [100] = { -- Layered Quest : https://wowhead.com/forever/quest=100
            [questKeys.questLevel] = 10,
            [questKeys.preQuestSingle_add] = {3},
        },
        [200] = { -- Ops Quest : https://wowhead.com/forever/quest=200
            [questKeys.startedBy_add] = {nil, {424005}},
            [questKeys.requiredRaces] = raceIDs.ALL_ALLIANCE,
        },
        [800] = { -- Gated Quest : https://wowhead.com/forever/quest=800
            [questKeys.availableStartingWith] = 92514,
        },
        [300] = { -- New Forever Quest : https://wowhead.com/forever/quest=300
            [questKeys.name] = "New Forever Quest",
            [questKeys.startedBy] = {{20}},
            [questKeys.finishedBy] = {{20}},
            [questKeys.requiredLevel] = 5,
            [questKeys.questLevel] = 7,
            [questKeys.requiredRaces] = raceIDs.NIGHT_ELF + raceIDs.SKYBORNE_ALLIANCE,
            [questKeys.zoneOrSort] = zoneIDs.ELWYNN_FOREST,
        },
    }
end
