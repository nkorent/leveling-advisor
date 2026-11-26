-- Hand-written test fixture (enum subset).

local _, LibQuestieDB = ...
local constants = LibQuestieDB.Enum

constants.questFlags = {
  NONE = 0,
  SHARABLE = 8,
}

constants.specialFlags = {
  NONE = 0,
  REPEATABLE = 1,
}

constants.sortKeys = {
  EPIC = -1,
}
