-- Hand-written test fixture shaped like QuestieDB's src/meta/questMeta.lua (not a copy).

local _, LibQuestieDB = ...

local meta = {
  entity = 'Quest',
  metaPrefix = 'Quest-',
  fieldCount = 36,

  --- fieldName -> fieldIndex. The Database Key Enum.
  keys = {
    ['name'] = 1,
    ['startedBy'] = 2,
    ['finishedBy'] = 3,
    ['requiredLevel'] = 4,
    ['questLevel'] = 5,
    ['requiredRaces'] = 6,
    ['requiredClasses'] = 7,
    ['objectivesText'] = 8,
    ['triggerEnd'] = 9,
    ['objectives'] = 10,
    ['sourceItemId'] = 11,
    ['preQuestGroup'] = 12,
    ['preQuestSingle'] = 13,
    ['childQuests'] = 14,
    ['inGroupWith'] = 15,
    ['exclusiveTo'] = 16,
    ['zoneOrSort'] = 17,
    ['requiredSkill'] = 18,
    ['requiredMinRep'] = 19,
    ['requiredMaxRep'] = 20,
    ['requiredSourceItems'] = 21,
    ['nextQuestInChain'] = 22,
    ['questFlags'] = 23,
    ['specialFlags'] = 24,
    ['parentQuest'] = 25,
    ['reputationReward'] = 26,
    ['breadcrumbForQuestId'] = 27,
    ['breadcrumbs'] = 28,
    ['extraObjectives'] = 29,
    ['requiredSpell'] = 30,
    ['requiredSpecialization'] = 31,
    ['requiredMaxLevel'] = 32,
    ['availableUntilCompleted'] = 33,
    ['availableStartingWith'] = 34,
    ['requiredRanks'] = 35,
    ['disabledByQuest'] = 36,
  },

  --- fieldIndex -> storage type: number | string | table
  types = {
[1]='string', [2]='table', [3]='table', [4]='number', [5]='number', [6]='number', [7]='number', [8]='table', [9]='table', [10]='table', [11]='number', [12]='table', [13]='table', [14]='table', [15]='table', [16]='table', [17]='number', [18]='table', [19]='table', [20]='table', [21]='table', [22]='number', [23]='number', [24]='number', [25]='number', [26]='table', [27]='number', [28]='table', [29]='table', [30]='number', [31]='number', [32]='number', [33]='number', [34]='number', [35]='table', [36]='number'
  },

  --- fieldIndex -> structural shape, for validators. nil for scalars.
  structures = {
[2]='questgivers', [3]='questgivers', [8]='stringarray', [9]='trigger', [10]='objectives', [12]='idarray', [13]='idarray', [14]='idarray', [15]='idarray', [16]='idarray', [18]='pair', [19]='pair', [20]='pair', [21]='idarray', [26]='reputationpairs', [28]='idarray', [29]='extraobjectives', [35]='pairs'
  },
}

if LibQuestieDB then
  LibQuestieDB.Meta = LibQuestieDB.Meta or {}
  LibQuestieDB.Meta['Quest'] = meta
end

return meta
