# Changelog

## 0.4.0 (beta), 2026-11-28

- The guide steps aside when you track a quest with the game's quest arrow; click **Resume guide** to continue to your next quest.
- "Continue with waypoint" is now **Resume guide** (the button, the minimap menu and `/advisor guide resume`; `continue` still works).
- The guide no longer pauses when the game itself starts tracking a quest you just accepted or turned in, or right after you log in.
- **Resume guide** always continues from up-to-date data, and after a /reload the guide does not send you back to a spot you already reached.
- Faster: recommendations are computed about 15% quicker, and the world-map pins are no longer rebuilt while the map is closed.
- Under the hood: code cleanup, removal of unused code, and stronger automated tests.

## 0.3.0 (beta), 2026-11-27

- **Restart the game after updating** (this version adds new files; /reload is not enough).
- Text on the book's parchment no longer has a blurry shadow.
- **Level fit:** the advisor recommends only yellow and green quests, and steers you to the zone and route that fit your level. Orange quests and quests you cannot take yet no longer appear in the recommendations.
- **Later — too high for now:** a new, collapsed list in the book with the quests that are too high for now. Each row says at which level it gets good. The list remembers whether it is open, per character.
- **Catch-up:** a zone with mostly green quests shows "Catch up — N quests you skipped at your level".
- **The guide:** it sets a waypoint to the next step of your zone route and moves it when the step changes. Show on Map, a map pin click or a waypoint of your own pauses it until you press "Resume guide", and so does removing its waypoint; it never overrides your own waypoint. While it is paused, the book and the minimap menu say "Guide: Paused" (chat says so once). It waits out combat. Turning it off removes its waypoint. `/advisor guide on|off|resume` controls it.
- **Guide controls:** right-click the minimap button for "Guide: On/Paused/Off", "Resume guide" and "Settings". The book's main page has the same guide toggle and a "Resume guide" button.
- **Quest mini map:** the blue dot for your own position is gone.
- **One waypoint marker:** Show on Map and the map pins now leave just the game's own waypoint pinpoint. Our extra gold pin and the game's square map pin no longer sit on top of it. A waypoint you place yourself keeps its pin. `/advisor debug` now lists the world map's pins, in case a pin still doubles up.
- **At the quest giver:** when you open a quest the advisor recommends, a small "Recommended — take it" ribbon under the quest window says why (its list, zone route step or dungeon) and about how much XP it gives. You can turn it off in the settings: "Mark recommended quests at quest givers".
- **Chain badge:** a chain you cannot finish shows a grey icon instead of a green one, and a dungeon quest your character cannot take says why (for example "Horde only").
- The book's bookmark on the Map & Quest Log now looks like the other side tabs and sits with them.
- The quest mini map's objective dots now say what they are: the item or creature, how many you need, where items drop, and your progress.
- Fixed: required item counts (e.g. Up to Snuff needs 15, not 1).

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
