"""robots.txt matcher with Google semantics (wildcards, longest match, Allow wins ties)."""
from __future__ import annotations

import math
import re
from dataclasses import dataclass, field

MAX_CRAWL_DELAY = 60.0


def _compile(rule: str) -> re.Pattern:
    anchored = rule.endswith("$")
    if anchored:
        rule = rule[:-1]
    body = ".*".join(re.escape(part) for part in rule.split("*"))
    return re.compile(body + ("$" if anchored else ""))


@dataclass
class RobotsRules:
    # (pattern length, is_allow, compiled)
    rules: list = field(default_factory=list)
    crawl_delay: float | None = None

    @classmethod
    def parse(cls, text: str, agent: str = "*") -> "RobotsRules":
        text = text.lstrip("\ufeff")
        groups: list[tuple[list[str], list[tuple[str, str]]]] = []
        agents: list[str] = []
        rules: list[tuple[str, str]] = []
        in_rules = False
        for raw in text.splitlines():
            line = raw.split("#", 1)[0].strip()
            if ":" not in line:
                continue
            key, value = (s.strip() for s in line.split(":", 1))
            key = key.lower()
            if key == "user-agent":
                if in_rules:
                    groups.append((agents, rules))
                    agents, rules, in_rules = [], [], False
                agents.append(value.lower())
            elif key in ("allow", "disallow", "crawl-delay"):
                in_rules = True
                rules.append((key, value))
        if agents:
            groups.append((agents, rules))

        name = agent.lower()
        chosen = None
        for g_agents, g_rules in groups:
            if any(a not in ("*", "") and name.startswith(a) for a in g_agents):
                chosen = g_rules
                break
        if chosen is None:
            chosen = [r for g_agents, g_rules in groups if "*" in g_agents for r in g_rules]

        out = []
        delay = None
        for kind, value in chosen:
            if kind == "crawl-delay":
                try:
                    d = float(value)
                except ValueError:
                    continue
                if math.isfinite(d) and d >= 0:
                    delay = min(d, MAX_CRAWL_DELAY)
                continue
            if value == "":  # empty Disallow allows everything; empty Allow is a no-op
                continue
            out.append((len(value), kind == "allow", _compile(value)))
        return cls(out, delay)

    def allowed(self, path_and_query: str) -> bool:
        best_len, best_allow = -1, True
        for length, is_allow, pattern in self.rules:
            if pattern.match(path_and_query):
                if length > best_len or (length == best_len and is_allow):
                    best_len, best_allow = length, is_allow
        return best_allow
