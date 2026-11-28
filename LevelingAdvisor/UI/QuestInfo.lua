local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.QuestInfo = ns.UI.QuestInfo or {}
local QuestInfo = ns.UI.QuestInfo
local Style = ns.UI.Style
local call, method = ns.Util.call, ns.Util.method

-- Pure helpers shared by the book's quest rows, detail page and search.

-- Same files as the map pins use when an atlas is missing.
QuestInfo.MARKER_FILES = {
  QuestNormal = "Interface\\GossipFrame\\AvailableQuestIcon",
  QuestTurnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}

-- state: "available" | "complete" | "progress" | "done" | "unavailable".
-- Returns { atlas, desaturated } or { file } (the done check): shared tables, read-only
-- (every list row asks for one on each render).
local MARKERS = {
  complete = { atlas = "QuestTurnin", desaturated = false },
  progress = { atlas = "QuestTurnin", desaturated = true },
  done = { file = "Interface\\Buttons\\UI-CheckBox-Check" },
  unavailable = { atlas = "QuestNormal", desaturated = true },
  available = { atlas = "QuestNormal", desaturated = false },
}
function QuestInfo.marker(state)
  return MARKERS[state] or MARKERS.available
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
  if row.later and row.goodAt then
    if row.state == "progress" then return "In your log — better at level " .. row.goodAt end
    return "Good at level " .. row.goodAt
  end
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

-- "Chain 15/21": a chain position (QuestInfo.chainPosition).
function QuestInfo.chainText(pos)
  return "Chain " .. pos.index .. "/" .. pos.length
end

