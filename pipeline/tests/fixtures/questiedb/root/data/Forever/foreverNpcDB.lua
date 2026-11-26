-- Hand-written test fixture shaped like QuestieDB's data/Forever/foreverNpcDB.lua (not a copy).

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

QuestieDB.npcKeys = {
    ['name'] = 1, -- string
    ['minLevelHealth'] = 2, -- int
    ['maxLevelHealth'] = 3, -- int
    ['minLevel'] = 4, -- int
    ['maxLevel'] = 5, -- int
    ['rank'] = 6, -- int
    ['spawns'] = 7, -- table {[zoneID(int)] = {coordPair(floatVector2D),...},...}
    ['waypoints'] = 8, -- table
    ['zoneID'] = 9, -- guess as to where this NPC is most common
    ['questStarts'] = 10, -- table {questID(int),...}
    ['questEnds'] = 11, -- table {questID(int),...}
    ['factionID'] = 12, -- int
    ['friendlyToFaction'] = 13, -- string, "A" and/or "H"; nil if hostile to both.
    ['subName'] = 14, -- string
    ['npcFlags'] = 15, -- int
}

QuestieDB.npcData = [[return {
[10] = {'Starter Ten',100,100,20,20,0,{[1519]={{50.0,50.0}}},nil,1519,{100,200},{100,200},12,"A",nil,2},
[11] = {'Scattered Eleven',100,100,15,15,0,{[12]={{10.0,10.0},{-1,-1},{120.0,50.0},{30.5,40.5,2}},[2257]={{50.0,50.0}},[4242]={{20.0,20.0}}},nil,12,nil,nil,35,"AH",nil,0},
[12] = {'Overridden Twelve',100,100,30,30,0,{[33]={{60.0,60.0}}},nil,33,nil,nil,35,"HA",nil,0},
[13] = {'Faction Thirteen',100,100,10,10,0,{[12]={{40.0,40.0}}},nil,12,nil,nil,35,"H",nil,0},
[30] = {'Alliance Thirty',100,100,10,10,0,{[12]={{30.0,30.0}}},nil,12,{400},{400},12,"A",nil,2},
[31] = {'Horde Thirty-One',100,100,10,10,0,{[12]={{31.0,31.0}}},nil,12,nil,nil,29,"H",nil,2},
[99] = {'Hostile Ninety-Nine',100,100,10,10,0,nil,nil,0,nil,nil,14,nil,nil,0},
}]]
