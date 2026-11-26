local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.RouteView = ns.UI.RouteView or {}
local UI = ns.UI
local RouteView = UI.RouteView
local Style, QuestDetail, Model, List, QuestInfo = UI.Style, UI.QuestDetail, UI.Model, UI.List, UI.QuestInfo
local call, method = ns.Util.call, ns.Util.method

-- The zone page: the route on the left, the quest detail on the right.
local view = {}

local function zoneName(mapID, ctx)
  local z = ctx and ctx.db and mapID and method(ctx.db, "zone", mapID)
  if type(z) == "table" and z.name then return z.name end
  local info = type(C_Map) == "table" and mapID and call(C_Map.GetMapInfo, mapID)
  if type(info) == "table" and info.name then return info.name end
  return "Zone"
end

function RouteView.title(v, ctx)
  return zoneName(v and v.mapID, ctx or UI.context())
end

local W = Style.CONTENT_W
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local RED, GREEN = { 0.62, 0.12, 0.09 }, { 0.24, 0.35, 0.12 }
local NO_PLAN = "Your route is worked out after combat."
local LINE_H, HEAD_H, SUB_H, DISC_SIZE = 18, 30, 18, 26

-- Height of a step element with n quest lines.
function RouteView.stepHeight(step)
  return HEAD_H + LINE_H * #step.quests + SUB_H
end

local function newLine(p, i, handlers)
  local line = CreateFrame("Button", nil, p.root)
  line:SetSize(W - 40 - DISC_SIZE - 8, LINE_H)
  line:SetPoint("TOPLEFT", p.root, "TOPLEFT", DISC_SIZE + 8, -(HEAD_H + (i - 1) * LINE_H))
  line.bg = line:CreateTexture(nil, "BACKGROUND")
  line.bg:SetAllPoints(line)
  line.bg:SetColorTexture(Style.GOLD[1], Style.GOLD[2], Style.GOLD[3], 0.18)
  line.marker = Style.texture(line, "ARTWORK", "QuestNormal", QuestInfo.MARKER_FILES.QuestNormal)
  line.marker:SetSize(14, 14)
  line.marker:SetPoint("LEFT", line, "LEFT", 2, 0)
  line.text = Style.text(line, "QuestFont", Style.INK)
  line.text:SetPoint("LEFT", line, "LEFT", 20, 0)
  line.text:SetWidth(W - 40 - DISC_SIZE - 8 - 24)
  line.text:SetWordWrap(false)
  line:SetHighlightTexture(WHITE, "ADD")
  local hl = ns.Util.method(line, "GetHighlightTexture")
  if type(hl) == "table" then ns.Util.method(hl, "SetVertexColor", 1, 1, 1, 0.08) end
  line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  line:SetScript("OnClick", function(self, button)
    if UI.Menu.handleClick(self, self.questID, button) then return end
    if button and button ~= "LeftButton" then return end
    if self.questID and p.handlers.onQuest then p.handlers.onQuest(self.questID) end
  end)
  return line
end

local function buildStep(frame)
  local root = CreateFrame("Frame", nil, frame)
  root:SetAllPoints(frame)
  local p = { root = root, lines = {}, handlers = {} }
  p.ring = Style.texture(root, "BACKGROUND", nil, DISC)
  p.ring:SetSize(DISC_SIZE, DISC_SIZE)
  p.ring:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -2)
  p.disc = Style.texture(root, "BORDER", nil, DISC)
  p.disc:SetSize(DISC_SIZE - 3, DISC_SIZE - 3)
  p.disc:SetPoint("CENTER", p.ring, "CENTER", 0, 0)
  p.number = Style.text(root, "GameFontNormal", Style.GOLD)
  p.number:SetPoint("CENTER", p.ring, "CENTER", 0, 0)
  p.check = Style.texture(root, "ARTWORK", nil, CHECK)
  p.check:SetSize(16, 16)
  p.check:SetPoint("CENTER", p.ring, "CENTER", 0, 0)
  p.title = Style.text(root, "QuestFont", Style.INK)
  p.title:SetPoint("TOPLEFT", root, "TOPLEFT", DISC_SIZE + 8, -7)
  p.title:SetWidth(W - DISC_SIZE - 8 - 40)
  p.title:SetWordWrap(false)
  p.sub = Style.text(root, "GameFontNormalSmall", Style.INK_SOFT)
  p.sub:SetWidth(W - DISC_SIZE - 8 - 40)
  p.sub:SetWordWrap(false)
  p.pin = Style.pinButton(root, nil)
  p.pin:SetPoint("TOPRIGHT", root, "TOPRIGHT", -4, -2)
  p.pin:SetScript("OnClick", function()
    if p.step and p.handlers.onPin then p.handlers.onPin(p.step) end
  end)
  return p
