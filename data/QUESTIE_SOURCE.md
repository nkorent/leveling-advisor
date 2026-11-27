# Questie source: QuestieDB Forever (vendored, git-ignored under data/vendor/)

Since Questie v12 the quest, NPC, object and item data lives in **QuestieDB**, Questie's data repository.
Its **Forever** flavor is what the pipeline reads (`pipeline/questiedb.py`). Nothing under
`data/vendor/` is committed.

## Inputs

- **QuestieDB**: https://github.com/Questie/QuestieDB, commit
  `6c9c71280e1295e96985825bcc49c79d470f01ea` (2026-11-26), a git clone at `data/vendor/QuestieDB/`.
  The build reads the commit from the clone's `.git` and writes `QuestieDB 6c9c712 Forever (GPL-3.0)`
  in `Meta.lua` and `report.json`.
- **Questie quest blacklist**: `QuestieQuestBlacklist.lua` from Questie master
  (https://github.com/Questie/Questie), commit `7cbd9c305c9e885d69b2317c690ecf4e9fcf75fb` (recorded in
  `data/vendor/Questie-master/COMMIT`), at
  `data/vendor/Questie-master/Database/Corrections/QuestieQuestBlacklist.lua`. It has Forever entries
  (`Questie.IsForever`).

CLI: `python -m pipeline build [--questiedb data/vendor/QuestieDB] [--questie-blacklist <file>]`.
A missing or unreadable input exits 2 with the paths it could not use. `--without questie` builds without
all of it: QuestieDB data, blacklist and QuestieDB XP.

## Never run their tools

Only data, correction, enum and support files are **evaluated**; QuestieDB's and Questie's code and tools
(`generate.lua`, `questiedb.sh`, `tools/*`, `src/corrections/tablePatch.lua`, ...) are never run. Raw data
strings are evaluated in an empty Lua environment. Everything else runs in the lupa sandbox shared with
`pipeline/questie.py`: `register_eval` off; `os`, `io`, `require`, `load`, `loadstring`, `dofile`,
`loadfile`, `debug`, `package` and `collectgarbage` raise an error when used (the build then exits 2);
`QuestieLoader` (`CreateModule` / `ImportModule` return plain tables pre-filled with keys and enums),
`QuestieDB`, `ZoneDB` and `Questie` are stubs; any other global is a harmless proxy, and a correction
value that still contains one is skipped and listed (`unresolved`). The `_add` / `_remove` table
operations of QuestieDB's ADR 0016 are reimplemented in Python.

## What is read, in order

1. **Raw data**: `data/Forever/forever{Quest,Npc,Object,Item}DB.lua` (`QuestieDB.<x>Data = [[return {...}]]`,
   Era data with coordinates converted to Forever map frames). Field indices come from each file's own
   `QuestieDB.<x>Keys`. Checked against `src/meta/{quest,npc,object,item}Meta.lua`, and any failure stops
   the build:
   - the file's key table must equal the meta `keys` table (same names, same indices), except that it
     may lack trailing meta keys (fields added after the data was written: the item data has no
     `teachesSpell`, index 16);
   - every meta key index must lie in 1..`fieldCount`, be unique and have a `types` entry (number,
     string or table);
   - every table-typed field the loader reads must have a `structures` entry.

   The loader then takes each field's type and shape (`types`, `structures`) from the meta file as
   given; it does not check them against the data. Only the fields the merge needs are read (items:
   `name`, `npcDrops`, `objectDrops`, for the quest objectives of Contract A field 26).
2. **Enums**: every `src/corrections/enum/*.lua` (`constants.lua` first), chosen for Forever as
   QuestieDB's correction compat does: the shared table, else Forever's own (`raceKeys` with
   `SKYBORNE_ALLIANCE`/`SKYBORNE_HORDE`, `npcFlags`), else Classic's (`classKeys`).
3. **Static correction layers**, in the order `docs/forever.md` gives (a later layer wins):
   1. legacy: `src/corrections/Forever/legacy/classic{Quest,NPC,Object,Item}Fixes.lua` `Load()` (the
      quest reputation and item-start providers are not read);
   2. generated delta-base: `src/corrections/Forever/generated/foreverBase{Quest,Npc,Object,Item}.lua`;
   3. traces: `src/corrections/Forever/traces/forever{Quest,Npc,Object,Item}Traces.lua`;
   4. relation traces: `src/corrections/Forever/traces/foreverQuestRelationTraces.lua`;
   5. authored: `src/corrections/Forever/forever{Quest,NPC,Object,Item}Fixes.lua` `Load()`.

   Scalars replace; `{}` clears a field; `<field>_add` (index + 1000) and `<field>_remove` (index - 1000)
   follow ADR 0016 (lists, starter/finisher groups with positional nil holes such as `{nil, {424005}}`,
   objective groups, spawn zones, atomic pairs). A row for an id that does not exist yet creates it only
   when it carries a name (`created`; others `skipped`). An operation QuestieDB would reject is skipped
   and listed (`rejected`). The layer that last set each field is kept: a race mask from the Era data or
   the legacy layer has origin `era`, one from any Forever layer `forever`.
4. **Dynamic corrections**: legacy `LoadFactionFixes()` then `LoadDynamic()`, each evaluated once for
   Alliance and once for Horde (`UnitFactionGroup` stub). A field both factions compose to the same
   value is applied. Where they disagree on `startedBy` / `finishedBy` the per-group union is stored
   (`faction_conflicts`). Where they disagree on any other quest field the merge gates on (levels,
   race/class masks, prerequisites, exclusiveTo, breadcrumb, skill, reputation, max level,
   specialization, special flags), both values are kept (`faction_dependent`, the quest's
   `faction_fixes`): the merge applies the value of the quest's own faction and excludes a quest of
   both factions as `faction-fix-unclear`. Other disagreements (quest name, objectives, source item;
   NPC and object spawns; item drop sources) keep the static value (`dynamic_not_applied`).
