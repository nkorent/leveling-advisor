local addonName, ns = ...

-- Shared look of the book: colours, sizes, text formatters (pure) and small
-- widget helpers. A missing atlas falls back to a texture file.
ns.UI = ns.UI or {}
local Style = ns.UI.Style or {}
ns.UI.Style = Style

local call = ns.Util.call

---------------------------------------------------------------------------
-- Colours and sizes.
---------------------------------------------------------------------------
Style.INK = { 0.20, 0.13, 0.05 }
Style.INK_SOFT = { 0.40, 0.29, 0.14 }
Style.GOLD = { 1.0, 0.82, 0.0 }
Style.REASON = { 0.56, 0.89, 0.56 }
Style.LEATHER = { 0.23, 0.15, 0.07 }

-- Difficulty colour names (Engine/Difficulty.lua) -> RGB: the map pins' table.
Style.DIFFICULTY = ns.MapPins.COLORS

Style.WIDTH = 860
Style.HEIGHT = 620
Style.PAGE_PAD = 18
Style.CONTENT_W = 382

---------------------------------------------------------------------------
-- Formatters (pure).
---------------------------------------------------------------------------
-- 7030 -> "7,030" (rounded to a whole number).
function Style.number(n)
  n = math.floor((tonumber(n) or 0) + 0.5)
  local digits = string.format("%d", math.abs(n))
  local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return (n < 0 and "-" or "") .. out
end

-- (10, 20) -> "10–20" (en dash).
function Style.levels(min, max)
  return tostring(min) .. "–" .. tostring(max)
end

-- (37.4, 40.1) -> "(37.4, 40.1)"; one decimal.
function Style.coords(x, y)
  return string.format("(%.1f, %.1f)", tonumber(x) or 0, tonumber(y) or 0)
end

-- 12403 -> "1g 24s 3c"; zero parts are left out (0 -> "0c").
function Style.money(copper)
  copper = math.floor(tonumber(copper) or 0)
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) % 100
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = Style.number(g) .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  if #parts == 0 then return "0c" end
  return table.concat(parts, " ")
end

-- (6, "quest") -> "6 quests".
function Style.plural(n, word)
  return Style.number(n) .. " " .. word .. (n == 1 and "" or "s")
end

---------------------------------------------------------------------------
-- Widget helpers.
---------------------------------------------------------------------------
-- Dark text (relative luminance under 0.5) is ink for the parchment.
local function luminance(r, g, b)
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

function Style.isInk(color)
  if type(color) ~= "table" then return false end
  return luminance(color[1], color[2], color[3]) < 0.5
end

-- GameFont* objects carry a black drop shadow meant for dark backgrounds; on
-- the parchment it smears dark ink. QuestFont and friends have none.
local function hasFontShadow(fs)
  return type(fs.laFont) == "string" and fs.laFont:find("^GameFont") ~= nil
end

-- Removes the drop shadow of ink text (no-op on shadowless fonts).
function Style.ink(fs)
  if hasFontShadow(fs) and not fs.laInked then
    fs:SetShadowOffset(0, 0)
    fs:SetShadowColor(0, 0, 0, 0)
    fs.laInked = true
  end
end

-- SetTextColor that also drops the shadow for ink colours, and gives the
-- font's usual shadow back when a recoloured FontString turns light again.
function Style.setTextColor(fs, r, g, b)
  fs:SetTextColor(r, g, b)
  if luminance(r, g, b) < 0.5 then
    Style.ink(fs)
  elseif fs.laInked then
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs.laInked = nil
  end
end

-- A left-justified FontString (default QuestFont), in `color` when given.
function Style.text(parent, font, color)
  font = font or "QuestFont"
  local fs = parent:CreateFontString(nil, "ARTWORK", font)
  fs.laFont = font
  fs:SetJustifyH("LEFT")
  if color then Style.setTextColor(fs, color[1], color[2], color[3]) end
  return fs
end

-- A QuestTitleFont heading in ink with a 1 px rule below it (fs.rule).
function Style.heading(parent, label)
  local fs = Style.text(parent, "QuestTitleFont", Style.INK)
  fs:SetText(label)
  local rule = parent:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(Style.INK[1], Style.INK[2], Style.INK[3], 0.35)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
  rule:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
  fs.rule = rule
  return fs
end

local function hasAtlas(atlas)
  if not atlas or type(C_Texture) ~= "table" then return false end
  return call(C_Texture.GetAtlasInfo, atlas) ~= nil
end

-- Shows `atlas` on tex when the client has it, else the file; clears the
-- desaturation unless `desaturated`.
function Style.setTexture(tex, atlas, file, desaturated)
  if hasAtlas(atlas) then
    tex:SetAtlas(atlas)
  elseif file then
    tex:SetTexture(file)
  end
  tex:SetDesaturated(desaturated and true or false)
end

-- A texture showing `atlas` when the client has it, else the file.
function Style.texture(parent, layer, atlas, file)
  local tex = parent:CreateTexture(nil, layer or "ARTWORK")
  Style.setTexture(tex, atlas, file, false)
  return tex
end

-- A native red button (UIPanelButtonTemplate), 22 px high.
function Style.button(parent, label, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 120, 22)
  b:SetText(label)
  return b
end

local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SHIELD = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\PinShield"

-- The round "Show on Map" button: gold ring, dark disc, the pin's shield.
function Style.pinButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(26, 26)
  local ring = Style.texture(b, "BACKGROUND", nil, DISC)
  ring:SetSize(26, 26)
  ring:SetPoint("CENTER", b, "CENTER", 0, 0)
  ring:SetVertexColor(0.54, 0.42, 0.20)
  local disc = Style.texture(b, "BORDER", nil, DISC)
  disc:SetSize(23, 23)
  disc:SetPoint("CENTER", b, "CENTER", 0, 0)
  disc:SetVertexColor(0.16, 0.11, 0.05)
  local icon = Style.texture(b, "ARTWORK", nil, SHIELD)
  icon:SetSize(12, 14)
  icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetHighlightTexture(DISC, "ADD")
  local hl = call(b.GetHighlightTexture, b)
  if type(hl) == "table" then ns.Util.method(hl, "SetAlpha", 0.25) end
  b.ring, b.disc, b.icon = ring, disc, icon
  b:SetScript("OnClick", function() if onClick then onClick() end end)
  b:SetScript("OnEnter", function(self)
    if type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Show on Map", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
  return b
end