end

-- Renders one step element into a pooled row frame. handlers =
-- { onQuest = fn(questID), onPin = fn(step) }. Also used for dungeon pickups.
function RouteView.stepElement(frame, step, handlers)
  local p = List.part(frame, "step", buildStep)
  p.step, p.handlers = step, handlers or {}
  frame:SetScript("OnClick", nil)
  local ring, disc = Style.GOLD, Style.LEATHER
  if step.done then
    ring, disc = GREEN, GREEN
  elseif step.current then
    ring, disc = Style.GOLD, RED
  end
  p.ring:SetVertexColor(ring[1], ring[2], ring[3])
  p.disc:SetVertexColor(disc[1], disc[2], disc[3])
  p.check:SetShown(step.done and true or false)
  p.number:SetShown(not step.done)
  p.number:SetText(tostring(step.index or ""))
  p.title:SetText(step.title or "")
  for i, q in ipairs(step.quests) do
    local line = p.lines[i]
    if not line then
      line = newLine(p, i, p.handlers)
      p.lines[i] = line
    end
    line.questID = q.questID
    local m = QuestInfo.marker(q.state)
    Style.setTexture(line.marker, m.atlas, m.atlas and QuestInfo.MARKER_FILES[m.atlas] or m.file, m.desaturated)
    line.text:SetText(q.name .. " — " .. q.what)
    local c = q.done and Style.INK_SOFT or Style.INK
    line.text:SetTextColor(c[1], c[2], c[3])
    line.bg:SetShown(q.selected and true or false)
    line:Show()
  end
  for i = #step.quests + 1, #p.lines do p.lines[i]:Hide() end
  p.sub:ClearAllPoints()
  p.sub:SetPoint("TOPLEFT", frame, "TOPLEFT", DISC_SIZE + 8, -(HEAD_H + LINE_H * #step.quests + 2))
  p.sub:SetText(step.sub or "")
  return p
end

local function initRow(frame, e)
  if e.kind == "step" then
    RouteView.stepElement(frame, e.step, {
      onQuest = function(id) UI.select(id) end,
      onPin = function(step) UI.Nav.showPlace(step.place, step.title, "pickup") end,
    })
  end
end

local function build(leftParent, rightParent)
  local left = CreateFrame("Frame", nil, leftParent)
  left:SetAllPoints(leftParent)
  local right = CreateFrame("Frame", nil, rightParent)
  right:SetAllPoints(rightParent)

  view.back = Style.button(left, "Back", 80)
  view.back:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
  view.back:SetScript("OnClick", function() UI.back() end)
  view.heading = Style.text(left, "QuestTitleFont", Style.INK)
  view.heading:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -34)
  view.heading:SetWidth(W)
  view.heading:SetWordWrap(false)
  view.progress = Style.text(left, "QuestFont", Style.INK_SOFT)
  view.progress:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -62)
  view.noPlan = Style.text(left, "QuestFont", Style.INK_SOFT)
  view.noPlan:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -90)
  view.noPlan:SetWidth(W)
  view.noPlan:SetText(NO_PLAN)

  view.list = List.new(left, initRow)
  if view.list then
    view.list.box:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -84)
    view.list.box:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -20, 30)
    view.list.bar:SetPoint("TOPLEFT", view.list.box, "TOPRIGHT", 4, 0)
    view.list.bar:SetPoint("BOTTOMLEFT", view.list.box, "BOTTOMRIGHT", 4, 0)
  end
  view.recalc = Style.button(left, "Recalculate route", 140)
  view.recalc:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 0)
  view.recalc:SetScript("OnClick", function()
    local v = UI.current()
    if ns.Advisor and ns.Advisor.replan and v then ns.Advisor.replan(v.mapID) end
    UI.refresh()
  end)

  view.detail = QuestDetail.new(right)
  RouteView.detail = view.detail
  return left, right