-- Tag chips for a row: { { text, color } } in display order. `q` is the DB quest. With `db`
-- and `state`, the first chip is the quest's "Chain n/m" (QuestInfo.chainPosition, the count
-- the Unlock Path uses); without them, or for a quest on no chain, there is no chain chip.
function QuestInfo.tags(row, q, db, state)
  local out, t = {}, row.tags or {}
  local soft = Style.INK_SOFT
  local pos = db and state and row.questID and QuestInfo.chainPosition(db, row.questID, state)
  if pos then out[#out + 1] = { text = QuestInfo.chainText(pos), color = soft } end
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
-- Availability, rows, chains, "Why Now" and the detail model.
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

-- ns.Unlock[name](db, questID, state), or nil. Fail-soft: a file added in an update is not
-- loaded until the client restarts (/reload is not enough), so Engine/Unlock.lua may be
-- missing. An error inside it is reported, never raised, so the page or row still renders.
local function fromUnlock(name, db, questID, state)
  local Unlock = ns.Unlock
  local f = type(Unlock) == "table" and Unlock[name]
  if type(f) ~= "function" then return nil end
  local ok, result = pcall(f, db, questID, state)
  if ok then return result end
  local handler = ns.Util.call(geterrorhandler)
  if handler then pcall(handler, result) end
  return nil
end

-- A quest's unlock path (Unlock.path), or nil.
function QuestInfo.unlockPath(db, questID, state)
  return fromUnlock("path", db, questID, state)
end

-- A quest's chain position { index, length } (Unlock.position), or nil: every "Chain n/m" and
-- "step n of m" text comes from here, so it counts the quests the Unlock Path counts.
function QuestInfo.chainPosition(db, questID, state)
  return fromUnlock("position", db, questID, state)
end

-- A quest's unlock path (Engine/Unlock.lua) with more than one quest left and a step to
-- start: "Needs 4 earlier quests first. Start with The Stagnant Oasis." and
-- "Needs 4 earlier quests"; a blocked path says so; nil otherwise.
local function pathTexts(path)
  if type(path) ~= "table" then return nil end
  if path.blocked then
    return "Needs earlier quests that are not available to your character.", "Needs unavailable quests"
  end
  if (path.remaining or 0) <= 1 or not path.first then return nil end
  local step = path.steps[path.first]
  local n = Style.number(path.remaining)
  return "Needs " .. n .. " earlier quests first. Start with " .. tostring(step.name or "Unknown quest") .. ".",
    "Needs " .. n .. " earlier quests"
end

-- One entry per Eligibility reason code: function(db, q, state, path) -> text, short.
-- `path` is the quest's unlock path when the caller has it.
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
  prereq = function(db, q, state, path)
    local text, short = pathTexts(path)
    if text then return text, short end
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
-- long text, short text, and for "unavailable" the Eligibility reason. `path` (optional,
-- Unlock.path of q) words a quest locked behind earlier quests.
function QuestInfo.availability(db, q, state, path)
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
  local text, short = f(db, q, state, path)
  return "unavailable", text, short, reason
end

-- Yards from the player to a place (nil without the player's position); the
-- giver box uses it.
local function dist(db, state, point)
  if not (state.mapID and state.x and state.y and point) then return nil end
  return (ns.Geo.distance(db, { state.mapID, state.x, state.y }, point))
end

-- Class files by class ID; a class mask bit is 2^(classID - 1).
local CLASS_FILES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
  "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }

local function hasBit(mask, bit)
  return math.floor(mask / bit) % 2 == 1
end

-- The class a class quest is for. The player's own class when the quest
-- allows it (or names no class); otherwise the quest's one class; nil when it
-- allows several other classes (the "Other class" status says enough).
local function classTag(q, state)
  if not q.classQuest then return nil end
  local mask, mine = q.classMask, state.classMask
  if type(mask) ~= "number" or (type(mine) == "number" and mine > 0 and hasBit(mask, mine)) then
    return state.classFile
  end
  local found
  for i, file in ipairs(CLASS_FILES) do
    if hasBit(mask, 2 ^ (i - 1)) then
      if found then return nil end
      found = file
    end
  end
  return found
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
    yards = ns.Sections.yards(db, state, q, status),
    short = short,
    -- no chain numbers: QuestInfo.tags shows the chain position when it renders the row
    tags = {
      class = classTag(q, state),
      elite = q.elite and true or false,
      group = (q.groupSize and q.groupSize >= 2) and q.groupSize or nil,
      unverified = q.unverified and true or false,
    },
  }
end

-- List order of a row's status: what can be acted on now, then soon, done,
-- then quests the player cannot take.
local STATUS_GROUP = { available = 0, progress = 0, complete = 0, soon = 1, done = 2, unavailable = 3 }
QuestInfo.STATUS_GROUP = STATUS_GROUP -- Search orders its matches by it

function QuestInfo.statusGroup(row)
  if type(row) ~= "table" then return 3 end
  if row.soon then return STATUS_GROUP.soon end
  return STATUS_GROUP[row.state] or 3
end

-- The row's status text ("Horde only", "Completed", "Unlocks at 22", ...) when
-- it cannot be acted on now; nil for available, in-progress and complete rows.
function QuestInfo.statusText(row)
  if QuestInfo.statusGroup(row) == 0 then return nil end
  return row.short
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
  if section == "later" then
    local good = source.goodAt or ns.Difficulty.goodAt(q)
    return "Too high for now — good at level " .. good .. "."
  end
  if section == "here" then
    if source.yards then
      return "Its quest giver is " .. math.floor(source.yards + 0.5) .. " yd from you."
    end
    return "Its quest giver is close to you."
  elseif section == "class" then
    return "A " .. (QuestInfo.className(state.classFile) or "class") .. " class quest."
  elseif section == "chains" then
    local pos = QuestInfo.chainPosition(db, q.id, state)
    if not pos then return "The next step of a chain you have started." end
    return "The next step of a chain you have started (step " .. pos.index .. " of " .. pos.length .. ")."
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

-- `startText`: the whole status of a quest locked behind its unlock path (pathTexts).
local function giverBox(db, q, state, status, short, startText)
  local place = QuestInfo.place(db, q, state)
  if type(place) ~= "table" then return nil end
  local status_text = startText
  if not status_text then
    local word = STATE_WORDS[status]
    if status == "soon" then word = "Unlocks at level " .. tostring(q.requiredLevel) end
    status_text = word or short
    local d = dist(db, state, place)
    if d then status_text = status_text .. " · " .. math.floor(d + 0.5) .. " yd" end
    if status ~= "complete" and status ~= "done" then
      status_text = status_text .. (turnInPart(db, q) or "")
    end
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
  local unlock = QuestInfo.unlockPath(db, questID, state)
  local status, _, short, reason = QuestInfo.availability(db, q, state, unlock)
  local startText = reason == "prereq" and (pathTexts(unlock)) or nil
  local d = {
    questID = q.id, title = q.name, level = q.level, color = row.color, state = status,
    requiredText = q.requiredLevel and ("Requires level " .. q.requiredLevel) or nil,
    giver = giverBox(db, q, state, status, short, startText),
    why = QuestInfo.why(db, q, state, source),
    objective = q.objectiveText,
    unlock = unlock,
  }
  -- the chain position counts the quests the Unlock Path counts, with or without a path
  local pos = QuestInfo.chainPosition(db, questID, state)
  if pos then
    d.chainText = QuestInfo.chainText(pos) .. (pos.index == pos.length and " · last step" or "")
  end
  -- the chain has its own text; the chips (no db and state: no chain chip) are the other tags
  d.tags = QuestInfo.tags(row, q)
  if row.xp > 0 then d.xpText = "~" .. Style.number(row.xp) .. " XP" end
  local chainXP = QuestInfo.chainXP(db, q, state)
  if chainXP and chainXP > row.xp then
    d.chainXpText = "~" .. Style.number(chainXP) .. " XP for the rest of the chain"
  end
  return d
end

---------------------------------------------------------------------------
-- Mini map model (spec 5.6): the quest's giver, turn-in and objectives on the
-- map that holds most of them.
---------------------------------------------------------------------------
local MERGE_DISTANCE = 0.5 -- map units (0-100)

local function hasXY(p)
  return type(p) == "table" and p.mapID ~= nil and type(p.x) == "number" and type(p.y) == "number"
end

local function labelFor(db, prefix, place)
  local who = QuestInfo.npcName(db, place)
  return who and (prefix .. ": " .. who) or prefix
end

-- Pure. Returns { mapID, mapName, points, others, complete, questID, objectiveText }
-- or nil when no point of the quest has coordinates. An objective point carries its
-- objective (Contract A field 26, DB-decoded) and is labelled with its name. No
-- player position (no player dot).
function QuestInfo.miniMap(db, q, state)
  if type(q) ~= "table" then return nil end
  local cand = {}
  if hasXY(q.giver) then cand[#cand + 1] = { kind = "giver", place = q.giver } end
  if hasXY(q.turnIn) then cand[#cand + 1] = { kind = "turnin", place = q.turnIn } end
  for _, p in ipairs(q.points or {}) do
    if hasXY(p) then cand[#cand + 1] = { kind = "objective", place = p } end
  end
  if #cand == 0 then return nil end

  local counts, order = {}, {}
  for _, c in ipairs(cand) do
    local id = c.place.mapID
    if not counts[id] then counts[id] = 0; order[#order + 1] = id end
    counts[id] = counts[id] + 1
  end
  -- most candidates wins; a tie goes to the giver's map, then the turn-in's
  -- (the candidates are in that order)
  local mapID, best = nil, 0
  for _, id in ipairs(order) do
    if counts[id] > best then mapID, best = id, counts[id] end
  end

  local giver, turnin
  local points = {}
  for _, c in ipairs(cand) do
    if c.place.mapID == mapID then
      if c.kind == "giver" then giver = c.place
      elseif c.kind == "turnin" then turnin = c.place end
    end
  end
  if giver and turnin and math.abs(giver.x - turnin.x) <= MERGE_DISTANCE
    and math.abs(giver.y - turnin.y) <= MERGE_DISTANCE then
    points[#points + 1] = { kind = "giver", x = giver.x, y = giver.y,
      label = labelFor(db, "Quest giver and turn-in", turnin) }
  else
    if giver then points[#points + 1] = { kind = "giver", x = giver.x, y = giver.y,
      label = labelFor(db, "Quest giver", giver) } end
    if turnin then points[#points + 1] = { kind = "turnin", x = turnin.x, y = turnin.y,
      label = labelFor(db, "Turn in", turnin) } end
  end
  local others, otherIdx = {}, {}
  local objectivePoints = {}
  for _, c in ipairs(cand) do
    local p = c.place
    if p.mapID == mapID then
      if c.kind == "objective" then
        local o = type(p.objective) == "table" and p.objective or nil
        objectivePoints[#objectivePoints + 1] = { kind = "objective", x = p.x, y = p.y,
          label = o and o.name or "Objective", objective = o, order = #objectivePoints + 1 }
      end
    else
      local o = otherIdx[p.mapID]
      if not o then
        o = { mapID = p.mapID, name = QuestInfo.zoneName(db, p.mapID) or ("map " .. tostring(p.mapID)), count = 0 }
        otherIdx[p.mapID] = o
        others[#others + 1] = o
      end
      o.count = o.count + 1
    end
  end

  -- the dots of one objective together, in objective order (unknown ones last); stable
  table.sort(objectivePoints, function(a, b)
    local ia = a.objective and a.objective.index or math.huge
    local ib = b.objective and b.objective.index or math.huge
    if ia ~= ib then return ia < ib end
    return a.order < b.order
  end)
  for _, p in ipairs(objectivePoints) do
    p.order = nil
    points[#points + 1] = p
  end

  local mm = { mapID = mapID, mapName = QuestInfo.zoneName(db, mapID) or "Map", points = points, others = others,
    questID = q.id, objectiveText = q.objectiveText }
  local _, complete = QuestInfo.place(db, q, state)
  mm.complete = complete and true or false
  return mm
end

---------------------------------------------------------------------------
-- Objectives (Contract A field 26): live progress and the mini map tooltip.
---------------------------------------------------------------------------
local LIGHT = { 0.8, 0.8, 0.8 }
local GREY = { 0.62, 0.62, 0.62 }
local DONE = { 0.1, 1, 0.1 }
local KIND_WORDS = { [1] = "Kill", [2] = "Object · use or collect", [3] = "Item", [4] = "Objective" }

-- C_QuestLog.GetQuestObjectives(questID) for a quest in the player's log, else nil.
-- Fail-soft: a missing or failing API reads as no live data.
function QuestInfo.liveObjectives(questID)
  local log = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not (log and questID) or not call(log.GetLogIndexForQuestID, questID) then return nil end
  local list = call(log.GetQuestObjectives, questID)
  return type(list) == "table" and list or nil
end

-- A live objective's text is "Name: 3/8" or, count first, "3/8 Name" (kills: "... slain").
local SUFFIX, PREFIX = ":?%s*(%d+)%s*/%s*(%d+)%s*$", "^%s*(%d+)%s*/%s*(%d+)%s*"

local function counts(entry)
  local have, need = tonumber(entry.numFulfilled), tonumber(entry.numRequired)
  if not (have and need) and type(entry.text) == "string" then
    local h, n = entry.text:match(SUFFIX)
    if not h then h, n = entry.text:match(PREFIX) end
    have, need = have or tonumber(h), need or tonumber(n)
  end
  return have, need
end

local function liveLabel(text)
  return (text:gsub(SUFFIX, ""):gsub(PREFIX, ""):lower())
end

-- The live entry of the objective called `name` (its text holds the name; "Name: 3/8",
-- "3/8 Name", "Name slain: 3/8"), with type `wantType` when given. An exact label wins;
-- several partial matches are ambiguous (nil). Returns { have, need, done } or nil.
function QuestInfo.liveProgress(list, name, wantType)
  if type(list) ~= "table" or type(name) ~= "string" or name == "" then return nil end
  local key = name:lower()
  local exact, partial = nil, {}
  for _, e in ipairs(list) do
    if type(e) == "table" and type(e.text) == "string" and (not wantType or e.type == wantType) then
      local label = liveLabel(e.text)
      if label == key or label == key .. " slain" then
        exact = exact or e
      elseif label:find(key, 1, true) then
        partial[#partial + 1] = e
      end
    end
  end
  local e = exact or (#partial == 1 and partial[1]) or nil
  if not e then return nil end
  local have, need = counts(e)
  if not need then return nil end
  have = have or 0
  return { have = have, need = need, done = e.finished == true or have >= need }
end

local function says(text, ...)
  if type(text) ~= "string" then return false end
  local low = text:lower()
  for _, word in ipairs({ ... }) do
    if low:find("%f[%a]" .. word .. "%f[%A]") then return true end
  end
  return false
end

-- "Item · 8 needed", "Kill · 10 needed", "Talk to", "Object · use or collect", "Objective".
function QuestInfo.objectiveKind(o, need, objectiveText)
  if o.kind == 1 and o.count == nil and says(objectiveText, "speak", "talk") then return "Talk to" end
  local text = KIND_WORDS[o.kind] or "Objective"
  if need then text = text .. " · " .. need .. " needed" end
  return text
end

-- "Drops from: Young Wolf, Timber Wolf, …" / "Found in: Old Crate", or nil.
function QuestInfo.objectiveSources(o)
  if type(o.from) ~= "table" or #o.from == 0 then return nil end
  local names = {}
  for i = 1, math.min(#o.from, 3) do names[i] = tostring(o.from[i]) end
  if o.fromMore or #o.from > 3 then names[#names + 1] = "…" end
  return (o.fromKind == 2 and "Found in: " or "Drops from: ") .. table.concat(names, ", ")
end

-- Tooltip lines { {text, r, g, b}, ... } of an objective dot. `point` is a mini map
-- model point, `model` the mini map model (its objectiveText), `live` the quest's
-- live objectives (QuestInfo.liveObjectives) or nil. Live counts win over the data.
function QuestInfo.objectiveTooltip(point, model, live)
  local o = type(point.objective) == "table" and point.objective or nil
  local lines = { { (o and o.name) or "Objective", 1, 1, 1 } }
  if o then
    local progress = QuestInfo.liveProgress(live, o.name)
    lines[#lines + 1] = { QuestInfo.objectiveKind(o, (progress and progress.need) or o.count,
      model and model.objectiveText), LIGHT[1], LIGHT[2], LIGHT[3] }
    local sources = QuestInfo.objectiveSources(o)
    if sources then lines[#lines + 1] = { sources, LIGHT[1], LIGHT[2], LIGHT[3] } end
    if progress then
      local c = progress.done and DONE or { 1, 1, 1 }
      lines[#lines + 1] = { "Progress: " .. progress.have .. "/" .. progress.need, c[1], c[2], c[3] }
    end
  end
  lines[#lines + 1] = { string.format("%.1f, %.1f", tonumber(point.x) or 0, tonumber(point.y) or 0)
    .. " · Click: set waypoint", GREY[1], GREY[2], GREY[3] }
  return lines
end
