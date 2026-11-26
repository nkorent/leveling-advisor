local _, ns = ...

ns.Tuning = {
  HUB_RADIUS_YD = 150,
  RIGHT_HERE_YD = 300,
  SOON_LEVELS = 2,
  -- A quest more than this many levels above the player is never offered (not in the log).
  MAX_LEVELS_ABOVE = 4,
  DEFAULT_ZONE_YARDS = { 3000, 2000 },
  HUB_BONUS = 0.25,
  HUB_BONUS_CAP = 1.0,
  TRAVEL_XP_PER_YD = 0.2,
  CONTINENT_CHANGE_XP = 4000,
  ELITE_SOLO_FACTOR = 0.5,
  DUNGEON_RUN_XP = 3000,
  DUNGEON_LEVEL_WINDOW = 2,
  MAX_ZONES = 3,
  HERE_MIN_QUESTS = 2,
  -- turnin and class sections are unlimited
  SECTION_LIMITS = { here = 6, chains = 4, next = 3 },
  LINK_XP = { walk = 0, boat = 500, zeppelin = 500, tram = 300, portal = 200, flight = 300 },
  ROUTE_IMPROVE_MAX_PASSES = 8,
  ROUTE_IMPROVE_MAX_MS = 3,
  -- Hard stop that needs no clock: about 9 ms interpreted on the busiest synthetic zone
  -- (less with JIT). ROUTE_IMPROVE_MAX_MS is what limits in-game time.
  ROUTE_IMPROVE_MAX_CANDIDATES = 10000,
  ROUTE_IMPROVE_MIN_GAIN_YD = 1,
}
