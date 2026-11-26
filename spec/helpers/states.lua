-- Contract B player states for the engine specs. Each is an independent copy.
local function s18(level)
  return {
    faction = "Alliance", raceMask = 8, classMask = 1024, classFile = "DRUID",
    level = level, mapID = 1439, x = 38.0, y = 41.0,
    greyAtOrBelow = nil,
    completed = { [4762] = true, [965] = true },
    log = { [966] = { complete = false }, [4730] = { complete = true } },
    ignored = {}, recordedXP = {},
    settings = { elite = true, dungeons = true },
  }
end

return {
  S18 = s18(18),
  S20 = s18(20),
  H20 = {
    faction = "Horde", raceMask = 2, classMask = 1, classFile = "WARRIOR",
    level = 20, mapID = 1411, x = 52.0, y = 43.0,
    greyAtOrBelow = nil,
    completed = {}, log = {}, ignored = {}, recordedXP = {},
    settings = { elite = true, dungeons = true },
  },
}
