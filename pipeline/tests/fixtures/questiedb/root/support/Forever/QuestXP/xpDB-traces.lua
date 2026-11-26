---@type QuestXP
local QuestXP = QuestieLoader:ImportModule("QuestXP")

-- Hand-written test fixture shaped like QuestieDB's xpDB-traces.lua (not a copy).
QuestXP.db[200] = {10, 520}
QuestXP.db[300] = {12, 700}
