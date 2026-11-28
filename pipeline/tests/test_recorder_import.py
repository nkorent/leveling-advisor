"""Recorder export importer (Task 8 + rulings): decoding, storage, source-independent agreement."""
import base64
import json
import zlib
from pathlib import Path

import pytest

from pipeline import recorder_import
from pipeline.__main__ import main
from pipeline.build import build
from pipeline.recorder_import import (agreed, aggregate_recorder, decode_export, import_exports,
                                      load_recorder)
from pipeline.tests.test_build import load_data, provisional_oog

FIXTURE = Path(__file__).parent / "fixtures" / "recorder" / "export_la1j.txt"


def payload(qid=4763, at=1764000000, xp=1700, level=18, qlevel=18, npc=3649, map_id=1439,
            x=37.4, y=40.1, **extra):
    detail = {"at": at, "choices": [1, 2], "level": level, "mapID": map_id, "npcID": npc,
              "rewards": {}, "seen": 1, "x": x, "y": y, "xp": xp}
    detail.update(extra)
    return {"v": 1, "addon": "0.1.0", "gameData": "1.60.1", "built": "2026-11-25",
            "recorder": {"accepted": [], "details": {str(qid): detail},
                         "levels": {str(qid): qlevel}, "xp": {str(qid): {str(level): xp}}}}


def la1j(p):
    return "LA1J:" + base64.b64encode(json.dumps(p).encode()).decode()


def la1z(p, wbits=15):
    c = zlib.compressobj(wbits=wbits)
    data = c.compress(json.dumps(p).encode()) + c.flush()
    return "LA1Z:" + base64.b64encode(data).decode()


def store(tmp_path, *payloads):
    d = tmp_path / "rec"
    import_exports([la1j(p) for p in payloads], d)
    return d


# ---------------------------------------------------------------- decoding

def test_decode_lua_fixture():
    d = decode_export(FIXTURE.read_text())
    assert d["v"] == 1
    rec = d["recorder"]
    assert rec["xp"] == {4763: {18: 1700}}
    assert rec["levels"] == {4763: 18}
    assert rec["details"][4763]["npcID"] == 3649 and rec["details"][4763]["x"] == 37.4
    assert rec["accepted"] == [[4763, 1764000000]]


def test_decode_zlib():
    p = payload()
    assert decode_export("  " + la1z(p) + "\n")["recorder"]["levels"] == {4763: 18}


def test_decode_raw_deflate():
    assert decode_export(la1z(payload(), wbits=-15))["recorder"]["xp"] == {4763: {18: 1700}}


def test_rejects_unknown_prefix_and_version():
    with pytest.raises(ValueError, match="prefix"):
        decode_export("LA2J:" + la1j(payload())[5:])
    with pytest.raises(ValueError, match="prefix"):
        decode_export("nonsense")
    for bad in (dict(payload(), v=2), dict(payload(), v="1"), dict(payload(), v=True),
                {k: v for k, v in payload().items() if k != "recorder"}, dict(payload(), recorder=[])):
        with pytest.raises(ValueError):
            decode_export(la1j(bad))


@pytest.mark.parametrize("text", ["LA1J:!!!not-base64", "LA1J:" + base64.b64encode(b"[1]").decode(),
                                  "LA1J:" + base64.b64encode(b"{oops").decode(),
                                  "LA1Z:" + base64.b64encode(b"not zlib").decode()])
def test_rejects_garbage(text):
    with pytest.raises(ValueError):
        decode_export(text)


def test_rejects_oversize_and_bomb():
    with pytest.raises(ValueError, match="longer"):
        decode_export("LA1J:" + "A" * 2_000_001)
    bomb = base64.b64encode(zlib.compress(b" " * (11 * 1024 * 1024))).decode()
    assert len(bomb) < 2_000_000
    with pytest.raises(ValueError, match="decompresses"):
        decode_export("LA1Z:" + bomb)


# ---------------------------------------------------------------- storage

def test_import_dedupes(tmp_path):
    out, stats = tmp_path / "rec", {}
    a, b = la1j(payload()), la1z(payload(qid=2))
    written = import_exports([a, b, a, "garbage"], out, stats)
    assert len(written) == 2 and all(p.parent == out and p.suffix == ".json" for p in written)
    assert stats == {"imported": 2, "duplicate": 1, "rejected": 1}
    assert import_exports([a, b], out, stats) == [] and stats["duplicate"] == 2
    assert sorted(p.name for p in out.iterdir()) == sorted(p.name for p in written)


