from pipeline.zone_faction import choose_faction, faction_split


def _q(map_id, faction):
    return {"faction": faction, "giver": {"map_id": map_id}}


def test_zone_faction_evidence():
    quests = {i: _q(1, "Horde") for i in range(10)}
    quests.update({100 + i: _q(1, "Alliance") for i in range(2)})
    quests.update({200 + i: _q(1, "Both") for i in range(50)})      # "both" quests are ignored
    quests.update({300 + i: _q(2, "Both") for i in range(5)})
    split = faction_split(quests)
    assert split[1] == {"Alliance": 2, "Horde": 10}
    assert split[2] == {"Alliance": 0, "Horde": 0}
    assert choose_faction(split[1]) == "Horde"          # 10 of 12 = 83%
    assert choose_faction(split[2]) == "Contested"


def test_faction_thresholds():
    assert choose_faction({"Alliance": 8, "Horde": 2}) == "Alliance"      # exactly 80%
    assert choose_faction({"Alliance": 7, "Horde": 2}) == "Contested"      # fewer than 8 quests
    assert choose_faction({"Alliance": 79, "Horde": 21}) == "Contested"    # under 80%
    assert choose_faction({"Alliance": 0, "Horde": 8}) == "Horde"
    assert choose_faction(None) == "Contested"


def test_capital_takes_its_faction_regardless_of_split():
    assert choose_faction({"Alliance": 0, "Horde": 0}, capital="Horde") == "Horde"
    assert choose_faction({"Alliance": 50, "Horde": 0}, capital="Horde") == "Horde"
