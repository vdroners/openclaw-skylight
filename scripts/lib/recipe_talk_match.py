#!/usr/bin/env python3
"""Recipe / bread machine Talk fast-path detection."""

from __future__ import annotations

import re

from forge_talk_match import extract_user_message, normalize_talk_text


def is_recipe_command(text: str, agent_name: str = "alfred") -> bool:
    norm = normalize_talk_text(extract_user_message(text))
    if not norm:
        return False
    agent = re.escape(agent_name.lstrip("@"))
    return bool(
        re.search(rf"(?i)@?{agent}\s+recipe\b", norm)
        or re.search(rf"(?i)@?{agent}\s+bread\b", norm)
    )


def parse_recipe_command(text: str, agent_name: str = "alfred") -> tuple[str, str]:
    """Return (kind, remainder) where kind is recipe|bread."""
    norm = normalize_talk_text(extract_user_message(text))
    agent = re.escape(agent_name.lstrip("@"))
    m = re.search(rf"(?i)@?{agent}\s+(recipe|bread)\s+(.*)$", norm)
    if not m:
        return "", ""
    return m.group(1).lower(), m.group(2).strip()
