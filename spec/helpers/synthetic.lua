-- Deterministic synthetic Contract A data for performance specs.
--   synthetic(questCount, zoneCount) -> Data table that DB.new accepts.
-- A fixed-seed LCG replaces math.random so every run sees the same world.
-- Zone 1439 (Darkshore, where S18 stands) is always present and gets extra
-- quests so that it is the busiest zone and S18 has real work to do there.
local function lcg(seed)
  local s = seed
  return function(n) -- integer in [0, n)
    -- 1103515245 = 16838 * 65536 + 20077; split so every product stays below 2^53
    s = ((s * 16838 % 32768) * 65536 + s * 20077 + 12345) % 2147483648
    return math.floor(s / 65536) % n
  end
end

local CONTINENTS = {
  [1414] = { name = "Kalimdor", yards = { 36800, 24533 } },
  [1415] = { name = "Eastern Kingdoms", yards = { 40740, 27160 } },
}

return function(questCount, zoneCount)
  local rnd = lcg(20261124)
  local data = { quests = {}, npcs = {}, zones = {}, continents = CONTINENTS, dungeons = {}, meta = {} }

  -- zones: ids 1439 and 2001.., laid out on a 5-wide grid per continent
  local ids = { 1439 }
  for i = 1, zoneCount - 1 do ids[#ids + 1] = 2000 + i end
  local perContinent = math.ceil(zoneCount / 2)
  local order = {} -- zones in link order per continent
  for i, id in ipairs(ids) do
    local continent = (i <= perContinent) and 1414 or 1415
    local k = (continent == 1414) and (i - 1) or (i - 1 - perContinent)
    local col, row = k % 5, math.floor(k / 5)
    local x1, y1 = 0.05 + col * 0.18, 0.05 + row * 0.09
    -- zone 1439 sits at ~level 17-25; the rest spread so levels cover 1-60
    local minLevel = (id == 1439) and 17 or (1 + math.floor((i - 1) * 55 / zoneCount))
    data.zones[id] = {
      name = "Zone " .. id, continent = continent, faction = (id == 1439) and 1 or 3,
      minLevel = minLevel, maxLevel = minLevel + 8, live = true, complete = true,
      yards = { 4000 + rnd(2000), 2700 + rnd(1300) },
      rect = { x1, x1 + 0.16, y1, y1 + 0.08 },
      links = {},
    }
    order[continent] = order[continent] or {}
    table.insert(order[continent], id)
  end
  -- walk links between neighbours, each with its reverse
  for _, list in pairs(order) do
    for i = 1, #list - 1 do
      local a, b = list[i], list[i + 1]
      local za, zb = data.zones[a], data.zones[b]
      za.links[#za.links + 1] = { to = b, kind = "walk", x = 50, y = 95, label = "walk to " .. zb.name }
      zb.links[#zb.links + 1] = { to = a, kind = "walk", x = 50, y = 5, label = "walk to " .. za.name }
    end
  end
  -- one boat across the continents
  local za, zb = data.zones[ids[1]], data.zones[ids[#ids]]
  za.links[#za.links + 1] = { to = ids[#ids], kind = "boat", x = 30, y = 40, label = "boat" }
  zb.links[#zb.links + 1] = { to = ids[1], kind = "boat", x = 30, y = 40, label = "boat back" }

  -- dungeons: two, with quests assigned below
  data.dungeons.SYN1 = { name = "Synthetic Deeps", entrance = { 1439, 40, 40 }, minLevel = 20, maxLevel = 26,
    groupSize = 5, faction = 3, live = true, quests = {} }
  data.dungeons.SYN2 = { name = "Synthetic Keep", entrance = { 2010, 50, 50 }, minLevel = 40, maxLevel = 48,
    groupSize = 5, faction = 3, live = true, quests = {} }

  local function place(zoneID)
    return { 1, 100000 + rnd(900000), zoneID, 5 + rnd(900) / 10, 5 + rnd(900) / 10 }
  end

  local n = 0
  local function add(id, zoneID, level, opts)
    opts = opts or {}
    local z = data.zones[zoneID]
    local g = place(zoneID)
    local r = {}
    r[1] = "Quest " .. id
    r[2] = opts.faction or ({ 1, 2, 3, 3 })[1 + rnd(4)]
    if zoneID == 1439 then r[2] = (r[2] == 2) and 3 or r[2] end
    r[5] = math.max(1, level - 3)
    r[6] = level
    r[7] = 1
    r[8] = zoneID
    r[9] = opts.flags or ((rnd(40) == 0) and 1 or 0)
    r[10] = opts.groupSize or ((r[9] % 2 == 1) and 3 or nil)
    r[11] = g
    r[12] = (rnd(3) == 0) and place(zoneID) or nil
    if rnd(4) == 0 then
      r[13] = { { zoneID, 5 + rnd(900) / 10, 5 + rnd(900) / 10 }, { zoneID, 5 + rnd(900) / 10, 5 + rnd(900) / 10 } }
    end
    r[17] = level * 60 + rnd(300)
    r[18] = 1
    r[19] = opts.prereq
    r[22] = opts.chain
    r[23] = opts.dungeonKey
    data.quests[id] = r
    n = n + 1
    return z
  end

  local id = 1
  while n < questCount do
    -- every 25th quest lands in zone 1439 so it stays the busiest zone
    local zoneID = (n % 25 == 0) and 1439 or ids[1 + rnd(#ids)]
    local z = data.zones[zoneID]
    local level = math.min(60, z.minLevel + rnd(9))
    if n % 100 == 1 and n + 3 <= questCount then
      -- a three-step chain
      local base = id
      for step = 1, 3 do
        add(id, zoneID, level, {
          faction = 3, flags = 0,
          chain = { base, step, 3 },
          prereq = step > 1 and { all = { id - 1 } } or nil,
        })
        id = id + 1
      end
    elseif n % 150 == 7 then
      local key = (n % 300 == 7) and "SYN1" or "SYN2"
      local d = data.dungeons[key]
      add(id, zoneID, math.max(d.minLevel, math.min(d.maxLevel, level)), {
        faction = 3, flags = 32, groupSize = 5, dungeonKey = key,
      })
      table.insert(d.quests, id)
      id = id + 1
    else
      add(id, zoneID, level)
      id = id + 1
    end
  end
  return data
end
