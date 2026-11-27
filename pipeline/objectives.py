"""Quest objectives: Contract A field 26 and the objective index of each field 13 point.

Each objective is ``{"kind", "id", "name", "count", "from", "from_kind", "from_more"}``:
  kind       "npc" (kill or talk), "object", "item" or "other" (an event or area); the emitter
             encodes them 1-4
  id         the NPC, object or item id, or None
  name       what the game calls it: the objective row's own text when QuestieDB has one (an object
             row's "Hillsbrad Proclamation destroyed"), else the NPC, object or item name; None when
             no source names it
  count      how many, from the objective text by ``count_in_text`` (never guessed), or None
  from       for an item: up to FROM_LIMIT names of the NPCs it drops from (or, without NPC sources,
             the objects it is found in), most relevant first; else None
  from_kind  "npc" | "object" (which of the two ``from`` names), or None
  from_more  True when the item has more distinct source names than ``from`` shows

QuestieDB first (``pipeline.questiedb`` objective rows): creature rows are "npc" objectives named after
the NPC, except a row with its own text, which describes an event ("Peons Awoken", "Servants of
Razelikh Freed"): kind "other", keeping the NPC id; object rows "object"; item rows "item" with their
drop sources; kill-credit rows "npc" with the base NPC. An NPC, object or item named like a
placeholder (Forever's kill-credit dummies "Credit", "DNT KILL CREDIT", "[DNT] ...") gives no name, and
such an NPC row is kind "other". Reputation and spell rows have no name and no place: they make no
objective. A row listed twice (same group, id and text) is one objective.
When QuestieDB has none, every distinct outof.games point name becomes one, kind "other" unless the
name is a QuestieDB item, NPC or object name (in that order); the id only when exactly one has it.

The count rule (``count_in_text``): a number counts for an objective only when it is the one number
(one distinct value) sitting right before the objective's name or a plural/stem of it, with at most
GAP_WORDS lower-case words between ("8 pieces of Tough Wolf Meat", "15 shares of Snuff", "8 Corrupt
Brain stems" for Corrupted Brain Stem, "five pieces of Tough Condor Meat"; digits or a spelled-out one
to twenty). The name must end there: "Firegut Ogre" is not in "7 Firegut Ogre Brutes". A number is
never a count inside a name of the quest's objectives ("Threshwackonator 4100"), inside parentheses
("Lesser Heal (Rank 2)"), after Rank or Level, with a leading zero, or in a hyphenated designation
("A-Me 01"). Otherwise the count is None. There is no "single objective, any number in the text" rule
(fix round 1): that guessed, e.g. Coagulated Rot x7 from "Collect 7 pieces of Living Rot".

A point's index (1-based into the objectives) comes from its outof.games name: the one objective whose
name or entity name it is, else the one item objective it drops from (any source, not only those in
``from``). Two candidates, or none, give None: a point is never attributed by guess.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

FROM_LIMIT = 3
GAP_WORDS = 3
GROUP_KIND = {1: "npc", 2: "object", 3: "item", 5: "npc"}
NAMELESS_GROUPS = (4, 6)   # reputation and spell rows: no name, no place

_TOKEN_RE = re.compile(r"(\d+(?:[.,]\d+)+)|([^\W_][\w'\u2019]*)|([.!?;])")
# Spelled-out numbers count next to a name ("five pieces of Tough Condor Meat"), never in the
# whole-text rule ("one of", "no one" are too common there).
NUMBER_WORDS = {w: n for n, w in enumerate(
    "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen "
    "seventeen eighteen nineteen twenty".split(), 1)}
# Forever's kill-credit dummies: an NPC so named names nothing ("Credit", "DNT KILL CREDIT", "[DNT] ...").
_PLACEHOLDER_RE = re.compile(r"(?i)^\s*(\[(dnt|ph)\]|dnt\b)|\bkill credit\b|^\s*credit\s*$")

@dataclass
class Names:
    """The QuestieDB names the builder reads: {id: name} for NPCs and objects, {id: {"name",
    "npc_drops", "object_drops"}} for items, and NPC / object spawns ({id: [{"map_id", ...}]}) to put
    an item's sources on the quest's own maps first."""
    npcs: dict = field(default_factory=dict)
    objects: dict = field(default_factory=dict)
    items: dict = field(default_factory=dict)
    npc_spawns: dict = field(default_factory=dict)
    object_spawns: dict = field(default_factory=dict)
    _by_name: dict = field(default_factory=dict, init=False, repr=False, compare=False)

    @classmethod
    def from_questiedb(cls, questiedb) -> "Names":
        if questiedb is None:
            return cls()

        def named(table):
            return {i: e["name"] for i, e in (table or {}).items() if (e or {}).get("name")}
        return cls(npcs=named(getattr(questiedb, "npcs", None)), objects=named(getattr(questiedb, "objects", None)),
                   items=dict(getattr(questiedb, "items", None) or {}),
                   npc_spawns=getattr(questiedb, "npc_spawns", None) or {},
                   object_spawns=getattr(questiedb, "object_spawns", None) or {})

    def by_name(self, kind: str) -> dict:
        """{normalised name: [ids]} for "item" | "npc" | "object" (built once per kind)."""
        cache = self._by_name
        if kind not in cache:
            table = {"item": {i: (e or {}).get("name") for i, e in self.items.items()},
                     "npc": self.npcs, "object": self.objects}[kind]
            index: dict = {}
            for ident in sorted(table):
                if table[ident]:
                    index.setdefault(_norm(table[ident]), []).append(ident)
            cache[kind] = index
        return cache[kind]


# ---------------------------------------------------------------- words

def _norm(name: str) -> str:
    """Case, curly apostrophes and spacing folded: how point names are compared."""
    return " ".join(str(name).replace("’", "'").split()).lower()


def _stem(word: str) -> str:
    """A crude English stem, the same for a name's word and its plural or participle in the text:
    wolves/wolf, stems/stem, councilmen/councilman, corrupted/corrupt, harpies/harpy."""
    w = word.lower().replace("’", "'")
    if w.endswith("'s"):
        w = w[:-2]
    w = w.rstrip("'")
    if w.isdigit() or len(w) <= 2:
        return w
    if w.endswith("ies") and len(w) > 4:
        w = w[:-3] + "y"
    elif w.endswith("ves") and len(w) > 4:
        w = w[:-3] + "f"
    elif w.endswith("men") and len(w) > 4:
        w = w[:-3] + "man"
    elif w.endswith("es") and len(w) > 3:
        w = w[:-2]
    elif w.endswith("s") and not w.endswith("ss") and len(w) > 3:
        w = w[:-1]
    if w.endswith("ed") and len(w) > 4:
        w = w[:-2]
    if w.endswith("e") and len(w) > 3:
        w = w[:-1]
    return w


def _tokens(text: str) -> list[tuple[str, str, int, int]]:
    """[(kind, value, start, end)]: kind "int" ("8"), "num" ("1.60"), "word" ("Tough") or "stop" (".").
    A hyphen separates words ("Ogre-Mages"); a period is a stop only at a sentence end (followed by space
    and a capital, or the end): "Vol. 74" is not, "Venture Co. Patrollers" is (a match skips it, see
    _match_end)."""
    out = []
    for m in _TOKEN_RE.finditer(text or ""):
        decimal, word, stop = m.groups()
        if decimal:
            out.append(("num", decimal, m.start(), m.end()))
        elif word:
            out.append(("int" if word.isdigit() else "word", word, m.start(), m.end()))
        elif stop != "." or re.match(r"\s+[A-Z\"']|\s*$", text[m.end():]):
            out.append(("stop", stop, m.start(), m.end()))
    return out


def _name_words(name: str) -> list[str]:
    return [t[1].lower() for t in _tokens(name) if t[0] in ("int", "word")]


def _same_word(text_word: str, name_word: str) -> bool:
    t = text_word.lower()
    return _stem(t) == _stem(name_word) or t == name_word + "s" or name_word == t + "s"


def _match_end(tokens, j: int, words: list[str]) -> int | None:
    """Index after the name ``words`` when they start at tokens[j] (stops between its words skipped:
    "Venture Co. Patrollers"), or None. Not a match when a capitalised word follows: the name only
    begins a longer one there ("Firegut Ogre" in "Firegut Ogre Brutes")."""
    if not words:
        return None
    k = j
    for n, w in enumerate(words):
        while n and k < len(tokens) and tokens[k][0] == "stop":
            k += 1
        if k >= len(tokens) or tokens[k][0] not in ("int", "word") or not _same_word(tokens[k][1], w):
            return None
        k += 1
    if k < len(tokens) and tokens[k][0] == "word" and tokens[k][1][0].isupper():
        return None
    return k


def _number(token) -> tuple[int | None, bool]:
    """(value, spelled out) of a number token, or (None, False)."""
    kind, value = token[0], token[1]
    if kind == "int":
        return int(value), False
    if kind == "word" and value.lower() in NUMBER_WORDS:
        return NUMBER_WORDS[value.lower()], True
    return None, False


def _quantity(text: str, tokens, i: int) -> bool:
    """Can the number at tokens[i] be a quantity? Never inside parentheses ("Lesser Heal (Rank 2)"),
    after Rank or Level, with a leading zero, or as part of a hyphenated or alphanumeric designation
    ("A-Me 01", "X-7")."""
    kind, value, start, end = tokens[i]
    before = text[:start]
    if before.count("(") > before.count(")"):
        return False
    if i and tokens[i - 1][0] == "word" and tokens[i - 1][1].lower() in ("rank", "level", "lvl"):
        return False
    if kind == "int" and len(value) > 1 and value.startswith("0"):
        return False
    if (start and (text[start - 1].isalnum() or text[start - 1] == "-")) or (end < len(text) and text[end] == "-"):
        return False
    return re.search(r"\w-\w+\s*$", before) is None


# ---------------------------------------------------------------- the count rule

def count_in_text(text: str | None, aliases, exclude=()) -> int | None:
    """The count of an objective named by any of ``aliases`` in ``text``, or None (see the module
    docstring). exclude: the other names of the quest's objectives (a number inside any of them is
    never a count)."""
    tokens = _tokens(text or "")
    if not tokens:
        return None
    own = [w for w in (_name_words(a) for a in aliases or () if a) if w]
    inside, other = set(), set()
    for words, where in [(w, inside) for w in own] + [(w, other) for w in (_name_words(a) for a in exclude or ()
                                                                            if a) if w]:
        for j in range(len(tokens)):
            stop = _match_end(tokens, j, words)
            if stop is not None:
                where.update(range(j, stop))
    numbers = [(i, *_number(t)) for i, t in enumerate(tokens)
               if i not in inside and i not in other and _quantity(text, tokens, i)]
    numbers = [(i, value, spelled) for i, value, spelled in numbers if value]
    near = set()
    for i, value, _spelled in numbers:
        for j in range(i + 1, min(i + 2 + GAP_WORDS, len(tokens))):
            if any(_match_end(tokens, j, words) is not None for words in own):
                near.add(value)
                break
            kind, word = tokens[j][0], tokens[j][1]
            if kind != "word" or not word[0].islower():
                break          # a number, a sentence end or another (capitalised) name in between
    return near.pop() if len(near) == 1 else None


# ---------------------------------------------------------------- objectives

def rows_from_ids(z: dict) -> list[dict]:
    """Objective rows from a Questie quest that only lists ids (objective_creature_ids, _object_ids,
    _item_ids; no texts): the same shape as QuestieDBData quest "objectives"."""
    out = []
    for group, key in ((1, "objective_creature_ids"), (2, "objective_object_ids"), (3, "objective_item_ids")):
        out += [{"group": group, "id": i, "text": None} for i in (z or {}).get(key) or []]
    return out


def _sources(item: dict, names: Names, point_names: set, maps) -> tuple[list[str], str | None, bool]:
    """(from, from_kind, from_more) of an item: its NPC sources, else its object sources; names that
    are points of the quest first, then those spawning on the quest's maps, then by id; distinct."""
    for kind, ids, table, spawns in (("npc", item.get("npc_drops"), names.npcs, names.npc_spawns),
                                     ("object", item.get("object_drops"), names.objects, names.object_spawns)):
        rows = [(i, table[i]) for i in sorted(set(ids or ())) if table.get(i)]
        if not rows:
            continue

        def rank(row):
            ident, name = row
            here = any(s.get("map_id") in maps for s in spawns.get(ident) or ())
            return (_norm(name) not in point_names, not here, ident)
        ordered = list(dict.fromkeys(name for _i, name in sorted(rows, key=rank)))
        return ordered[:FROM_LIMIT], kind, len(ordered) > FROM_LIMIT
    return [], None, False