5. **Blacklist**: `QuestieQuestBlacklist:Load()` with a Forever client stub: `Questie.IsForever = true`,
   every other `Questie.Is*` flag (`IsClassic`, `IsEra`, `IsSoD`, `IsTBC`, `IsWotlk`, `IsCata`, `IsMoP`,
   ...) false, `Expansions = {Era = 1, Tbc = 2, Wotlk = 3, Cata = 4, MoP = 5, Current = 1}`. `true`
   entries hide the quest (`questie-hidden`), also when QuestieDB does not have it (`hidden_ids`);
   `HIDE_ON_MAP` entries do not.
6. **Spawns**: NPC and object `spawns` (`{[areaId] = {{x, y, phase?}, ...}}`) are mapped to uiMapIDs
   with `support/Forever/Zones/areaIdToUiMapId.lua`: its `areaIdToUiMapIdOverride` table first, then
   `areaIdToUiMapId`. A mapping to 0 or no mapping drops the spawn; so do pairs outside 0..100 and the
   `-1` placeholders. Coordinates are kept as given (already Forever frames).
7. **Quest XP**: `support/Forever/QuestXP/xpDB-classic.lua`, then `xpDB-traces.lua` (traces win):
   `{questId: (level, xp)}`.

**Not applied: QuestieDB's Derived Passes** (its ADR 0004: the required-races inference over zero masks,
gathering-node spawn handling, waypoint simplification). They are code, so they are not run; the loaded
data is the corrected data before those passes, not byte-for-byte what QuestieDB materialises.

## How the merge uses it

outof.games (1.60.1 game data) stays authoritative; QuestieDB only fills what is missing (see the
`pipeline/merge.py` docstring):

- quest objectives (Contract A field 26: kinds, NPC/object/item names, where items drop; see
  `pipeline/objectives.py`) and the objective of each outof.games objective point;
- quest levels, race/class masks, prerequisites, exclusive/breadcrumb links, items, skill/reputation
  requirements, the blacklist, and NPC factions (`friendlyToFaction`; outof.games NPC pages win). An NPC
  that a Forever layer created without ever stating `friendlyToFaction` has an unknown faction, not
  "hostile to both". A quest created by a Forever layer (not Era data) counts as new in Forever.
- race masks keep the Forever bits (High Order Skyborne 2^32, Windshaper Skyborne 2^33); only
  whole-faction masks become "no race restriction" plus the faction. The classic 77/178/255 count as
  whole-faction only with origin `era`; a Forever layer's 77 is literal (no Skyborne).
- availability gates (`questMeta`): `availableStartingWith` becomes a `prereq.all` entry;
  `availableUntilCompleted` and `disabledByQuest` become Contract A field 25 `unavailableAfter`;
  `parentQuest`, `requiredSpell` and `requiredRanks` exclude the quest (`parent-quest`, `needs-spell`,
  `needs-rank`); a changed-in-Forever quest with any of them is `gate-unclear`. `nextQuestInChain` is
  only counted (`report.json` `next_quest_in_chain`).
- a quest a correction could not be applied to (a skipped nameless row, an unresolved or rejected value
  on a gating field, or a Dynamic Correction that creates it for one faction only) is excluded
  (`correction-skipped`, `correction-unclear`).
- giver points for quests whose giver has no coordinates (and that QuestieDB does not disagree on), from
  QuestieDB starters with a tight spawn on a uiMapID whose QuestieDB NPC spawns agree with outof.games
  (`report.json` `questiedb.spawn_check`); page-less NPC givers of kept quests are emitted from QuestieDB.
- quest XP only when the agreement check passes (`questiedb.xp_check`; at 6c9c712 it does not: 82.6 %
  of the 3097 same-level quests agree, below the 90 % bar, so no XP is filled).

## License

What QuestieDB's `LICENSE.md` (at 6c9c712) says, and what we take from it:

- QuestieDB's initial data, schema and corrections were imported from Questie. That content and its
  later modifications are subject to Questie's licensing (GPL-3.0, https://github.com/Questie/Questie).
  This is why Leveling Advisor is GPL-3.0.
- QuestieDB and the Questie content it was built from historically had no proper license, and not every
  historic contributor has consented to one. The Questie team considers those contributions made in the
  spirit of open source but cannot speak for every contributor. Content not covered otherwise is to be
  treated as "all rights reserved" when in doubt.
- The Questie team is fine with others forking or copying QuestieDB under the GPLv3 terms, while it
  cannot promise that every contributor is.
- Contributors on its GPLv3 list have put their own contributions under GPLv3, and pull requests after
  21.10.2026 count as GPLv3 consent. The authors of the Forever trace and delta-base data (Logon, Muehe
  and others) are on that list.
- The Questie name and logo are not covered. Leveling Advisor does not use them as its branding.

## Updating

Pull the QuestieDB clone (and the blacklist file with its commit), update the commits in this file and
`data/vendor/Questie-master/COMMIT`, run `.venv/bin/pytest pipeline/tests -q` (the real-data smoke tests
load the clone) and `.venv/bin/python -m pipeline build --provisional`, then review `report.json`
(`questiedb` section: layer counts, rejected/unresolved values, spawn check, XP check).

## History

Until 2026-11-26 the pipeline read Questie v11.38.0 (`454b9d0`, Classic Era files under
`Database/Classic/`) at `data/vendor/Questie`. That build path was removed; `pipeline/questie.py` stays
for the sandbox and conversion helpers `pipeline/questiedb.py` reuses.
