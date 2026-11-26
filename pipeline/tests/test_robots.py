from pipeline.robots import RobotsRules

RULES = """User-agent: *
Disallow: /realms/forever/quests/?page=*&
Allow: /realms/forever/quests/?page=
Disallow: /realms/forever/quests/?
Disallow: /api/v2/forever/
User-agent: MJ12bot
Disallow: /
"""


def test_plain_page_allowed():
    r = RobotsRules.parse(RULES)
    assert r.allowed("/realms/forever/quests/?page=2")
    assert r.allowed("/realms/forever/quest/4763-the-blackwood-corrupted/")


def test_filters_and_api_disallowed():
    r = RobotsRules.parse(RULES)
    assert not r.allowed("/realms/forever/quests/?page=2&sort=xp")
    assert not r.allowed("/realms/forever/quests/?faction=alliance")
    assert not r.allowed("/api/v2/forever/quests")


def test_other_agent_block_ignored():
    assert RobotsRules.parse(RULES).allowed("/realms/forever/npc/3649-thundris-windweaver/")


def test_named_agent_group_used():
    assert not RobotsRules.parse(RULES, agent="MJ12bot").allowed("/anything")


def test_allow_wins_tie_and_empty_disallow():
    r = RobotsRules.parse("User-agent: *\nDisallow: /a\nAllow: /a\n")
    assert r.allowed("/a")
    assert RobotsRules.parse("User-agent: *\nDisallow:\n").allowed("/x")


def test_wildcard_and_end_anchor():
    r = RobotsRules.parse("User-agent: *\nDisallow: /*.json$\n")
    assert not r.allowed("/a/b.json")
    assert r.allowed("/a/b.json?x=1")


def test_bom_stripped_and_no_crawl_delay():
    r = RobotsRules.parse("\ufeffUser-agent: *\nDisallow: /x\n")
    assert not r.allowed("/x") and r.crawl_delay is None


def test_group_selected_by_case_insensitive_prefix_of_our_token():
    text = "User-agent: levelingadvisor\nDisallow: /x\n\nUser-agent: *\nDisallow: /y\n"
    r = RobotsRules.parse(text, agent="LevelingAdvisorDataBuilder")
    assert not r.allowed("/x") and r.allowed("/y")
    # a group whose name merely appears inside our token (not as a prefix) is ignored
    text2 = "User-agent: DataBuilder\nDisallow: /x\n\nUser-agent: *\nDisallow: /y\n"
    r2 = RobotsRules.parse(text2, agent="LevelingAdvisorDataBuilder")
    assert r2.allowed("/x") and not r2.allowed("/y")


def test_crawl_delay_capped_and_non_finite_ignored():
    assert RobotsRules.parse("User-agent: *\nCrawl-delay: 5\n").crawl_delay == 5
    assert RobotsRules.parse("User-agent: *\nCrawl-delay: 100000\n").crawl_delay == 60
    for bad in ("inf", "nan", "-inf", "-3"):
        assert RobotsRules.parse(f"User-agent: *\nCrawl-delay: {bad}\n").crawl_delay is None
