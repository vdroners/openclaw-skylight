#!/usr/bin/env python3
"""Chore Talk fast-path detection (@alfred chores / @alfred done …)."""

from __future__ import annotations

import re

from forge_talk_match import extract_user_message, normalize_talk_text


def is_chore_command(text: str, agent_name: str = "alfred") -> bool:
    norm = normalize_talk_text(extract_user_message(text))
    if not norm:
        return False
    agent = re.escape(agent_name.lstrip("@"))
    return bool(
        re.search(rf"(?i)@?{agent}\s+chores?\b", norm)
        or re.search(rf"(?i)@?{agent}\s+(?:done|complete|finish(?:ed)?)\b", norm)
    )


def parse_chore_command(text: str, agent_name: str = "alfred") -> tuple[str, str]:
    """Return (action, remainder) where action is list|done."""
    norm = normalize_talk_text(extract_user_message(text))
    agent = re.escape(agent_name.lstrip("@"))
    m = re.search(rf"(?i)@?{agent}\s+chores?\b(?:\s+(.*))?$", norm)
    if m:
        rem = (m.group(1) or "").strip().lower()
        if rem in ("", "today", "list", "open"):
            return "list", ""
        return "list", rem
    m = re.search(
        rf"(?i)@?{agent}\s+(?:done|complete|finish(?:ed)?)\s+(.+)$",
        norm,
    )
    if m:
        return "done", m.group(1).strip()
    return "", ""


def is_meal_plan_command(text: str, agent_name: str = "alfred") -> bool:
    """@alfred meal plan [propose|new] — trigger weekly propose."""
    norm = normalize_talk_text(extract_user_message(text))
    if not norm:
        return False
    agent = re.escape(agent_name.lstrip("@"))
    return bool(re.search(rf"(?i)@?{agent}\s+meal[\s-]?plan\b", norm))
