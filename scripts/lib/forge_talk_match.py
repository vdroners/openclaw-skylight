#!/usr/bin/env python3
"""Forge / 3D print Talk fast-path detection."""

from __future__ import annotations

import json
import re

MENTION_CHIP_RE = re.compile(r"\{mention-user\d+\}", re.IGNORECASE)


def normalize_talk_text(text: str) -> str:
    cleaned = MENTION_CHIP_RE.sub(" ", text or "")
    return re.sub(r"\s+", " ", cleaned).strip()


def extract_user_message(text: str) -> str:
    raw = (text or "").strip()
    if raw.startswith("{") and '"message"' in raw:
        try:
            obj = json.loads(raw)
            if isinstance(obj, dict):
                msg = obj.get("message")
                if isinstance(msg, str) and msg.strip():
                    return normalize_talk_text(msg)
        except json.JSONDecodeError:
            pass
    return normalize_talk_text(raw)


def is_tool_json_payload(text: str) -> bool:
    raw = (text or "").strip()
    if not raw.startswith("{"):
        return False
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        return False
    if not isinstance(obj, dict):
        return False
    msg = obj.get("message")
    params = obj.get("parameters")
    if isinstance(msg, str) and params == []:
        return False
    return "parameters" in obj


def is_forge_command(text: str, agent_name: str = "alfred") -> bool:
    norm = extract_user_message(text)
    if not norm:
        return False
    agent = re.escape(agent_name.lstrip("@"))
    patterns = [
        rf"(?i)@?{agent}\s+print\b",
        rf"(?i)@?{agent}\s+forge\b",
        rf"(?i)@?{agent}\s+k1\b",
        rf"(?i)@?{agent}\s+k1-max\b",
    ]
    return any(re.search(p, norm) for p in patterns)


def parse_forge_subcommand(text: str, agent_name: str = "alfred") -> str:
    norm = extract_user_message(text)
    agent = re.escape(agent_name.lstrip("@"))
    norm = re.sub(rf"(?i)@?{agent}\s+(print|forge|k1|k1-max)\s*", "", norm, count=1).strip()
    if not norm or norm.lower() in ("help", "?"):
        return "help"
    first = norm.split()[0].lower()
    if first in ("status", "queue", "slicer", "camera", "help"):
        return first
    if "status" in norm.lower():
        return "status"
    if "queue" in norm.lower():
        return "queue"
    if "slicer" in norm.lower():
        return "slicer"
    return "status"