def test_cli_import_recorder(tmp_path, capsys):
    src = tmp_path / "exports.txt"
    src.write_text(la1j(payload()) + "\n\n" + la1j(payload()) + "\nbad\n", encoding="utf-8")
    assert main(["import-recorder", str(src), "--out", str(tmp_path / "rec")]) == 0
    assert "1 imported, 1 duplicate, 1 rejected" in capsys.readouterr().out
    assert len(list((tmp_path / "rec").glob("*.json"))) == 1
    assert main(["import-recorder", str(tmp_path / "missing.txt"), "--out", str(tmp_path / "x")]) == 2


# ---------------------------------------------------------------- agreement

def test_agreed_needs_two():
    assert agreed([1700]) is None
    assert agreed([1700, 1700, 1650]) == 1700
    assert agreed([]) is None
    assert agreed([1, 1, 2, 2]) is None            # ambiguous tie


def test_same_account_exports_count_once(tmp_path):
    d = store(tmp_path, payload(), payload(extra_unused=1) | {"addon": "0.1.1"})
    assert len(list(d.glob("*.json"))) == 2         # two distinct export strings
    agg = aggregate_recorder(d)
    assert agg[4763]["reports"] == 1 and agg[4763]["xp"] == {18: [1700]}
    assert load_recorder(d) == {}


def test_two_sources_agree(tmp_path):
    d = store(tmp_path, payload(at=1000), payload(at=2000, x=38.0, y=40.5))
    agg = aggregate_recorder(d)
    assert agg[4763]["reports"] == 2 and agg[4763]["xp"] == {18: [1700, 1700]}
    assert agg[4763]["level"] == [18, 18] and agg[4763]["choices"] == [[1, 2], [1, 2]]
    assert agg[4763]["rewards"] == [[], []]
    assert load_recorder(d) == {4763: {"xp": {18: 1700}, "level": 18,
                                       "giver": {"npc": 3649, "map_id": 1439, "x": 37.7, "y": 40.3}}}


def test_latest_snapshot_of_a_source_wins(tmp_path):
    older = payload(at=1000, xp=1600)
    newer = payload(at=1000, xp=1600)
    newer["recorder"]["details"]["4763"]["xp"] = 1700       # same observation, edited later
    newer["recorder"]["details"]["5000"] = {"at": 3000, "level": 20}
    newer["recorder"]["xp"]["4763"]["18"] = 1700
    d = store(tmp_path, older, newer)
    assert aggregate_recorder(d)[4763]["xp"] == {18: [1700]}


def test_xp_agrees_per_player_level(tmp_path):
    d = store(tmp_path, payload(at=1, level=18, xp=1700), payload(at=2, level=18, xp=1700),
              payload(at=3, level=19, xp=1600))
    assert load_recorder(d)[4763]["xp"] == {18: 1700}


def test_disagreeing_level_not_agreed(tmp_path):
    d = store(tmp_path, payload(at=1, qlevel=18), payload(at=2, qlevel=19))
    assert load_recorder(d)[4763]["level"] is None


def test_giver_agreed_mean(tmp_path):
    d = store(tmp_path, payload(at=1, x=30.0, y=30.0), payload(at=2, x=33.0, y=34.0),
              payload(at=3, x=31.5, y=32.0))
    assert load_recorder(d)[4763]["giver"] == {"npc": 3649, "map_id": 1439, "x": 31.5, "y": 32.0}
    assert recorder_import.last_conflicts == []


def test_giver_far_apart_not_agreed(tmp_path):
    d = store(tmp_path, payload(at=1, x=30.0, y=30.0), payload(at=2, x=41.0, y=30.0))
    got = load_recorder(d)[4763]
    assert got["giver"] is None and got["level"] == 18        # level/xp still agree
    assert [c["quest"] for c in recorder_import.last_conflicts] == [4763]


def test_giver_different_npcs_not_agreed(tmp_path):
    d = store(tmp_path, payload(at=1, npc=1), payload(at=2, npc=2))
    assert load_recorder(d)[4763]["giver"] is None


# ---------------------------------------------------------------- hostile input

def test_empty_object_as_list(tmp_path):
    p = payload()
    p["recorder"]["details"]["4763"]["rewards"] = {}
    p["recorder"]["details"]["4763"]["choices"] = {}
    agg = aggregate_recorder(store(tmp_path, p))
    assert agg[4763]["rewards"] == [[]] and agg[4763]["choices"] == [[]]


