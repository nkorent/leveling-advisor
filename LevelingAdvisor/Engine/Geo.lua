local _, ns = ...

local Geo = {}
ns.Geo = Geo

local sqrt = math.sqrt

-- Accepts {mapID, x, y} or {mapID = , x = , y = }.
local function unpack3(p)
  if not p then return nil, nil, nil end
  return p.mapID or p[1], p.x or p[2], p.y or p[3]
end
Geo.unpackPoint = unpack3

function Geo.zoneYards(db, mapID)
  local z = mapID and db:zone(mapID)
  local y = z and z.yards
  if y and y[1] and y[2] then return y[1], y[2] end
  local d = ns.Tuning.DEFAULT_ZONE_YARDS
  return d[1], d[2]
end

-- -> continentID, cx, cy (0-1), or nil when the zone has no rect.
function Geo.continentPoint(db, mapID, x, y)
  local z = mapID and db:zone(mapID)
  local r = z and z.rect
  if not (r and z.continent and x and y) then return nil end
  return z.continent,
    r[1] + (x / 100) * (r[2] - r[1]),
    r[3] + (y / 100) * (r[4] - r[3])
end

-- -> yards|nil, sameContinent
function Geo.distance(db, a, b)
  local m1, x1, y1 = unpack3(a)
  local m2, x2, y2 = unpack3(b)
  if not (m1 and m2 and x1 and y1 and x2 and y2) then return nil, false end

  if m1 == m2 then
    local w, h = Geo.zoneYards(db, m1)
    local dx, dy = (x2 - x1) / 100 * w, (y2 - y1) / 100 * h
    return sqrt(dx * dx + dy * dy), true
  end

  local z1, z2 = db:zone(m1), db:zone(m2)
  local c1, c2 = z1 and z1.continent, z2 and z2.continent
  local same = (c1 ~= nil and c1 == c2)
  if not same then return nil, false end
  local k1, cx1, cy1 = Geo.continentPoint(db, m1, x1, y1)
  local k2, cx2, cy2 = Geo.continentPoint(db, m2, x2, y2)
  local cont = db:continent(c1)
  if not (k1 and k2 and cont and cont.yards) then return nil, same end
  local dx = (cx2 - cx1) * cont.yards[1]
  local dy = (cy2 - cy1) * cont.yards[2]
  return sqrt(dx * dx + dy * dy), true
end