def _entry(kind, ident, name, aliases, sources=()) -> dict:
    return {"kind": kind, "id": ident, "name": name, "aliases": [a for a in aliases if a],
            "sources": {_norm(s) for s in sources if s}}


def _all_source_names(item: dict, names: Names) -> list[str]:
    return ([names.npcs.get(i) for i in item.get("npc_drops") or ()]
            + [names.objects.get(i) for i in item.get("object_drops") or ()])


def _real(name):
    """A name, or None for a placeholder (``_PLACEHOLDER_RE``) or no name."""
    return name if name and not _PLACEHOLDER_RE.search(name) else None


def _from_questiedb(rows, names: Names) -> list[dict]:
    out = []
    for row in rows:
        group, ident, text = row.get("group"), row.get("id"), row.get("text")
        if group in NAMELESS_GROUPS or group not in GROUP_KIND:
            continue
        if group == 3:
            item = names.items.get(ident) or {}
            entity = _real(item.get("name"))
            out.append(_entry("item", ident, text or entity, [text, entity], _all_source_names(item, names)))
        elif group == 2:
            entity = _real(names.objects.get(ident))
            out.append(_entry("object", ident, text or entity, [text, entity]))
        else:
            raw = names.npcs.get(ident)
            entity = _real(raw)
            dummy = entity is None and raw is not None      # a kill-credit placeholder: still its points' name
            credit = [names.npcs.get(i) for i in row.get("ids") or () if i != ident]
            kind = "other" if (group == 1 and text) or dummy else "npc"
            out.append(_entry(kind, ident, text or entity, [text, raw, *credit]))
    return out


