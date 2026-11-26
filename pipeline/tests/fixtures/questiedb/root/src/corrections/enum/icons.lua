-- Hand-written test fixture (enum subset).

local _, LibQuestieDB = ...
local constants = LibQuestieDB.Enum

constants.iconTypes = {
  ICON_TYPE_SLAY = 1,
  ICON_TYPE_LOOT = 2,
  ICON_TYPE_EVENT = 3,
}
