-- Hand-written test fixture shaped like QuestieDB's data/Forever/foreverQuestDB.lua (not a copy).

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

QuestieDB.questKeys = {
    ['name'] = 1, -- string
    ['startedBy'] = 2, -- table
        --['creatureStart'] = 1, -- table {creature(int),...}
        --['objectStart'] = 2, -- table {object(int),...}
        --['itemStart'] = 3, -- table {item(int),...}
    ['finishedBy'] = 3, -- table
        --['creatureEnd'] = 1, -- table {creature(int),...}
        --['objectEnd'] = 2, -- table {object(int),...}
    ['requiredLevel'] = 4, -- int
    ['questLevel'] = 5, -- int
    ['requiredRaces'] = 6, -- bitmask
    ['requiredClasses'] = 7, -- bitmask
    ['objectivesText'] = 8, -- table: {string,...}
    ['triggerEnd'] = 9, -- table: {text, {[zoneID] = {coordPair,...},...}}
    ['objectives'] = 10, -- table
    ['sourceItemId'] = 11, -- int
    ['preQuestGroup'] = 12, -- table: {quest(int)}
    ['preQuestSingle'] = 13, -- table: {quest(int)}
    ['childQuests'] = 14, -- table: {quest(int)}
    ['inGroupWith'] = 15, -- table: {quest(int)}
    ['exclusiveTo'] = 16, -- table: {quest(int)}
    ['zoneOrSort'] = 17, -- int
    ['requiredSkill'] = 18, -- table: {skill(int), value(int)}
    ['requiredMinRep'] = 19, -- table: {faction(int), value(int)}
    ['requiredMaxRep'] = 20, -- table: {faction(int), value(int)}
    ['requiredSourceItems'] = 21, -- table: {item(int), ...}
    ['nextQuestInChain'] = 22, -- int
    ['questFlags'] = 23, -- bitmask
    ['specialFlags'] = 24, -- bitmask: 1 = Repeatable
    ['parentQuest'] = 25, -- int
    ['reputationReward'] = 26, -- table
    ['breadcrumbForQuestId'] = 27, -- int
    ['breadcrumbs'] = 28, -- table
    ['extraObjectives'] = 29, -- table
    ['requiredSpell'] = 30, -- int
    ['requiredSpecialization'] = 31, -- int
    ['requiredMaxLevel'] = 32, -- int
    ['availableUntilCompleted'] = 33, -- int
    ['availableStartingWith'] = 34, -- int
    ['requiredRanks'] = 35, -- table
    ['disabledByQuest'] = 36, -- int
}

QuestieDB.questData = [[return {
[100] = {"Layered Quest",{{10}},{{10}},5,8,0,0,nil,nil,nil,nil,nil,{1},nil,nil,nil,12},
[200] = {"Ops Quest",{{10,11}},{{10}},10,12,77,0,nil,nil,{{{1001,"Slay"}},nil,{{2001}}},nil,nil,nil,nil,nil,{299,300},12},
[201] = {"Rejected Ops Quest",{{10}},{{10}},10,12,0,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,12,{164,50}},
[400] = {"Faction Quest",{{30}},{{30}},10,12,0,0},
[402] = {"Dynamic Override Quest",{{40}},{{40}},10,12,0,0},
[500] = {"Forever Blacklisted",{{10}},{{10}},1,2,0,0},
[501] = {"Not Forever Blacklisted",{{10}},{{10}},1,2,0,0},
[502] = {"Hide On Map",{{10}},{{10}},1,2,0,0},
[503] = {"Always Blacklisted",{{10}},{{10}},1,2,0,0},
[504] = {"Classic Only Blacklisted",{{10}},{{10}},1,2,0,0},
[505] = {"Era Blacklisted",{{10}},{{10}},1,2,0,0},
[600] = {"Unresolved Fix Quest",{{10}},{{10}},10,12,0,0,nil,nil,nil,5555},
[700] = {"Item Started",{nil,nil,{9000}},{{10}},10,12,0,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,12,nil,nil,nil,nil,nil,nil,1},
[800] = {"Gated Quest",{{10}},{{10}},10,12,0,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,12,nil,nil,nil,nil,801,nil,nil,338,nil,nil,nil,nil,nil,nil,nil,1302},
[801] = {"Spell Quest",{{10}},{{10}},10,12,0,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,12},
[802] = {"Era Alliance Quest",{{10}},{{10}},10,12,77,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,12},
[803] = {"Forever Literal Quest",{{10}},{{10}},10,12,0,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,12},
[804] = {"Faction Race Quest",{{10}},{{10}},10,12,0,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,12},
[805] = {"Unresolved Gate Quest",{{10}},{{10}},10,12,0,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,12},
}]]
