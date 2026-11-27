-- Hand-written test fixture shaped like QuestieDB's src/meta/itemMeta.lua (not a copy).

local _, LibQuestieDB = ...

local meta = {
  entity = 'Item',
  metaPrefix = 'Item-',
  fieldCount = 16,

  --- fieldName -> fieldIndex. The Database Key Enum.
  keys = {
    ['name'] = 1,
    ['npcDrops'] = 2,
    ['objectDrops'] = 3,
    ['itemDrops'] = 4,
    ['startQuest'] = 5,
    ['questRewards'] = 6,
    ['flags'] = 7,
    ['foodType'] = 8,
    ['itemLevel'] = 9,
    ['requiredLevel'] = 10,
    ['ammoType'] = 11,
    ['class'] = 12,
    ['subClass'] = 13,
    ['vendors'] = 14,
    ['relatedQuests'] = 15,
    ['teachesSpell'] = 16,
  },

  --- fieldIndex -> storage type: number | string | table
  types = {
[1]='string', [2]='table', [3]='table', [4]='table', [5]='number', [6]='table', [7]='number', [8]='number', [9]='number', [10]='number', [11]='number', [12]='number', [13]='number', [14]='table', [15]='table', [16]='number'
  },

  --- fieldIndex -> structural shape, for validators. nil for scalars.
  structures = {
[2]='idarray', [3]='idarray', [4]='idarray', [6]='idarray', [14]='idarray', [15]='idarray'
  },
}

return meta