end

-- The first not-done quest line of the current step.
local function defaultQuest(route)
  local step = route and route.current and route.steps[route.current]
  for _, q in ipairs(step and step.quests or {}) do
    if not q.done then return q.questID end
  end
  return nil
end

-- The step that holds questID: the detail's "Why Now" source.
local function stepSource(route, questID, zone)
  for i, step in ipairs(route and route.steps or {}) do
    for _, q in ipairs(step.quests) do
      if q.questID == questID then
        return { stepIndex = i, zoneName = zone, others = #step.quests - 1 }
      end
    end
  end
  return nil
end

local function markSelected(route, sel)
  for _, step in ipairs(route and route.steps or {}) do
    for _, q in ipairs(step.quests) do q.selected = q.questID == sel end
  end
end

local function update(v, ctx)
  local name = zoneName(v.mapID, ctx)
  local A = ns.Advisor
  local plan = A and A.plan and A.plan(v.mapID) or nil
  local route = plan and ctx.db and Model.route(plan, ctx.state, ctx.db, nil)
  local sel = v.questID
  if sel == nil then sel = defaultQuest(route) end
  markSelected(route, sel)

  view.heading:SetText(route and route.header or name)
  view.progress:SetText(route and route.progress or "")
  view.noPlan:SetShown(route == nil)
  if view.list then
    view.list.box:SetShown(route ~= nil)
    view.list.bar:SetShown(route ~= nil)
    if route then
      local elements = {}
      for i, step in ipairs(route.steps) do
        elements[i] = { kind = "step", step = step, height = RouteView.stepHeight(step) }
      end
      view.list:set(elements, "zone:" .. tostring(v.mapID))
    end
  end

  if sel then
    local source = v.source
    if source == nil then source = stepSource(route, sel, name) end
    view.detail:show(sel, source)
  else
    view.detail:clear("Pick a quest to see its details.")
  end
end

UI.registerView("zone", { build = build, update = update, title = RouteView.title })

---------------------------------------------------------------------------
-- The dungeon page: "Before You Go" route on the left, facts and quests on
-- the right.
---------------------------------------------------------------------------
local dv = {}
RouteView.dungeonParts = dv -- the dungeon page widgets (specs)
local NOT_RECOMMENDED = "This dungeon is not recommended right now."

local function currentDungeon(v, ctx)
  local d = ctx and ctx.rec and ctx.rec.dungeon
  if type(d) == "table" and d.key == v.key then return d end
  return nil
end

local function dungeonTitle(v, ctx)
  ctx = ctx or UI.context()
  local d = currentDungeon(v, ctx)
  if d then return d.name end
  local rec = ctx.db and v.key and method(ctx.db, "dungeon", v.key)
  return type(rec) == "table" and rec.name or "Dungeon"
end

local function dungeonRow(frame, e)
  if e.kind == "step" then
    RouteView.stepElement(frame, e.step, {
      onQuest = function(id) UI.select(id) end,
      onPin = function(step)
        UI.Nav.showPlace(step.place, step.title, step.entrance and "entrance" or "pickup")
      end,
    })
  elseif e.kind == "quest" then
    local cur = UI.current()
    UI.QuestRow.render(frame, e.row, {
      selected = cur and cur.questID == e.row.questID,
      -- I1: a quest this character cannot act on says why ("Horde only", ...)
      sub = QuestInfo.statusText(e.row),
      onClick = function(row) UI.select(row.questID) end,
    })
  end
end

local function listBox(list, parent, topAnchor, topOffset, bottom, right)
  if not list then return end
  list.box:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, topOffset)
  list.box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", right, bottom)
  list.bar:SetPoint("TOPLEFT", list.box, "TOPRIGHT", 4, 0)
  list.bar:SetPoint("BOTTOMLEFT", list.box, "BOTTOMRIGHT", 4, 0)
