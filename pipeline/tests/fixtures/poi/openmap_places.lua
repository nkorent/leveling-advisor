-- Hand-written test fixture in the OpenMap Places layout (not copied from OpenMap).
--   instances[i] = { continent, x, y, { { mapID, name, raid, minLevel, maxLevel }, ... } }
--     or { nil, x, y, { ... }, map = uiMapID } (0..1 on that zone's map)
--   transports[i] = { kind, route, continent, x, y, toContinent, toX, toY }; faction =: one faction's only

local _, ns = ...

ns.MapPlaces = {
	instances = {
		{ 1, 4249.1, 748.4, { { 48, "Deep Caves", false, 22, 32 } } },
		{ 0, 2892.2, -811.3, { { 189, "Old Abbey - Garden", false, 30, 38 }, { 189, "Old Abbey - Vault", false, 36, 44 } } },
		{ 0, -7522.5, -1233.0, { { 409, "Big Lair", true, 60, 60 } } },
		{ nil, 0.725, 0.114, { { 2999, "Sunken Ruins", false, 15, 22 } }, map = 1458 },
		{ 1, 10.0, 20.0, { { 800, "Lost Vault", false, 40, 45 } } },
	},
	unplaced = {
		{ 0, "Unplaced Den", false, 10, 15 },
	},
	bosses = {
		[48] = { "Cave Boss" },
	},
	transports = {
		{ "boat", "Saltmere - Mossvale", 0, -3905.2, -585.8, 1, -4016.4, -4740.6 },
		{ "boat", "Saltmere - Mossvale", 1, -4016.4, -4740.6, 0, -3905.2, -585.8, faction = "Alliance" },
	},
	sailings = {
	},
}
