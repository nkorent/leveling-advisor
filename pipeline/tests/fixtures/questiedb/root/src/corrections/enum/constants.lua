-- Hand-written test fixture shaped like QuestieDB's src/corrections/enum/constants.lua (not a copy).

local _, LibQuestieDB = ...

local constants = {}

if LibQuestieDB then
  LibQuestieDB.Enum = constants
else
  local namespace = { Enum = constants }
  local files = dofile("src/config.lua").enumFiles
  for index = 2, #files do
    assert(loadfile(files[index]))("QuestieDB", namespace)
  end
end

return constants