end

local function buildDungeon(leftParent, rightParent)
  local left = CreateFrame("Frame", nil, leftParent)
  left:SetAllPoints(leftParent)
  local right = CreateFrame("Frame", nil, rightParent)
  right:SetAllPoints(rightParent)

  dv.back = Style.button(left, "Back", 80)
  dv.back:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
  dv.back:SetScript("OnClick", function() UI.back() end)
  dv.notRecommended = Style.text(left, "QuestFont", Style.INK_SOFT)
  dv.notRecommended:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -40)
  dv.notRecommended:SetWidth(W)
  dv.notRecommended:SetText(NOT_RECOMMENDED)
  dv.header = Style.text(left, "QuestTitleFont", Style.INK)
  dv.header:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -34)
  dv.header:SetWidth(W)
  dv.header:SetWordWrap(false)
  dv.progress = Style.text(left, "QuestFont", Style.INK_SOFT)
  dv.progress:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -62)
  dv.list = List.new(left, dungeonRow)
  if dv.list then
    dv.list.box:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -84)
    dv.list.box:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -20, 0)
    dv.list.bar:SetPoint("TOPLEFT", dv.list.box, "TOPRIGHT", 4, 0)
    dv.list.bar:SetPoint("BOTTOMLEFT", dv.list.box, "BOTTOMRIGHT", 4, 0)
  end

  -- right page, no quest selected
  dv.info = CreateFrame("Frame", nil, right)
  dv.info:SetAllPoints(right)
  dv.name = Style.text(dv.info, "QuestTitleFont", Style.INK)
  dv.name:SetPoint("TOPLEFT", dv.info, "TOPLEFT", 0, 0)
  dv.name:SetWidth(W)
  dv.meta = Style.text(dv.info, "QuestFont", Style.INK_SOFT)
  dv.meta:SetPoint("TOPLEFT", dv.name, "BOTTOMLEFT", 0, -4)
  dv.meta:SetWidth(W)
  dv.whyHeading = Style.heading(dv.info, "Why Now")
  dv.whyHeading:SetPoint("TOPLEFT", dv.meta, "BOTTOMLEFT", 0, -12)
  dv.why = Style.text(dv.info, "QuestFont", Style.INK)
  dv.why:SetPoint("TOPLEFT", dv.whyHeading, "BOTTOMLEFT", 0, -10)
  dv.why:SetWidth(W)
  dv.entranceHeading = Style.heading(dv.info, "Entrance")
  dv.entranceHeading:SetPoint("TOPLEFT", dv.why, "BOTTOMLEFT", 0, -12)
  dv.entrance = Style.text(dv.info, "QuestFont", Style.INK)
  dv.entrance:SetPoint("TOPLEFT", dv.entranceHeading, "BOTTOMLEFT", 0, -10)
  dv.entrance:SetWidth(W - 34)
  dv.pin = Style.pinButton(dv.info, nil)
  dv.pin:SetPoint("LEFT", dv.entrance, "RIGHT", 4, 0)
  dv.questsHeading = Style.heading(dv.info, "Quests")
  dv.questsHeading:SetPoint("TOPLEFT", dv.entrance, "BOTTOMLEFT", 0, -12)
  dv.questList = List.new(dv.info, dungeonRow)
  listBox(dv.questList, dv.info, dv.questsHeading, -10, 32, -20)
  dv.mapButton = Style.button(dv.info, "Show Entrance on Map", 180)
  dv.mapButton:SetPoint("BOTTOMLEFT", dv.info, "BOTTOMLEFT", 0, 0)

  -- right page, a quest selected
  dv.detailBox = CreateFrame("Frame", nil, right)
  dv.detailBox:SetAllPoints(right)
  dv.backToDungeon = CreateFrame("Button", nil, dv.detailBox)
  dv.backToDungeon:SetSize(W, 22)
  dv.backToDungeon:SetPoint("TOPLEFT", dv.detailBox, "TOPLEFT", 0, 0)
  ns.Util.method(dv.backToDungeon, "SetNormalFontObject", "GameFontNormal")
  ns.Util.method(dv.backToDungeon, "SetHighlightFontObject", "GameFontHighlight")
  dv.backToDungeon:SetScript("OnClick", function() UI.select(nil) end)
  local holder = CreateFrame("Frame", nil, dv.detailBox)
  holder:SetPoint("TOPLEFT", dv.detailBox, "TOPLEFT", 0, -28)
  holder:SetPoint("BOTTOMRIGHT", dv.detailBox, "BOTTOMRIGHT", 0, 0)
  dv.detail = QuestDetail.new(holder)
  return left, right
