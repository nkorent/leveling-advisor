-- Hand-written test fixture shaped like QuestieDB's src/meta/npcMeta.lua (not a copy).

local _, LibQuestieDB = ...

local meta = {
  entity = 'Npc',
  metaPrefix = 'Npc-',
  fieldCount = 15,

  --- fieldName -> fieldIndex. The Database Key Enum.
  keys = {
    ['name'] = 1,
    ['minLevelHealth'] = 2,
    ['maxLevelHealth'] = 3,
    ['minLevel'] = 4,
    ['maxLevel'] = 5,
    ['rank'] = 6,
    ['spawns'] = 7,
    ['waypoints'] = 8,
    ['zoneID'] = 9,
    ['questStarts'] = 10,
    ['questEnds'] = 11,
    ['factionID'] = 12,
    ['friendlyToFaction'] = 13,
    ['subName'] = 14,
    ['npcFlags'] = 15,
  },

  --- fieldIndex -> storage type: number | string | table
  types = {
[1]='string', [2]='number', [3]='number', [4]='number', [5]='number', [6]='number', [7]='table', [8]='table', [9]='number', [10]='table', [11]='table', [12]='number', [13]='string', [14]='string', [15]='number'
  },

  --- fieldIndex -> structural shape, for validators. nil for scalars.
  structures = {
[7]='spawnlist', [8]='waypointlist', [10]='idarray', [11]='idarray'
  },
}

return meta