def test_bad_types_skipped(tmp_path):
    p = payload()
    rec = p["recorder"]
    rec["xp"].update({"-5": {"18": 100}, "abc": {"18": 100}, "7": {"18": "lots", "99": 5, "x": 5},
                      "8": ["a"], "9": {"18": True}})
    rec["levels"].update({"6": "high", "10": 0, "11": 71, "12": True, "-1": 18})
    rec["details"].update({"13": "nope", "14": {"at": "soon", "npcID": 1, "mapID": 1, "x": 1, "y": 1},
                           "15": {"at": 5, "npcID": "1", "mapID": 1, "x": 1, "y": 1},
                           "16": {"at": 6, "npcID": 1, "mapID": 1, "x": 101, "y": 1},
                           "17": {"at": 7, "npcID": 1, "mapID": 1, "x": float("nan"), "y": 1},
                           "18": {"at": 8, "npcID": 1, "mapID": 1, "x": 1, "y": 1,
                                  "choices": "x", "rewards": [1, "a", None, True, -2, 3]}})
    rec["accepted"] = "junk"
    rec["xp"]["20"] = None
    d = tmp_path / "rec"
    d.mkdir()
    (d / "a.json").write_text(json.dumps(p, allow_nan=True), encoding="utf-8")
    (d / "b.json").write_text("{not json", encoding="utf-8")
    (d / "c.json").write_text(json.dumps({"v": 1, "recorder": 5}), encoding="utf-8")
    agg = aggregate_recorder(d)
    # malformed xp / levels / detail entries are skipped; details with a valid `at` but an unusable
    # giver are still observations (reports=1) that contribute nothing agreeable
    assert set(agg) == {4763, 15, 16, 17, 18}
    assert all(agg[q]["giver"] == [] for q in (15, 16, 17))
    assert agg[18]["rewards"] == [[1, 3]] and agg[18]["choices"] == [[]]
    assert agg[4763]["xp"] == {18: [1700]}
    assert load_recorder(tmp_path / "missing") == {} and load_recorder(tmp_path) == {}


def test_digit_keys_become_ints_recursively():
    d = decode_export(la1j({"v": 1, "recorder": {"xp": {"1": {"2": 3}}, "n": {"a": {"07": 1}}}}))
    assert d["recorder"]["xp"] == {1: {2: 3}} and d["recorder"]["n"] == {"a": {7: 1}}


# ---------------------------------------------------------------- build integration

def test_build_uses_recorder(tmp_path):
    d = store(tmp_path, payload(qid=1, at=1, qlevel=14), payload(qid=1, at=2, qlevel=14))
    recorder = load_recorder(d)
    assert recorder[1]["level"] == 14
    build(provisional_oog(), {}, {}, {}, tmp_path / "Data", tmp_path / "report.json",
          provisional=True, built="2026-11-25", recorder=recorder)
    data = load_data(tmp_path / "Data")
    assert data.quests[1][6] == 14 and data.quests[1][7] == 3       # quest_level, source 3 = recorder
    assert data.quests[2][7] != 3                                   # untouched quest keeps its source


# ---------------------------------------------------------------- fix round 1

def test_accepted_entries_link_sources_despite_reviewed_details(tmp_path):
    """Details `at` is rewritten on every view; the append-only accepted log still ties exports together."""
    a = payload(at=1000, level=18, xp=1700, qlevel=18)
    a["recorder"]["accepted"] = [[4763, 1000]]
    b = payload(at=2000, level=19, xp=1800, qlevel=18)
    b["recorder"]["accepted"] = [[4763, 1000], [4763, 2000]]
    b["recorder"]["xp"]["4763"]["18"] = 1700            # carried over from A's cumulative table
    d = store(tmp_path, a, b)
    assert aggregate_recorder(d)[4763]["reports"] == 1
    assert load_recorder(d) == {}


def test_accepted_object_shape_links_too(tmp_path):
    a, b = payload(at=1000), payload(at=2000)
    for p in (a, b):
        p["recorder"]["accepted"] = [{"questID": 4763, "at": 500}]
    assert aggregate_recorder(store(tmp_path, a, b))[4763]["reports"] == 1


def test_giver_outlier_not_agreed_and_logged(tmp_path):
    d = store(tmp_path, payload(at=1, x=30.0, y=30.0), payload(at=2, x=30.0, y=30.0),
              payload(at=3, x=45.0, y=30.0))
    assert load_recorder(d)[4763]["giver"] is None
    assert [c["quest"] for c in recorder_import.last_conflicts] == [4763]


def test_giver_radius_boundary_is_inclusive(tmp_path):
    d = store(tmp_path, payload(at=1, x=30.0, y=30.0), payload(at=2, x=40.0, y=30.0))
    assert load_recorder(d)[4763]["giver"] == {"npc": 3649, "map_id": 1439, "x": 35.0, "y": 30.0}
    assert recorder_import.last_conflicts == []


