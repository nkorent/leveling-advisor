local _, ns = ...

-- Local quest recorder: captures real quest data while the player plays.
-- Writes only into the store it is given (ns.db.recorder); never sends anything.
local Recorder = {}
ns.Recorder = Recorder
Recorder.MAX_ACCEPTED = 500

local Rec = {}
Rec.__index = Rec

local function enabled()
  return ns.Settings.get("recorder") and true or false
end

local function validID(q)
  return type(q) == "number" and q > 0
end

local function itemID(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)"))
end

local function itemIDs(count, linkFn)
  local out = {}
  for i = 1, tonumber(count) or 0 do
    local id = itemID(linkFn(i))
    if id then out[#out + 1] = id end
  end
  return out
end

local function setXP(store, questID, level, xp)
  local byLevel = store.xp[questID]
  if not byLevel then
    byLevel = {}
    store.xp[questID] = byLevel
  end
  byLevel[level] = xp
end

function Recorder.new(store, api)
  if type(store) ~= "table" then store = {} end
  for _, k in ipairs({ "xp", "levels", "details" }) do
    if type(store[k]) ~= "table" then store[k] = {} end
  end
  if type(store.accepted) ~= "table" then store.accepted = {} end
  return setmetatable({ store = store, api = api, completeLevel = {} }, Rec)
end

function Rec:onDetail()
  if not enabled() then return end
  local api, store = self.api, self.store
  local questID = api.questID()
  if not validID(questID) then return end
  local mapID = api.mapID()
  local px, py
  if mapID then px, py = api.position(mapID) end
  local prev = store.details[questID]
  local level = api.level()
  local xp = api.rewardXP()
  store.details[questID] = {
    npcID = ns.Util.npcIDFromGUID(api.npcGUID()),
    mapID = mapID,
    x = px and ns.Util.round1(px * 100) or nil,
    y = py and ns.Util.round1(py * 100) or nil,
    xp = xp,
    level = level,
    choices = itemIDs(api.numChoices(), api.choiceLink),
    rewards = itemIDs(api.numRewards(), api.rewardLink),
    at = api.now(),
    seen = ((prev and prev.seen) or 0) + 1,
  }
  if type(xp) == "number" and xp > 0 and level then setXP(store, questID, level, xp) end
end

local function storeLevels(self, list)
  if not enabled() then return end
  for _, q in ipairs(list or {}) do
    if validID(q.questID) and type(q.questLevel) == "number" then
      self.store.levels[q.questID] = q.questLevel
    end
  end
end

function Rec:onGossip() storeLevels(self, self.api.gossipAvailable()) end
function Rec:onGreeting() storeLevels(self, self.api.greetingAvailable()) end

-- QUEST_COMPLETE fires when the reward window opens: remember the level then,
-- because a turn-in that levels the player must not be recorded at the new level.
function Rec:onComplete()
  if not enabled() then return end
  local questID = self.api.questID()
  if validID(questID) then self.completeLevel[questID] = self.api.level() end
end

function Rec:onTurnedIn(questID, xpReward)
  if not enabled() then return end
  if not validID(questID) then return end
  local level = self.completeLevel[questID]
  self.completeLevel[questID] = nil
  if type(xpReward) ~= "number" or xpReward <= 0 then return end
  level = level or self.api.level()
  if level then setXP(self.store, questID, level, xpReward) end
end

function Recorder.questIDFromAccepted(a, b)
  if type(b) == "number" then return b end
  return a
end

function Rec:onAccepted(a, b)
  if not enabled() then return end
  local questID = Recorder.questIDFromAccepted(a, b)
  if not validID(questID) then return end
  local list = self.store.accepted
  list[#list + 1] = { questID, self.api.now() }
  while #list > Recorder.MAX_ACCEPTED do table.remove(list, 1) end
end

---------------------------------------------------------------------------
-- Real WoW API (every call fail-soft).
---------------------------------------------------------------------------
local function g(name)
  return function(...)
    return ns.Util.call(_G[name], ...)
  end
end

function Recorder.realApi()
  local call = ns.Util.call
  local function gossip()
    local out = {}
    local list = type(C_GossipInfo) == "table" and call(C_GossipInfo.GetAvailableQuests) or nil
    if type(list) == "table" then
      for _, q in ipairs(list) do
        out[#out + 1] = { questID = q.questID, questLevel = q.questLevel }
      end
    end
    return out
  end
  local function greeting()
    local out = {}
    local n = tonumber(call(_G.GetNumAvailableQuests)) or 0
    for i = 1, n do
      local q = select(5, call(_G.GetAvailableQuestInfo, i))
      local lvl = call(_G.GetAvailableLevel, i)
      if q then out[#out + 1] = { questID = q, questLevel = lvl } end
    end
    return out
  end
  return {
    questID = g("GetQuestID"),
    npcGUID = function() return call(_G.UnitGUID, "npc") end,
    mapID = function()
      return type(C_Map) == "table" and call(C_Map.GetBestMapForUnit, "player") or nil
    end,
    position = function(mapID)
      if type(C_Map) ~= "table" then return nil end
      local p = call(C_Map.GetPlayerMapPosition, mapID, "player")
      if type(p) ~= "table" then return nil end
      local x, y = call(p.GetXY, p)
      return x, y
    end,
    rewardXP = g("GetRewardXP"),
    numChoices = function() return tonumber(call(_G.GetNumQuestChoices)) or 0 end,
    choiceLink = function(i) return call(_G.GetQuestItemLink, "choice", i) end,
    numRewards = function() return tonumber(call(_G.GetNumQuestRewards)) or 0 end,
    rewardLink = function(i) return call(_G.GetQuestItemLink, "reward", i) end,
    level = function() return call(_G.UnitLevel, "player") end,
    now = function() return call(_G.time) end,
    gossipAvailable = gossip,
    greetingAvailable = greeting,
  }
end
