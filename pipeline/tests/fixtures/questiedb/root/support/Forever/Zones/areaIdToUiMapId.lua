-- Hand-written test fixture shaped like QuestieDB's support/Forever/Zones/areaIdToUiMapId.lua (not a copy).

local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

-- Existing Questie aliases/display policy, not inferred DBC assignments.
---@type string
ZoneDB.private.areaIdToUiMapIdOverride = [[return {
    [0] = 0, -- Existing fail-safe
    [2257] = 0, -- Deeprun Tram: retain existing display suppression
    [33] = 9999, -- override wins over the DBC row below
}]]

-- Reviewed DBC relationships.
---@type string
ZoneDB.private.areaIdToUiMapId = [[return {
    [12] = 1429, -- Elwynn Forest
    [33] = 1434, -- Stranglethorn Vale
    [1519] = 1453, -- Stormwind City
    [1637] = 1454, -- Orgrimmar
    [2257] = 1453, -- Deeprun Tram -> Stormwind City
}]]
