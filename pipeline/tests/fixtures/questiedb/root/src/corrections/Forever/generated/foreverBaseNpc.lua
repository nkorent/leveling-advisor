-- Hand-written test fixture shaped like QuestieDB's generated delta-base (not a copy).
local ForeverBaseNpc = QuestieLoader:CreateModule("ForeverBaseNpc")
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
function ForeverBaseNpc:Load()
    local npcKeys = QuestieDB.npcKeys
    local zoneIDs = ZoneDB.zoneIDs
    return {
        [20] = { -- Forever Giver : https://wowhead.com/forever/npc=20
            [npcKeys.name] = "Forever Giver",
            [npcKeys.minLevel] = 12,
            [npcKeys.spawns] = {[12] = {{44.4, 55.5}}},
            [npcKeys.friendlyToFaction] = "A",
            [npcKeys.zoneID] = zoneIDs.ELWYNN_FOREST,
        },
        [22] = { -- Unknown Side : created without friendlyToFaction (unknown, not hostile)
            [npcKeys.name] = "Unknown Side",
            [npcKeys.minLevel] = 8,
            [npcKeys.spawns] = {[12] = {{60.0, 70.0}}},
        },
        [21] = { -- no name and not in the data: skipped
            [npcKeys.minLevel] = 5,
        },
    }
end
