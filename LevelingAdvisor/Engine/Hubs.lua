local _, ns = ...

local Hubs = {}
ns.Hubs = Hubs

-- Greedy clustering in input order. points = { {mapID, x, y, ref} }.
-- A point joins the first same-map hub whose running-mean centroid is within
-- radiusYd; otherwise it starts a new hub. -> { {mapID, x, y, members} }
function Hubs.cluster(db, points, radiusYd)
  local hubs = {}
  local sqrt, floor = math.sqrt, math.floor
  -- Spatial grid per map so a point only meets nearby hubs. The grid is only
  -- a filter (cells are slightly wider than the radius); the join test and the
  -- "first hub in creation order" rule are unchanged.
  local cellYd = radiusYd * 1.01
  local maps = {}
  local order, cellOf = {}, {}   -- hub -> creation index, hub -> grid key

  local function key(kx, ky, x, y)
    return floor(x / 100 * kx / cellYd) * 65536 + floor(y / 100 * ky / cellYd)
  end

  local function add(p)
    local mapID, x, y, ref = p[1], p[2], p[3], p[4]
    if not (mapID and x and y) or radiusYd <= 0 then
      -- unusable point or radius: a hub of its own, outside the grid
      hubs[#hubs + 1] = { mapID = mapID, x = x, y = y, members = { ref } }
      return
    end
    local m = maps[mapID]
    if not m then
      local w, h = ns.Geo.zoneYards(db, mapID)
      m = { w = w, h = h, cells = {} }
      maps[mapID] = m
    end
    local w, h, cells = m.w, m.h, m.cells
    local cx, cy = floor(x / 100 * w / cellYd), floor(y / 100 * h / cellYd)
    local home, homeIdx
    for gx = cx - 1, cx + 1 do
      for gy = cy - 1, cy + 1 do
        local list = cells[gx * 65536 + gy]
        if list then
          for i = 1, #list do
            local hub = list[i]
            local idx = order[hub]
            if not homeIdx or idx < homeIdx then
              local dx, dy = (x - hub.x) / 100 * w, (y - hub.y) / 100 * h
              if sqrt(dx * dx + dy * dy) <= radiusYd then home, homeIdx = hub, idx end
            end
          end
        end
      end
    end
    if home then
      local n = #home.members + 1
      home.x = home.x + (x - home.x) / n
      home.y = home.y + (y - home.y) / n
      home.members[n] = ref
      local nk = key(w, h, home.x, home.y)
      local ok = cellOf[home]
      if nk ~= ok then
        local list = cells[ok]
        for i = 1, #list do
          if list[i] == home then list[i] = list[#list]; list[#list] = nil; break end
        end
        local dest = cells[nk]
        if not dest then dest = {}; cells[nk] = dest end
        dest[#dest + 1] = home
        cellOf[home] = nk
      end
    else
      local hub = { mapID = mapID, x = x, y = y, members = { ref } }
      hubs[#hubs + 1] = hub
      order[hub] = #hubs
      local k = key(w, h, x, y)
      local dest = cells[k]
      if not dest then dest = {}; cells[k] = dest end
      dest[#dest + 1] = hub
      cellOf[hub] = k
    end
  end
  for _, p in ipairs(points) do add(p) end
  return hubs
end
