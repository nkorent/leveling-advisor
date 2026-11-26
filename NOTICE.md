# Notices

Leveling Advisor is licensed under GPL-3.0 (see `LICENSE`). Its data comes partly from the projects below.
Where the data was taken from is recorded in the source repository, in `data/REFERENCE_SOURCES.md`
and `data/QUESTIE_SOURCE.md`.

## OpenMap (MIT)

Dungeon names, the raid flag, Group Finder level ranges, dungeon entrances, boat and zeppelin routes,
and zone level ranges come from OpenMap (https://github.com/openmap-world/openmap, commit
`6c2299f6e1f9bdce1bbd92145f84a05b0c6c05a7`, files `OpenMap/Data/Forever/Places.lua` and `Levels.lua`).
OpenMap's license notice:

```text
MIT License

Copyright (c) 2026 OpenMap contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Questie and QuestieDB (GPL-3.0)

The quest database is imported from QuestieDB (https://github.com/Questie/QuestieDB, commit `6c9c712`),
Questie's data repository, in its WoW: Forever flavor: Era data converted to Forever map frames, the
generated Forever delta-base, the Forever trace layers and the Forever quest XP tables. The quest
blacklist comes from Questie (https://github.com/Questie/Questie, commit `7cbd9c3`).

Questie is licensed under GPL-3.0. Per QuestieDB's LICENSE.md, the content QuestieDB imported from
Questie, and its later modifications, follow Questie's licensing; that is why Leveling Advisor is
GPL-3.0 too. The same file says the Questie team accepts forks and copies of QuestieDB under the GPLv3
terms but cannot promise that every historic contributor agrees (not all have consented), and that
content not otherwise covered is to be treated as "all rights reserved" when in doubt. The authors of
the Forever trace and delta-base data (Logon, Muehe and others) are on its list of contributors who put
their contributions under GPLv3. The Questie name and logo are not ours and are not used as Leveling
Advisor's branding.
