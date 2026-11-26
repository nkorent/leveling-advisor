-- Hand-written test fixture shaped like QuestieDB's data/Forever/foreverObjectDB.lua (not a copy).

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

QuestieDB.objectKeys = {
    ['name'] = 1, -- string
    ['questStarts'] = 2, -- table {questID(int),...}
    ['questEnds'] = 3, -- table {questID(int),...}
    ['spawns'] = 4, -- table {[zoneID(int)] = {coordPair(floatVector2D),...},...}
    ['zoneID'] = 5, -- guess as to where this object is most common
    ['factionID'] = 6, -- faction restriction mask
    ['waypoints'] = 7, -- waypoints for objects on ships/zeppelins/etc
}

QuestieDB.objectData = [[return {
[5000] = {"Wanted Poster",{200},nil,{[12]={{40.0,60.0}}},12},
}]]
