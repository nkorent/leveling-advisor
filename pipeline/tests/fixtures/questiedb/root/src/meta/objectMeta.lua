-- Hand-written test fixture shaped like QuestieDB's src/meta/objectMeta.lua (not a copy).

local _, LibQuestieDB = ...

local meta = {
  entity = 'Object',
  metaPrefix = 'Object-',
  fieldCount = 7,

  --- fieldName -> fieldIndex. The Database Key Enum.
  keys = {
    ['name'] = 1,
    ['questStarts'] = 2,
    ['questEnds'] = 3,
    ['spawns'] = 4,
    ['zoneID'] = 5,
    ['factionID'] = 6,
    ['waypoints'] = 7,
  },

  --- fieldIndex -> storage type: number | string | table
  types = {
[1]='string', [2]='table', [3]='table', [4]='table', [5]='number', [6]='number', [7]='table'
  },

  --- fieldIndex -> structural shape, for validators. nil for scalars.
  structures = {
[2]='idarray', [3]='idarray', [4]='spawnlist', [7]='waypointlist'
  },
}

return meta
