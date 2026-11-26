--! Hand-written test fixture shaped like QuestieDB's xpDB-classic.lua (not a copy).

---@type QuestXP
local QuestXP = QuestieLoader:ImportModule("QuestXP");

QuestXP.db = {
  [100] = {8, 400}, -- Classic: 8: 400
  [200] = {10, 500}, -- Classic: 10: 500
}
