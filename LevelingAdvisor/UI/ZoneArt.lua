local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.ZoneArt = ns.UI.ZoneArt or {}
local ZoneArt = ns.UI.ZoneArt
local Style = ns.UI.Style
local call, method = ns.Util.call, ns.Util.method

-- Zone art for the cards and the minimap: the map's background atlas, else its
-- layer-1 tiles, else a parchment card. Tile art is verified in game (the
-- diagnostic's "art" check).
local PARCHMENT_ATLAS, PARCHMENT_FILE = "QuestBG-Parchment", "Interface\\QuestFrame\\QuestBG"

-- Pure. Where a layer's tiles go inside a boxW x boxH box.
--   "crop": the layer is scaled to the box width, its middle rows kept, and
--           only the tiles that intersect the box are listed.
--   "fit":  the layer is scaled to fit whole and centred; every tile is listed.
-- Returns { scale, offsetX, offsetY, tiles = { {index, x, y, w, h} } }; x, y
-- are box-relative (from its top-left, downward positive) and already include
-- the offsets.
function ZoneArt.placement(layer, boxW, boxH, mode)
  local cols = math.ceil(layer.layerWidth / layer.tileWidth)
  local rows = math.ceil(layer.layerHeight / layer.tileHeight)
  local scale, offsetX, offsetY
  if mode == "fit" then
    scale = math.min(boxW / layer.layerWidth, boxH / layer.layerHeight)
    offsetX = (boxW - layer.layerWidth * scale) / 2
    offsetY = (layer.layerHeight * scale - boxH) / 2
  else
    scale = boxW / layer.layerWidth
    offsetX = 0
    offsetY = (layer.layerHeight * scale - boxH) / 2
  end
  local tw, th = layer.tileWidth * scale, layer.tileHeight * scale
  local tiles = {}
  for row = 0, rows - 1 do
    local y = row * th - offsetY
    if mode == "fit" or (y + th > 0 and y < boxH) then
      for col = 0, cols - 1 do
        local x = offsetX + col * tw
        if mode == "fit" or (x + tw > 0 and x < boxW) then
          tiles[#tiles + 1] = { index = row * cols + col + 1, x = x, y = y, w = tw, h = th }
        end
      end
    end
  end
  return { scale = scale, offsetX = offsetX, offsetY = offsetY, tiles = tiles }
end

-- A clipping frame with an atlas texture, a tile canvas (+ pool) and the
-- parchment fallback.
function ZoneArt.newBox(parent, w, h)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(w, h)
  box.width, box.height = w, h
  method(box, "SetClipsChildren", true)
  box.parchment = Style.texture(box, "BACKGROUND", PARCHMENT_ATLAS, PARCHMENT_FILE)
  box.parchment:SetAllPoints(box)
  box.atlasTex = box:CreateTexture(nil, "BACKGROUND", nil, 1)
  box.atlasTex:SetAllPoints(box)
  box.canvas = CreateFrame("Frame", nil, box)
  box.canvas:SetAllPoints(box)
  method(box.canvas, "SetFrameLevel", (method(box, "GetFrameLevel") or 1) + 1)
  box.tilePool = {}
  return box
end

local function validLayer(layer)
  return type(layer) == "table" and (layer.layerWidth or 0) > 0 and (layer.layerHeight or 0) > 0
    and (layer.tileWidth or 0) > 0 and (layer.tileHeight or 0) > 0
end

-- Draws map `mapID` into box; returns "atlas", "tiles" or "none" (parchment).
function ZoneArt.draw(box, mapID, mode)
  box.parchment:Hide()
  box.atlasTex:Hide()
  box.canvas:Hide()
  for _, t in ipairs(box.tilePool) do t:Hide() end

  local atlas = type(C_Map) == "table" and call(C_Map.GetMapArtBackgroundAtlas, mapID)
  if type(atlas) == "string" and atlas ~= "" and pcall(box.atlasTex.SetAtlas, box.atlasTex, atlas) then
    box.atlasTex:Show()
    return "atlas"
  end

  local layers = type(C_Map) == "table" and call(C_Map.GetMapArtLayers, mapID)
  local layer = type(layers) == "table" and layers[1]
  local textures = type(C_Map) == "table" and call(C_Map.GetMapArtLayerTextures, mapID, 1)
  if validLayer(layer) and type(textures) == "table" then
    local placed = ZoneArt.placement(layer, box.width, box.height, mode)
    local used = 0
    for _, t in ipairs(placed.tiles) do
      local fileID = textures[t.index]
      if fileID then
        used = used + 1
        local tex = box.tilePool[used]
        if not tex then
          tex = box.canvas:CreateTexture(nil, "BACKGROUND")
          box.tilePool[used] = tex
        end
        tex:SetTexture(fileID)
        tex:SetSize(t.w, t.h)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", box.canvas, "TOPLEFT", t.x, -t.y)
        tex:Show()
      end
    end
    if used > 0 then
      box.canvas:Show()
      return "tiles"
    end
  end
  box.parchment:Show()
  return "none"
end
