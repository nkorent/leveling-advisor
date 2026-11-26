"""CLI:
  python -m pipeline crawl [--max N] [--refresh-lists] [--reparse] [--out DIR] [--cache DIR]
  python -m pipeline crawl --dungeons [--refresh-lists] [--out DIR] [--cache DIR]   # dungeon list + pages only
  python -m pipeline dungeon-quests [--oog DIR] [--curated DIR]     # match pages -> dungeons.quests.generated.toml
  python -m pipeline census [--input FILE] [--out FILE]
  python -m pipeline import-recorder <file-or-> [--out DIR]
  python -m pipeline build [--provisional] [--without SOURCE ...] [--recorder DIR] [paths ...]
  python -m pipeline poi [--openmap PATH] [--census FILE] [--curated DIR] [--problems FILE]
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from pipeline.build import run as run_build
from pipeline.census import load_census
from pipeline.crawl import crawl_dungeons, crawl_outofgames
from pipeline.fetch import USER_AGENT, PoliteFetcher
from pipeline.http import make_http_get
from pipeline.merge import REMOVABLE_SOURCES
from pipeline.poi import run as run_poi
from pipeline.recorder_import import cmd_import_recorder
from pipeline.robots import RobotsRules

PRODUCT_TOKEN = "LevelingAdvisorDataBuilder"
ROBOTS_URL = "https://outof.games/robots.txt"


def cmd_crawl(args) -> int:
    cache = Path(args.cache)
    log = lambda m: print(m, flush=True)  # noqa: E731
    if args.reparse and not args.refresh_lists:
        # offline: the cached HTML only, no request at all (not even robots.txt)
        fetcher = PoliteFetcher.offline(cache)
        if args.dungeons:
            result = crawl_dungeons(fetcher, Path(args.out), log=log)
        else:
            result = crawl_outofgames(fetcher, Path(args.out), max_quests=args.max, log=log,
                                      refresh_lists=False, reparse=True)
        print(result, flush=True)
        return _crawl_exit(result, args)
    http_get = make_http_get(timeout=30)
    print(f"GET {ROBOTS_URL}", flush=True)
    robots_started = time.monotonic()   # PoliteFetcher's default clock
    try:
        status, text = http_get(ROBOTS_URL, {"User-Agent": USER_AGENT})
    except Exception as e:  # noqa: BLE001
        print(f"robots.txt request failed: {e}", file=sys.stderr)
        return 2
    if status != 200:
        print(f"robots.txt returned HTTP {status}; refusing to crawl", file=sys.stderr)
        return 2
    robots_path = cache / "outof.games" / "robots.txt"
    robots_path.parent.mkdir(parents=True, exist_ok=True)
    robots_path.write_text(text, encoding="utf-8")
    robots = RobotsRules.parse(text, agent=PRODUCT_TOKEN)

    fetcher = PoliteFetcher(cache, robots, http_get)
    # robots.txt was a request too: the first crawl request waits min_interval after it.
    fetcher._last_start = robots_started
    if args.dungeons:
        result = crawl_dungeons(fetcher, Path(args.out), log=log, refresh_lists=args.refresh_lists)
    else:
        result = crawl_outofgames(fetcher, Path(args.out), max_quests=args.max, log=log,
                                  refresh_lists=args.refresh_lists, reparse=args.reparse)
    print(result, flush=True)
    return _crawl_exit(result, args)


def _crawl_exit(result: dict, args) -> int:
    if result.get("list_failed"):
        what = "dungeon list page" if args.dungeons else "quest list page 1"
        print(f"{what} failed or listed nothing; the crawl is incomplete", file=sys.stderr)
        return 2
    return 0


def cmd_dungeon_quests(args) -> int:
    from pipeline.curated import _read
    from pipeline.dungeon_quests import build_quest_lists, write_quests_toml
    oog, curated = Path(args.oog), Path(args.curated)
    pages = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((oog / "dungeons").glob("*.json"))]
    if not pages:
        print(f"dungeon-quests: no dungeon pages in {oog / 'dungeons'} (run: crawl --dungeons)", file=sys.stderr)
        return 2
    dungeons = _read(curated / "dungeons.generated.toml").get("dungeons") or {}
    known = {int(p.stem) for p in (oog / "quests").glob("*.json") if p.stem.isdigit()}
    lists, report = build_quest_lists(pages, dungeons, known)
    write_quests_toml(lists, curated / "dungeons.quests.generated.toml")
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=1, sort_keys=True), encoding="utf-8")
    print(f"dungeon-quests: {len(pages)} pages, {len(lists)} dungeons with a list, "
          f"{len(report['unmatched_pages'])} unmatched pages, {len(report['zero_quests'])} with 0 quests, "
          f"{len(report['ambiguous_wing'])} ambiguous-wing pages -> {report_path}", flush=True)
    return 0


def cmd_build(args) -> int:
    return run_build(args, log=lambda m: print(m, flush=True))


def cmd_poi(args) -> int:
    return run_poi(args, log=lambda m: print(m, flush=True))


def cmd_census(args) -> int:
    src = Path(args.input)
    if not src.is_file():
        print(f"census: input not found: {src} (run the diagnostic addon in-game, then copy its "
              "LevelingAdvisorDiag.lua SavedVariables file there)", file=sys.stderr)
        return 2
    try:
        census = load_census(src)
    except ValueError as e:
        print(f"census: {e}", file=sys.stderr)
        return 2
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".tmp")
    tmp.write_text(json.dumps(census, indent=1, ensure_ascii=False), encoding="utf-8")
    tmp.replace(out)
    maps = census["maps"].values()
    continents = sum(1 for m in maps if m["mapType"] == 2)
    zones = sum(1 for m in maps if m["mapType"] == 3)
    print(f"census: {len(census['maps'])} maps, {continents} continents, {zones} zones, "
          f"{len(census['here'])} here records -> {out}", flush=True)
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="pipeline")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("crawl", help="crawl outof.games quests and NPCs")
    c.add_argument("--max", type=int, default=None, help="stop after N quests")
    c.add_argument("--dungeons", action="store_true",
                   help="crawl only the dungeon list and dungeon pages (no quests or NPCs)")
    c.add_argument("--refresh-lists", action="store_true",
                   help="request the list pages again (politely) so new quest ids are found; known pages stay cached")
    c.add_argument("--reparse", action="store_true",
                   help="rebuild the parsed JSON from the cached HTML; without --refresh-lists it makes no request")
    c.add_argument("--out", default="data/build/outofgames")
    c.add_argument("--cache", default="data/raw")
    c.set_defaults(func=cmd_crawl)

    dq = sub.add_parser("dungeon-quests", help="dungeon quest lists (data/curated/dungeons.quests.generated.toml) "
                                               "from the crawled dungeon pages")
    dq.add_argument("--oog", default="data/build/outofgames")
    dq.add_argument("--curated", default="data/curated")
    dq.add_argument("--report", default="data/build/dungeon-quests-report.json")
    dq.set_defaults(func=cmd_dungeon_quests)

    n = sub.add_parser("census", help="convert the in-game census SavedVariables into data/census/maps.json")
    n.add_argument("--input", default="data/census/LevelingAdvisorDiag.lua")
    n.add_argument("--out", default="data/census/maps.json")
    n.set_defaults(func=cmd_census)

    r = sub.add_parser("import-recorder", help="store recorder export strings (one per line) in data/recorder/")
    r.add_argument("file", help="file with one export per line, or - for stdin")
    r.add_argument("--out", default="data/recorder")
    r.set_defaults(func=cmd_import_recorder)

    b = sub.add_parser("build", help="build LevelingAdvisor/Data/*.lua and data/build/report.json")
    b.add_argument("--provisional", action="store_true",
                   help="build without the census and curated zones (zones from quest givers, no dungeons)")
    b.add_argument("--without", action="extend", nargs="+", default=[], choices=sorted(REMOVABLE_SOURCES),
                   metavar="SOURCE", help=f"build without a source ({', '.join(sorted(REMOVABLE_SOURCES))})")
    b.add_argument("--recorder", default=None, help="recorder export directory (optional)")
    b.add_argument("--oog", default="data/build/outofgames", help="crawl output directory")
    b.add_argument("--questiedb", default="data/vendor/QuestieDB", help="QuestieDB clone (Forever flavor is read)")
    b.add_argument("--questie-blacklist", default="data/vendor/Questie-master/Database/Corrections/QuestieQuestBlacklist.lua",
                   help="Questie master quest blacklist")
    b.add_argument("--curated", default="data/curated", help="directory with zones.toml and dungeons.toml")
    b.add_argument("--census", default="data/census/maps.json")
    b.add_argument("--levels", default="data/vendor/openmap/Levels.lua",
                   help="OpenMap Levels.lua (zone level ranges for a provisional build)")
    b.add_argument("--out", default="LevelingAdvisor/Data")
    b.add_argument("--report", default="data/build/report.json")
    b.set_defaults(func=cmd_build)

    p = sub.add_parser("poi", help="generate travel links and dungeon references from OpenMap and the census "
                                   "(data/curated/*.generated.toml)")
    p.add_argument("--openmap", default="data/vendor/openmap/Places.lua")
    p.add_argument("--census", default="data/census/maps.json")
    p.add_argument("--curated", default="data/curated",
                   help="zones.toml, openmap_zone_hints.toml and dungeons.toml (its keys are kept); "
                        "where the generated TOML files go")
    p.add_argument("--problems", default="data/build/poi-problems.json")
    p.set_defaults(func=cmd_poi)
    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
