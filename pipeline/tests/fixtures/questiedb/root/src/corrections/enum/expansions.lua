-- Hand-written test fixture shaped like QuestieDB's src/corrections/enum/expansions.lua (subset).

local _, LibQuestieDB = ...
local constants = LibQuestieDB.Enum

constants.raceMaskById = {
  [1] = 1, -- HUMAN
  [2] = 2, -- ORC
  [3] = 4, -- DWARF
  [4] = 8, -- NIGHT_ELF
  [5] = 16, -- UNDEAD
  [6] = 32, -- TAUREN
  [7] = 64, -- GNOME
  [8] = 128, -- TROLL
  [9] = 256, -- GOBLIN
  [95] = 4294967296, -- SKYBORNE_ALLIANCE
  [96] = 8589934592, -- SKYBORNE_HORDE
}
local raceMaskById = constants.raceMaskById
local classicAlliance = raceMaskById[1] + raceMaskById[3] + raceMaskById[4] + raceMaskById[7]
local classicHorde = raceMaskById[2] + raceMaskById[5] + raceMaskById[6] + raceMaskById[8]

constants.byExpansion = {
  Classic = {
    classKeys = {
      NONE = 0,
      WARRIOR = 1,
      MAGE = 128,
    },
    npcFlags = {
      NONE = 0,
      QUEST_GIVER = 2,
    },
    raceKeys = {
      NONE = 0,
      HUMAN = raceMaskById[1],
      NIGHT_ELF = raceMaskById[4],
      ALL_ALLIANCE = classicAlliance,
      ALL_HORDE = classicHorde,
    },
  },
  Forever = {
    npcFlags = {
      NONE = 0,
      QUEST_GIVER = 2,
      VENDOR = 4,
    },
    raceKeys = {
      NONE = 0,
      HUMAN = raceMaskById[1],
      NIGHT_ELF = raceMaskById[4],
      GOBLIN = raceMaskById[9],
      SKYBORNE_ALLIANCE = raceMaskById[95],
      ALL_ALLIANCE = classicAlliance + raceMaskById[95],
      SKYBORNE_HORDE = raceMaskById[96],
      ALL_HORDE = classicHorde + raceMaskById[96],
    },
  },
}
