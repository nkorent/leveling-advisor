local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.Search = ns.UI.Search or {}
local UI = ns.UI
local Search = UI.Search
local Style, List, QuestInfo, QuestRow, QuestDetail = UI.Style, UI.List, UI.QuestInfo, UI.QuestRow, UI.QuestDetail
local method = ns.Util.method

-- Quest search (spec 5.10): a box in the book's title strip; the matches fill
-- the left page, the picked quest's detail the right.
Search.LIMIT = 50
local HINT = "Type at least 2 letters."
local PROMPT = "Pick a quest to see its details."
local W = Style.CONTENT_W

-- Group order: what can be acted on now, then soon, done, unobtainable.
local GROUP = { available = 0, progress = 0, complete = 0, soon = 1, done = 2, unavailable = 3 }

-- db -> { ids = {...}, names = { lowercased name per id } }, built once per db.
local cache = setmetatable({}, { __mode = "k" })

local function index(db)
  local c = cache[db]
  if c then return c end
  c = { ids = {}, names = {} }
  for _, id in ipairs(method(db, "questIDs") or {}) do
    local q = method(db, "quest", id)
    if type(q) == "table" and type(q.name) == "string" then
      c.ids[#c.ids + 1] = id
      c.names[#c.ids] = q.name:lower()
    end
  end
  cache[db] = c
  return c
end

-- -> rows (at most `limit` QuestInfo rows), total matches, hint.
-- Status is computed for every match (the sort needs the group); rows are
-- built only for the shown ones.
function Search.find(db, query, state, limit)
  limit = limit or Search.LIMIT
  local q = tostring(query or ""):match("^%s*(.-)%s*$"):lower()
  local numeric = q:match("^%d+$") ~= nil
  if not numeric and #q < 2 then return {}, 0, HINT end
  if type(db) ~= "table" or type(state) ~= "table" then return {}, 0, nil end
  local idx = index(db)
  local exactID = numeric and tonumber(q) or nil
  local level = tonumber(state.level) or 0
  local matches = {}
  for i, name in ipairs(idx.names) do
    local id = idx.ids[i]
    local byName = string.find(name, q, 1, true)
    if byName or id == exactID then
      local quest = method(db, "quest", id)
      local status = QuestInfo.availability(db, quest, state)
      matches[#matches + 1] = {
        id = id, name = name,
        exact = id == exactID and 0 or 1,
        prefix = (byName == 1) and 0 or 1,
        group = GROUP[status] or 3,
        dist = math.abs((tonumber(quest.level) or 0) - level),
      }
    end
  end
  table.sort(matches, function(a, b)
    if a.exact ~= b.exact then return a.exact < b.exact end
    if a.prefix ~= b.prefix then return a.prefix < b.prefix end
    if a.group ~= b.group then return a.group < b.group end
    if a.dist ~= b.dist then return a.dist < b.dist end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  local rows = {}
  for i = 1, math.min(limit, #matches) do
    rows[#rows + 1] = QuestInfo.row(db, matches[i].id, state)
  end
  return rows, #matches, nil
end

function Search.summary(query, shown, total)
  if total == 0 then return 'No quests match "' .. query .. '".' end
  if total > shown then
    return "Showing " .. shown .. " of " .. total .. ' quests for "' .. query .. '"'
  end
  if total == 1 then return '1 quest for "' .. query .. '"' end
  return total .. ' quests for "' .. query .. '"'
end

---------------------------------------------------------------------------
-- The view.
---------------------------------------------------------------------------
local view = {}
local lastResults = {}

local function initRow(frame, e)
  local zone = e.zone
  QuestRow.render(frame, e.row, {
    selected = UI.current() and UI.current().questID == e.row.questID,
    sub = zone and (zone .. " · " .. (e.row.short or "")) or e.row.short,
    onClick = function(row) UI.select(row.questID) end,
  })
end

local function build(leftParent, rightParent)
  local left = CreateFrame("Frame", nil, leftParent)
  left:SetAllPoints(leftParent)
  local right = CreateFrame("Frame", nil, rightParent)
  right:SetAllPoints(rightParent)

  view.heading = Style.text(left, "QuestTitleFont", Style.INK)
  view.heading:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
  view.heading:SetText("Search")
  view.summary = Style.text(left, "QuestFont", Style.INK_SOFT)
  view.summary:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -34)
  view.summary:SetWidth(W)
  view.summary:SetWordWrap(false)

  view.list = List.new(left, initRow)
  if view.list then
    view.list.box:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -60)
    view.list.box:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -20, 0)
    view.list.bar:SetPoint("TOPLEFT", view.list.box, "TOPRIGHT", 4, 0)
    view.list.bar:SetPoint("BOTTOMLEFT", view.list.box, "BOTTOMRIGHT", 4, 0)
  end
  view.detail = QuestDetail.new(right)
  return left, right
end

local function update(v, ctx)
  local query = tostring(v.query or ""):match("^%s*(.-)%s*$")
  local rows, total, hint = Search.find(ctx.db, query, ctx.state, Search.LIMIT)
  lastResults = rows
  view.summary:SetText(hint or Search.summary(query, #rows, total))
  if view.list then
    local elements = {}
    for i, row in ipairs(rows) do
      local q = method(ctx.db, "quest", row.questID)
      elements[i] = { kind = "quest", row = row, height = QuestRow.HEIGHT,
        zone = type(q) == "table" and QuestInfo.zoneName(ctx.db, q.zone) or nil }
    end
    view.list:set(elements, "search:" .. query:lower())
  end
  if v.questID then
    view.detail:show(v.questID, v.source)
  else
    view.detail:clear(PROMPT)
  end
end

UI.registerView("search", { build = build, update = update, title = function() return "Search" end })

---------------------------------------------------------------------------
-- The box.
---------------------------------------------------------------------------
UI.onBuild(function(frame)
  local box = CreateFrame("EditBox", "LevelingAdvisorSearchBox", frame, "SearchBoxTemplate")
  box:SetSize(200, 20)
  box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -34)
  if type(box.Instructions) == "table" then box.Instructions:SetText("Search quests") end
  method(box, "SetAutoFocus", false)
  -- Hooked, not replaced: the template's own handler hides the placeholder
  -- and shows the clear button.
  local function onText(self, userInput)
    local text = self:GetText() or ""
    local inSearch = UI.current().kind == "search"
    if text == "" then
      -- also the clear (x) button, which does not report user input
      if inSearch then UI.back() end
    elseif userInput then
      UI.show({ kind = "search", query = text }, inSearch)
    end
  end
  if type(box.HookScript) == "function" then
    box:HookScript("OnTextChanged", onText)
  else
    box:SetScript("OnTextChanged", onText)
  end
  -- Build the name index before the first keystroke when possible.
  method(box, "HookScript", "OnEditFocusGained", function()
    local db = ns.Advisor and ns.Advisor.db
    if db then index(db) end
  end)
  box:SetScript("OnEnterPressed", function(self)
    local first = lastResults[1]
    if first and UI.current().kind == "search" then UI.select(first.questID) end
    self:ClearFocus()
  end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  UI.Search.box = box
  function Search.clearBox()
    if (box:GetText() or "") ~= "" then box:SetText("") end
  end
end)
