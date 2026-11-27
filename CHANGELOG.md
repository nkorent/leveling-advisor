# Changelog

## 0.2.0 (beta), 2026-11-27

- **Restart the game after updating** (this version adds new files; /reload is not enough).
- **Unlock Path:** a quest's details show the chain of quests that unlock it, in order, with what is done, where to start, and the XP on the way. Long chains fold their done steps.
- **Chain badge:** on a dungeon's quest list, a chain-link icon marks quests that need earlier quests, with how many are left.
- Prerequisite quests that the advisor does not recommend (for example ones started from an item) still appear in the chain by name.
- **Chain n/m** now counts the same quests as the Unlock Path.
- **Fixed:** a Lua error after every recompute while the world map had not been opened yet.

## 0.1.0 (beta), 2026-11-26

First public beta for WoW: Forever (1.60.1).

- **Book window** (`/advisor`, a key binding, the bookmark on the Map & Quest Log, or the minimap button): recommended zones, quests and dungeon for your character.
- **Zone routes:** an ordered, step-by-step plan through a zone, with done steps checked off.
- **Quest details:** levels, chain progress, giver location, a zone mini map with markers, objectives, and reward items with tooltips, links and dressing-room preview.
- **Quest search** by name, and a **right-click menu**: Show on Map, Link to Chat, Ignore.
- **World-map pins** for recommended quest givers and turn-ins; click a pin to set a waypoint.
- **Dungeon advice:** which quests to pick up before you go, and where the entrance is.
- Every race and class, including Skyborne. A quest is never recommended when the data says your character cannot take it.
