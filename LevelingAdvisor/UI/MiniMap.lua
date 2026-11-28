local addonName, ns = ...; ns.UI = ns.UI or {}; ns.UI.MiniMap = ns.UI.MiniMap or {}
local MiniMap = ns.UI.MiniMap
local UI = ns.UI
local Style, QuestInfo, ZoneArt = UI.Style, UI.QuestInfo, UI.ZoneArt
local method = ns.Util.method

-- The zone mini map of the detail page: the quest's giver, turn-in and
-- objectives on the zone art; hover names a marker, click sets a waypoint.
-- An objective dot's tooltip says what it is (QuestInfo.objectiveTooltip: name,
-- kind and count, where an item drops, live progress from the quest log).
-- No player dot.
MiniMap.W, MiniMap.H = 300, 200

local SHIELD = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\PinShield"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CAPTION_H = 16

local function level(frame, plus)
  return (method(frame, "GetFrameLevel") or 1) + plus
end

local function disc(parent, size, color, layer)
  local t = Style.texture(parent, layer or "ARTWORK", nil, DISC)
  t:SetSize(size, size)
  t:SetPoint("CENTER", parent, "CENTER", 0, 0)
  t:SetVertexColor(color[1], color[2], color[3])
  return t
end

local function newMarker(mm)
  local b = CreateFrame("Button", nil, mm.box)
  method(b, "SetFrameLevel", level(mm.box, 4))
  b.shield = Style.texture(b, "ARTWORK", nil, SHIELD)
  b.shield:SetSize(16, 18)
  b.shield:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.glyph = Style.texture(b, "OVERLAY", "QuestNormal", QuestInfo.MARKER_FILES.QuestNormal)
  b.glyph:SetSize(9, 9)
  b.glyph:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.rim = disc(b, 11, { 0, 0, 0 }, "BACKGROUND")
  b.dot = disc(b, 9, { 0.9, 0.25, 0.15 }, "ARTWORK")
  b:SetScript("OnEnter", function(self)
    if type(GameTooltip) ~= "table" or not self.point then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.point.kind == "objective" then
      local model = mm.model
      local live = QuestInfo.liveObjectives(model and model.questID)
      for i, l in ipairs(QuestInfo.objectiveTooltip(self.point, model, live)) do
        if i == 1 then GameTooltip:SetText(l[1], l[2], l[3], l[4]) else GameTooltip:AddLine(l[1], l[2], l[3], l[4]) end
      end
    else
      GameTooltip:SetText(self.point.label .. " " .. Style.coords(self.point.x, self.point.y), 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
  end)
  b:SetScript("OnClick", function(self)
    local p = self.point
    if p and mm.mapID then
      UI.Nav.showPlace({ mapID = mm.mapID, x = p.x, y = p.y }, p.label, p.kind)
    end
  end)
  return b
end

local function place(mm, w, x, y)
  w:ClearAllPoints()
  w:SetPoint("CENTER", mm.box, "TOPLEFT", x / 100 * MiniMap.W, -y / 100 * MiniMap.H)
end

function MiniMap.new(parent)
  local mm = { markers = {} }
  mm.frame = CreateFrame("Frame", nil, parent)
  mm.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  mm.frame:SetSize(MiniMap.W, MiniMap.H + CAPTION_H)
  mm.box = ZoneArt.newBox(mm.frame, MiniMap.W, MiniMap.H)
  mm.box:SetPoint("TOPLEFT", mm.frame, "TOPLEFT", 0, 0)
  mm.caption = Style.text(mm.frame, "GameFontNormalSmall", Style.INK_SOFT)
  mm.caption:SetPoint("TOPLEFT", mm.frame, "TOPLEFT", 0, -(MiniMap.H + 4))
  mm.caption:SetWidth(MiniMap.W)
  mm.caption:SetWordWrap(true)

  -- Hides the map; shows it for `model` (QuestInfo.miniMap). `quest` is the
  -- detail model. Returns the height the section needs, 0 when hidden.
  function mm:show(model, quest)
    if not model then self:hide(); return 0 end
    self.mapID, self.model = model.mapID, model
    ZoneArt.draw(self.box, model.mapID, "fit")
    for _, m in ipairs(self.markers) do m:Hide() end
    for i, p in ipairs(model.points) do
      local m = self.markers[i]
      if not m then m = newMarker(self); self.markers[i] = m end
      m.point = p
      if p.kind == "objective" then
        m:SetSize(11, 11)
        m.shield:Hide(); m.glyph:Hide(); m.rim:Show(); m.dot:Show()
      else
        m:SetSize(16, 18)
        local turnin = p.kind == "turnin" or model.complete
        local atlas = turnin and "QuestTurnin" or "QuestNormal"
        Style.setTexture(m.glyph, atlas, QuestInfo.MARKER_FILES[atlas], false)
        m.shield:Show(); m.glyph:Show(); m.rim:Hide(); m.dot:Hide()
      end
      place(self, m, p.x, p.y)
      m:Show()
    end
    local lines = { (model.mapName or "Map") .. " — click a marker for a waypoint" }
    for _, o in ipairs(model.others) do
      lines[#lines + 1] = "+" .. Style.plural(o.count, "point") .. " in " .. o.name
    end
    self.caption:SetText(table.concat(lines, "\n"))
    self.frame:Show()
    local h = MiniMap.H + 4 + math.max(self.caption:GetStringHeight() or 0, CAPTION_H - 4)
    self.frame:SetHeight(h)
    return h
  end

  function mm:hide()
    self.mapID, self.model = nil, nil
    self.frame:Hide()
  end
  return mm
end