end

local function updateDungeon(v, ctx)
  local d = currentDungeon(v, ctx)
  dv.notRecommended:SetShown(d == nil)
  for _, w in ipairs({ dv.header, dv.progress, dv.info, dv.detailBox }) do w:SetShown(false) end
  if dv.list then dv.list.box:SetShown(false); dv.list.bar:SetShown(false) end
  if not d then return end

  local m = Model.dungeon(d, ctx.state, ctx.db)
  dv.header:SetText(m.header)
  dv.header:SetShown(true)
  dv.progress:SetText(m.progress)
  dv.progress:SetShown(true)
  if dv.list then
    local elements = {}
    for i, step in ipairs(m.steps) do
      elements[i] = { kind = "step", step = step, height = RouteView.stepHeight(step) }
    end
    dv.list.box:SetShown(true); dv.list.bar:SetShown(true)
    dv.list:set(elements, "dungeon:" .. tostring(v.key))
  end

  local place, label = m.info.place, m.title .. " entrance"
  local function showEntrance() UI.Nav.showPlace(place, label, "entrance") end
  if v.questID then
    dv.detailBox:SetShown(true)
    dv.backToDungeon:SetText("Back to " .. m.title)
    dv.detail:show(v.questID, { dungeon = v.key })
    return
  end
  dv.info:SetShown(true)
  dv.name:SetText(m.title)
  dv.meta:SetText(m.info.meta)
  dv.why:SetText(m.info.why or "")
  dv.entrance:SetText(m.info.entrance)
  dv.pin:SetScript("OnClick", showEntrance)
  dv.mapButton:SetScript("OnClick", showEntrance)
  dv.pin:SetShown(place ~= nil)
  if place then dv.mapButton:Enable() else dv.mapButton:Disable() end
  if dv.questList then
    local rows = {}
    for _, id in ipairs(m.quests) do
      local row = ctx.db and ctx.state and QuestInfo.row(ctx.db, id, ctx.state)
      if row then
        rows[#rows + 1] = { kind = "quest", row = row, height = UI.QuestRow.HEIGHT,
          order = #rows, group = QuestInfo.statusGroup(row) }
      end
    end
    -- I1: what this character can act on first; the data's order within a group
    table.sort(rows, function(a, b)
      if a.group ~= b.group then return a.group < b.group end
      return a.order < b.order
    end)
    dv.questsHeading:SetText("All quests (" .. #rows .. ")")
    dv.questList:set(rows, "dungeon:" .. tostring(v.key))
  end
end

UI.registerView("dungeon", { build = buildDungeon, update = updateDungeon, title = dungeonTitle })