def test_giver_conflict_logged_when_distinct_keys_and_none_agreed(tmp_path):
    load_recorder(store(tmp_path, payload(at=1, npc=1), payload(at=2, npc=2)))
    assert [c["quest"] for c in recorder_import.last_conflicts] == [4763]


def test_levels_only_quest_in_same_account_counts_once(tmp_path):
    a, b = payload(at=1000), payload(at=1000)
    b["addon"] = "other"
    for p in (a, b):
        p["recorder"]["levels"]["9999"] = 20           # no details for this quest
    d = store(tmp_path, a, b)
    assert aggregate_recorder(d)[9999]["reports"] == 1
    assert 9999 not in load_recorder(d)


def test_xp_table_as_array_means_levels_one_to_n(tmp_path):
    p = {"v": 1, "recorder": {"xp": {"5": [0, 40, 50]}}}
    q = {"v": 1, "recorder": {"xp": {"5": [0, 40, 60]}, "levels": {"5": 3}}}
    d = store(tmp_path, p, q)
    assert aggregate_recorder(d)[5]["xp"] == {2: [40, 40], 3: [50, 60]}
    assert load_recorder(d)[5]["xp"] == {2: 40}


def test_identical_recorder_tables_are_one_source(tmp_path):
    p = {"v": 1, "recorder": {"levels": {"7": 20}, "xp": {}}}
    d = tmp_path / "rec"
    import_exports([la1j(p), la1z(dict(p, addon="x"))], d)
    assert len(list(d.glob("*.json"))) == 2
    assert aggregate_recorder(d)[7]["reports"] == 1 and load_recorder(d) == {}


def test_id_and_xp_ranges(tmp_path):
    big = 2**31
    p = {"v": 1, "recorder": {"xp": {str(big): {"5": 10}, "8": {"5": 1_000_001, "6": 1_000_000}},
                              "levels": {str(2**31 - 1): 10},
                              "details": {"9": {"at": 1, "npcID": big, "mapID": 1, "x": 1, "y": 1,
                                                "choices": [big, 5, 0]}}}}
    agg = aggregate_recorder(store(tmp_path, p))
    assert set(agg) == {8, 2**31 - 1, 9}
    assert agg[8]["xp"] == {6: [1_000_000]} and agg[9]["giver"] == [] and agg[9]["choices"] == [[5]]


def run_build(tmp_path, recorder_dir):
    from pipeline.tests.test_build import cli_paths, write_oog
    from pipeline.tests.test_merge import oq
    write_oog(tmp_path / "oog", [oq(1, quest_level=12), oq(2, quest_level=14)])
    rc = main(["build", "--provisional", "--without", "questie", "--recorder", str(recorder_dir),
               *cli_paths(tmp_path)])
    assert rc == 0
    return json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))


def test_cli_build_with_recorder_dir(tmp_path):
    d = store(tmp_path, payload(qid=1, at=1, qlevel=14), payload(qid=1, at=2, qlevel=14))
    report = run_build(tmp_path, d)
    assert not any("recorder" in n for n in report["notes"])
    data = load_data(tmp_path / "Data")
    assert data.quests[1][6] == 14 and data.quests[1][7] == 3


@pytest.mark.parametrize("make", [lambda t: t / "missing", lambda t: store(t, payload())])
def test_cli_build_notes_recorder_without_agreed_data(tmp_path, make):
    report = run_build(tmp_path, make(tmp_path))
    assert any("recorder" in n and "no agreed" in n for n in report["notes"])


def test_unreadable_payload_files_are_listed(tmp_path):
    d = store(tmp_path, payload(at=1), payload(at=2))
    (d / "0000bad.json").write_text("{not json", encoding="utf-8")
    (d / "0001bad.json").write_text(json.dumps({"v": 99}), encoding="utf-8")
    assert load_recorder(d)[4763]["level"] == 18
    assert recorder_import.last_skipped == ["0000bad.json", "0001bad.json"]
    load_recorder(store(tmp_path / "clean", payload(at=1), payload(at=2)))
    assert recorder_import.last_skipped == []


def test_cli_build_notes_recorder_conflicts_and_unreadable_files(tmp_path):
    d = store(tmp_path, payload(qid=1, at=1, qlevel=14, x=30.0, y=30.0),
              payload(qid=1, at=2, qlevel=14, x=45.0, y=30.0))
    (d / "0000bad.json").write_text("{not json", encoding="utf-8")
    notes = run_build(tmp_path, d)["notes"]
    assert "recorder: 1 quest(s) without a recorded giver: the recordings disagree" in notes
    assert "recorder: 1 unreadable stored payload(s) skipped: 0000bad.json" in notes
