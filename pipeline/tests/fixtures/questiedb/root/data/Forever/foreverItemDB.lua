-- Hand-written test fixture shaped like QuestieDB's data/Forever/foreverItemDB.lua (not a copy).
-- Like the real file, its key table predates the meta's last key (teachesSpell = 16).

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

QuestieDB.itemKeys = {
    ['name'] = 1, -- string
    ['npcDrops'] = 2, -- table or nil, NPC IDs
    ['objectDrops'] = 3, -- table or nil, object IDs
    ['itemDrops'] = 4, -- table or nil, item IDs
    ['startQuest'] = 5, -- int or nil, ID of the quest started by this item
    ['questRewards'] = 6, -- table or nil, quest IDs
    ['flags'] = 7, -- int or nil
    ['foodType'] = 8, -- int or nil
    ['itemLevel'] = 9, -- int, the level of this item
    ['requiredLevel'] = 10, -- int, the level required to equip/use this item
    ['ammoType'] = 11, -- int,
    ['class'] = 12, -- int,
    ['subClass'] = 13, -- int,
    ['vendors'] = 14, -- table or nil, NPC IDs
    ['relatedQuests'] = 15, -- table or nil, IDs of quests that are related to this item
}

QuestieDB.itemData = [[return {
[2001] = {'Gnoll Paw',{99,10},nil,nil,nil,nil,nil,nil,5,0,0,12,0,nil,{200}},
[2004] = {'Faction Spice',{13},nil,nil,nil,nil,nil,nil,5,0,0,12,0},
[9000] = {'Starting Letter',nil,{5000},nil,700,nil,nil,nil,1,0,0,12,0},
}]]