def _from_points(points, names: Names) -> list[dict]:
    out, seen = [], set()
    for p in points:
        name = p.get("name")
        if not name or _norm(name) in seen:
            continue
        seen.add(_norm(name))
        for kind in ("item", "npc", "object"):
            ids = names.by_name(kind).get(_norm(name))
            if ids:
                ident = ids[0] if len(ids) == 1 else None
                item = (names.items.get(ident) or {}) if kind == "item" else {}
                out.append(_entry(kind, ident, name, [name], _all_source_names(item, names)))
                break
        else:
            out.append(_entry("other", None, name, [name]))
    return out


def _index(point_name, entries) -> int | None:
    if not point_name:
        return None
    n = _norm(point_name)
    direct = [i for i, e in enumerate(entries, 1) if n in {_norm(a) for a in e["aliases"]}]
    if direct:
        return direct[0] if len(direct) == 1 else None
    dropped = [i for i, e in enumerate(entries, 1) if n in e["sources"]]
    return dropped[0] if len(dropped) == 1 else None


def build_objectives(rows, points, text: str | None, names: Names, maps=()) -> tuple[list[dict], list]:
    """(objectives, point indices) for one quest.

    rows: QuestieDB objective rows (QuestieDBData quest "objectives", or ``rows_from_ids``); points:
    outof.games objective points ({map_id, x, y, name}); text: the objective text (Contract A field
    14); maps: the quest's uiMapIDs (giver, turn-in, points), to name an item's local sources first.
    The indices are 1-based into the objectives, one per point, None when unmatched.
    """
    rows, points, maps = list(rows or ()), list(points or ()), set(maps or ())
    unique = {}                    # a row QuestieDB lists twice is one objective
    for row in rows:
        unique.setdefault((row.get("group"), row.get("id"), row.get("text")), row)
    rows = list(unique.values())
    entries = _from_questiedb(rows, names) if rows else _from_points(points, names)
    point_names = {_norm(p["name"]) for p in points if p.get("name")}
    objectives = []
    for e in entries:
        others = [a for o in entries if o is not e for a in o["aliases"]]
        item = names.items.get(e["id"]) if e["kind"] == "item" and e["id"] is not None else None
        sources, from_kind, more = _sources(item, names, point_names, maps) if item else ([], None, False)
        objectives.append({"kind": e["kind"], "id": e["id"], "name": e["name"],
                           "count": count_in_text(text, e["aliases"], exclude=others),
                           "from": sources or None, "from_kind": from_kind, "from_more": more})
    return objectives, [_index(p.get("name"), entries) for p in points]
