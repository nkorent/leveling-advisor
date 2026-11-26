-- Simple O(n*h) reference for Hubs.cluster, used by the property test.
-- Points are processed greedily in input order. A point joins the FIRST hub
-- (creation order) on the same map whose running-mean centroid is within
-- radiusYd (<=); otherwise it starts a new hub. Same distance arithmetic as
-- Geo.distance on one map: (dx / 100 * w, dy / 100 * h) with the zone's yards.
return function(ns, db, points, radiusYd)
  local hubs = {}
  for _, p in ipairs(points) do
    local mapID, x, y, ref = p[1], p[2], p[3], p[4]
    local w, h = ns.Geo.zoneYards(db, mapID)
    local home
    for _, hub in ipairs(hubs) do
      if hub.mapID == mapID then
        local dx, dy = (x - hub.x) / 100 * w, (y - hub.y) / 100 * h
        if math.sqrt(dx * dx + dy * dy) <= radiusYd then home = hub; break end
      end
    end
    if home then
      local n = #home.members + 1
      home.x = home.x + (x - home.x) / n
      home.y = home.y + (y - home.y) / n
      home.members[n] = ref
    else
      hubs[#hubs + 1] = { mapID = mapID, x = x, y = y, members = { ref } }
    end
  end
  return hubs
end
