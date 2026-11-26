local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.QuestInfo = ns.UI.QuestInfo or {}
local QuestInfo = ns.UI.QuestInfo
local Style = ns.UI.Style
local method = ns.Util.method

-- Pure helpers shared by the book's quest rows, detail page and search.

-- Same files as the map pins use when an atlas is missing.
QuestInfo.MARKER_FILES = {
  QuestNormal = "Interface\\GossipFrame\\AvailableQuestIcon",
  QuestTurnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}

-- state: "available" | "complete" | "progress" | "done" | "unavailable".
-- Returns { atlas, desaturated } or { file } (the done check).
function QuestInfo.marker(state)
  if state == "complete" then return { atlas = "QuestTurnin", desaturated = false } end
  if state == "progress" then return { atlas = "QuestTurnin", desaturated = true } end
  if state == "done" then return { file = "Interface\\Buttons\\UI-CheckBox-Check" } end
  if state == "unavailable" then return { atlas = "QuestNormal", desaturated = true } end
  return { atlas = "QuestNormal", desaturated = false }
end

-- An NPC place's name, or nil (kind 1 with a record in the data).
function QuestInfo.npcName(db, place)
  if type(place) ~= "table" or place.kind ~= 1 then return nil end
  local npc = method(db, "npc", place.id)
  return type(npc) == "table" and npc[1] or nil
end

function QuestInfo.zoneName(db, mapID)
  local z = mapID and method(db, "zone", mapID)
  return type(z) == "table" and z.name or nil
end

-- Localized class name for a class file ("DRUID"), else Title-case.
function QuestInfo.className(file)
  if type(file) ~= "string" then return nil end
  local names = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE
  return (names and names[file]) or (file:sub(1, 1):upper() .. file:sub(2):lower())
end

-- The place a quest row is about: the turn-in when complete, else the giver.
-- `state` is the row state ("complete") or the player state (its log).
function QuestInfo.place(db, q, state)
  if type(q) ~= "table" then return nil end
  local complete = state == "complete"
  if type(state) == "table" and type(state.log) == "table" then
    complete = state.log[q.id] ~= nil and state.log[q.id].complete and true or false
  end
  if complete and q.turnIn then return q.turnIn, true end
  return q.giver, false
end

