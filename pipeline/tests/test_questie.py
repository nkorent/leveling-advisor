"""Shared Questie-format helpers (pipeline/questie.py) that the QuestieDB loader reuses.

The Classic Era loader and its tests were removed in Task 8c fix round 1; the loader-level behaviour
is covered by test_questiedb.py."""
from pathlib import Path

import lupa
import pytest

from pipeline.questie import (_eval_table, _extract_data_string, _fix_fields, _flat_ids, _friendly, _read_keys,
                              _union_conflict)

QDB_QUESTS = Path(__file__).parent / "fixtures" / "questiedb" / "root" / "data" / "Forever" / "foreverQuestDB.lua"


def test_reads_keys_from_source():
    keys = _read_keys(QDB_QUESTS, "questKeys")
    assert keys["name"] == 1 and keys["preQuestGroup"] == 12 and keys["breadcrumbForQuestId"] == 27
    assert len(keys) == 36                       # commented sub-keys (creatureStart, ...) are not keys


def test_data_cannot_reach_globals():
    with pytest.raises(lupa.LuaError):
        _eval_table('return {[1] = {os.getenv("HOME")}}')


def test_missing_data_string_raises(tmp_path):
    empty = tmp_path / "e.lua"
    empty.write_text("-- nothing")
    with pytest.raises(ValueError):
        _extract_data_string(empty, "questData")


def test_false_is_not_an_id():
    assert _flat_ids([False, 5]) == ([5], False)


def test_fix_fields_maps_questie_fields():
    assert _fix_fields("preQuestSingle", [4762, None, 4761]) == ({"pre_any": [4762, 4761]}, False)
    assert _fix_fields("startedBy", [[1, 2], None, [9]]) == (
        {"starter_npcs": [1, 2], "starter_objects": None, "starter_items": [9]}, False)
    assert _fix_fields("specialFlags", 1) == ({"repeatable": True}, False)
    assert _fix_fields("zoneOrSort", 12) == (None, False)          # not an output field


def test_union_conflict_per_sub_list():
    assert _union_conflict("startedBy", [[31]], [[30], [5]]) == [[30, 31], [5]]
    assert _union_conflict("preQuestSingle", [1], [2]) is None


@pytest.mark.parametrize("value,expected", [("A", "A"), ("H", "H"), ("AH", "AH"), ("HA", "AH"), ("", None),
                                            (None, None)])
def test_friendly_normalised(value, expected):
    assert _friendly(value) == expected