-- "Turn in: Marine Tidehunter · 134 yd · ~880 XP"
function QuestInfo.subLine(db, row, state)
  local place, isTurnIn
  if row.state == "complete" then
    place, isTurnIn = QuestInfo.place(db, method(db, "quest", row.questID), "complete")
  end
  if not place then place, isTurnIn = row.giver, false end
  local parts = {}
  local known = type(place) == "table"
  local here = known and type(state) == "table" and place.mapID == state.mapID
  local who = known and QuestInfo.npcName(db, place) or nil
  if who and isTurnIn then who = "Turn in: " .. who end
  if known and place.mapID and not here then
    local zone = QuestInfo.zoneName(db, place.mapID)
    if zone then who = who and (who .. ", " .. zone) or zone end
  end
  if who then parts[#parts + 1] = who end
  if here and row.yards then parts[#parts + 1] = math.floor(row.yards + 0.5) .. " yd" end
  if (row.xp or 0) > 0 then parts[#parts + 1] = "~" .. Style.number(row.xp) .. " XP" end
  return table.concat(parts, " · ")
end

-- Tag chips for a row: { { text, color } } in display order. `q` is the DB quest.
function QuestInfo.tags(row, q)
  local out, t = {}, row.tags or {}
  local soft = Style.INK_SOFT
  if t.chain then
    out[#out + 1] = { text = "Chain " .. t.chain.index .. "/" .. t.chain.length, color = soft }
  end
  if t.class then
    local c = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[t.class]
    out[#out + 1] = { text = QuestInfo.className(t.class),
      color = c and { c.r, c.g, c.b } or soft }
  end
  if t.group then out[#out + 1] = { text = t.group .. " players", color = soft } end
  if t.elite then out[#out + 1] = { text = "Elite", color = soft } end
  if row.soon and q and q.requiredLevel then
    out[#out + 1] = { text = "Unlocks at " .. q.requiredLevel, color = soft }
  end
  if t.unverified then out[#out + 1] = { text = "unverified", color = soft } end
  return out
end

---------------------------------------------------------------------------
-- Availability, rows, chains, "Why Now" and the detail model (Task 6).
---------------------------------------------------------------------------
local FACTION_NAMES = { [1] = "Alliance", [2] = "Horde" }

local function firstMissingPrereq(q, state)
  local completed = state.completed or {}
  local prereq = q.prereq or {}
  for _, p in ipairs(prereq.all or {}) do
    if not completed[p] then return p end
  end
  return (prereq.any or {})[1]
end

-- One entry per Eligibility reason code: function(db, q, state) -> text, short.
local REASONS = {
  completed = function() return "You have completed this quest.", "Completed" end,
  ignored = function() return "You are ignoring this quest.", "Ignored" end,
  ["no-data"] = function() return "Not enough data to recommend this quest.", "No data" end,
  faction = function(_, q)
    local f = FACTION_NAMES[q.faction] or "Other faction"
    return f .. " only.", f .. " only"
  end,
  race = function() return "Not available to your race.", "Other race" end,
  class = function() return "Not available to your class.", "Other class" end,
  exclusive = function() return "You did a quest that rules this one out.", "Ruled out" end,
  unavailable = function() return "You did a quest that rules this one out.", "Ruled out" end,
  breadcrumb = function() return "You already have the quest it leads to.", "Not needed" end,
  prereq = function(db, q, state)
    local p = firstMissingPrereq(q, state)
    local pq = p and method(db, "quest", p)
    local name = type(pq) == "table" and pq.name or "an earlier quest"
    return "Needs " .. name .. " first.", "Needs an earlier quest"
  end,
  level = function(_, q)
    return "Requires level " .. q.requiredLevel .. ".", "Requires level " .. q.requiredLevel
  end,
  ["max-level"] = function(_, q)
    return "Only up to level " .. q.requiredMaxLevel .. ".", "Too late"
  end,
  ["too-high"] = function(_, q)
    return "Quest level " .. q.level .. " is too high for you yet.", "Too high"
  end,
  grey = function() return "Too low for your level (grey).", "Grey" end,
}

-- -> status ("available" | "soon" | "progress" | "complete" | "done" | "unavailable"),
-- long text, short text.
function QuestInfo.availability(db, q, state)
  local E = ns.Eligibility
  local ok, result, reason = pcall(E.check, db, q, state)
  if not ok then return "unavailable", "Not enough data to recommend this quest.", "No data" end
  if result == "eligible" then return "available", "You can pick it up now.", "Available" end
  if result == "soon" then
    return "soon", "Unlocks at level " .. q.requiredLevel .. ".", "Unlocks at " .. q.requiredLevel
  end
  if reason == "in-log" then
    if E.logState(state, q.id) == "complete" then
      return "complete", "Ready to turn in.", "Ready to turn in"
    end
    return "progress", "In your quest log.", "In your log"
  end
  if reason == "completed" then return "done", REASONS.completed() end
  local f = REASONS[reason] or REASONS["no-data"]
  return "unavailable", f(db, q, state)
end

-- Mirrors Engine/Sections.lua rowYards (Engine is off limits, so the copy is forced).
local function dist(db, state, point)
  if not (state.mapID and state.x and state.y and point) then return nil end
  return (ns.Geo.distance(db, { state.mapID, state.x, state.y }, point))
end

local function rowYards(db, state, q, status)
  if status == "complete" then return dist(db, state, q.turnIn) end
  if status == "progress" then
    local best
    for _, p in ipairs(q.points or {}) do
      local d = dist(db, state, p)
      if d and (not best or d < best) then best = d end
    end
    if q.points and #q.points > 0 then return best end
    return dist(db, state, q.turnIn)
  end
  return dist(db, state, q.giver)
end

-- A Contract C row for any quest in the DB (nil otherwise).
function QuestInfo.row(db, questID, state)
  local q = method(db, "quest", questID)
  if type(q) ~= "table" or type(state) ~= "table" then return nil end
  local status, _, short = QuestInfo.availability(db, q, state)
  local g = q.giver or {}
  return {
    questID = q.id,
    name = q.name,
    level = q.level,
    color = ns.Difficulty.color(q.level, state.level, state.greyAtOrBelow),
    state = status == "soon" and "available" or status,
    soon = status == "soon",
    xp = ns.XP.estimate(q, state.level, state.recordedXP),
    giver = { mapID = g.mapID, x = g.x, y = g.y, kind = g.kind, id = g.id },
    yards = rowYards(db, state, q, status),
    short = short,
    tags = {
      chain = q.chain and { index = q.chain.index, length = q.chain.length } or nil,
      class = q.classQuest and state.classFile or nil,
      elite = q.elite and true or false,
      group = (q.groupSize and q.groupSize >= 2) and q.groupSize or nil,
      unverified = q.unverified and true or false,
    },
  }
end

-- chainID -> { [index] = questID }, built once per db.
local chainIndexes = setmetatable({}, { __mode = "k" })

local function chainIndex(db)
  local idx = chainIndexes[db]
  if idx then return idx end
  idx = {}
  for _, id in ipairs(method(db, "questIDs") or {}) do
    local q = method(db, "quest", id)
    if type(q) == "table" and q.chain and q.chain.id and q.chain.index then
      local c = idx[q.chain.id]
      if not c then c = {}; idx[q.chain.id] = c end
      c[q.chain.index] = id
    end
  end
  chainIndexes[db] = idx
  return idx
end

-- XP of this chain step and every later step not completed; nil without a
-- chain of 2+ steps or when fewer than 2 steps count.
function QuestInfo.chainXP(db, q, state)
  local chain = type(q) == "table" and q.chain
  if not (chain and chain.id and chain.index and (chain.length or 0) >= 2) then return nil end
  local steps = chainIndex(db)[chain.id]
  if not steps then return nil end
  local total, count = 0, 0
  for index, id in pairs(steps) do
    if index >= chain.index and not (state.completed and state.completed[id]) then
      local sq = id == q.id and q or method(db, "quest", id)
      if type(sq) == "table" then
        total = total + ns.XP.estimate(sq, state.level, state.recordedXP)
        count = count + 1
      end
    end
  end
  if count < 2 then return nil end
  return total
end

local function dungeonName(db, key)
  local d = key and method(db, "dungeon", key)
  return type(d) == "table" and d.name or tostring(key)
end

-- The reason this quest is shown; the first rule that applies wins.
function QuestInfo.why(db, q, state, source)
  source = type(source) == "table" and source or {}
  if ns.Eligibility.logState(state, q.id) == "complete" then
    local who = QuestInfo.npcName(db, q.turnIn)
    return "It is complete: turn it in to " .. (who or "the quest giver") .. "."
  end
  -- the source only explains quests that can still be picked up or are underway
  local status, text = QuestInfo.availability(db, q, state)
  if status ~= "available" and status ~= "soon" and status ~= "progress" then return text end
  local section = source.section
  if section == "here" then
    if source.yards then
      return "Its quest giver is " .. math.floor(source.yards + 0.5) .. " yd from you."
    end
    return "Its quest giver is close to you."
  elseif section == "class" then
    return "A " .. (QuestInfo.className(state.classFile) or "class") .. " class quest."
  elseif section == "chains" then
    local c = q.chain or {}
    return "The next step of a chain you have started (step " .. tostring(c.index) .. " of "
      .. tostring(c.length) .. ")."
  elseif section == "next" then
    return "One of the first quests in " .. (QuestInfo.zoneName(db, q.zone) or "that zone")
      .. ", your next recommended zone."
  end
  if source.stepIndex then
    local text = "Step " .. source.stepIndex .. " of your " .. tostring(source.zoneName or "zone") .. " route."
    if (source.others or 0) > 0 then
      text = text .. " Done together with " .. source.others .. " other "
        .. (source.others == 1 and "quest" or "quests") .. " there."
    end
    return text
  end
  if source.dungeon then
    return "A quest for " .. dungeonName(db, source.dungeon) .. ": pick it up before you go."
  end
  return text
end

local STATE_WORDS = { available = "Not picked up yet", progress = "In your quest log",
  complete = "Ready to turn in", done = "Completed" }

local function placeTitle(db, place)
  local zone = QuestInfo.zoneName(db, place.mapID)
  if place.kind == 2 then return "An object" .. (zone and (", " .. zone) or "") end
  if place.kind == 3 then return "Starts from an item" end
  local name = QuestInfo.npcName(db, place) or "Quest giver"
  return name .. (zone and (", " .. zone) or "")
end

local function turnInPart(db, q)
  local g, t = q.giver, q.turnIn
  if type(t) ~= "table" then return nil end
  if type(g) == "table" and g.kind == t.kind and g.id == t.id then return " · turn in to the same NPC" end
  local name = QuestInfo.npcName(db, t)
  return name and (" · turn in to " .. name) or nil
end

local function giverBox(db, q, state, status, short)
  local place = QuestInfo.place(db, q, state)
  if type(place) ~= "table" then return nil end
  local word = STATE_WORDS[status]
  if status == "soon" then word = "Unlocks at level " .. tostring(q.requiredLevel) end
  word = word or short
  local status_text = word
  local d = dist(db, state, place)
  if d then status_text = status_text .. " · " .. math.floor(d + 0.5) .. " yd" end
  if status ~= "complete" and status ~= "done" then
    status_text = status_text .. (turnInPart(db, q) or "")
  end
  return {
    title = placeTitle(db, place),
    coords = place.x and place.y and Style.coords(place.x, place.y) or nil,
    status = status_text,
    place = { mapID = place.mapID, x = place.x, y = place.y },
  }
end

-- The model of the quest detail page (nil when the quest is not in the DB).
function QuestInfo.detail(db, questID, state, source)
  local q = method(db, "quest", questID)
  local row = QuestInfo.row(db, questID, state)
  if type(q) ~= "table" or not row then return nil end
  local status, text, short = QuestInfo.availability(db, q, state)
  local d = {
    questID = q.id, title = q.name, level = q.level, color = row.color, state = status,
    requiredText = q.requiredLevel and ("Requires level " .. q.requiredLevel) or nil,
    giver = giverBox(db, q, state, status, short),
    why = QuestInfo.why(db, q, state, source),
    objective = q.objectiveText,
  }
  local chain = q.chain
  if chain and (chain.length or 0) >= 2 then
    d.chainText = "Chain " .. chain.index .. "/" .. chain.length
      .. (chain.index == chain.length and " · last step" or "")
  end
  -- the chain has its own text; the chips are the other tags
  local tagRow = { soon = row.soon, tags = {} }
  for k, v in pairs(row.tags) do if k ~= "chain" then tagRow.tags[k] = v end end
  d.tags = QuestInfo.tags(tagRow, q)
  if row.xp > 0 then d.xpText = "~" .. Style.number(row.xp) .. " XP" end
  local chainXP = QuestInfo.chainXP(db, q, state)
  if chainXP and chainXP > row.xp then
    d.chainXpText = "~" .. Style.number(chainXP) .. " XP for the rest of the chain"
  end
  return d
end
