"""Static @alfred help fast-path for Talk (no LLM)."""

from __future__ import annotations

import os
import re
from pathlib import Path


def _agent_name() -> str:
    mention = (os.environ.get("OPENCLAW_AGENT_MENTION") or "@alfred").strip()
    return mention.lstrip("@").lower() or "alfred"


def is_help_command(text: str) -> bool:
    name = _agent_name()
    norm = re.sub(r"\s+", " ", (text or "").strip())
    return bool(re.match(rf"(?i)@?{re.escape(name)}\s+help\b", norm))


def _help_file_for_room(room_token: str, family_hub_room: str) -> Path:
    fam = (family_hub_room or os.environ.get("SKYLIGHT_FAMILY_TALK_ROOM") or "9x4f25n3").strip()
    kind = "family" if room_token == fam else "ops"
    candidates = [
        Path(os.environ.get("OPENCLAW_DIR", os.path.expanduser("~/.openclaw")))
        / "config"
        / f"talk-help-{kind}.txt",
        Path(__file__).resolve().parent.parent.parent / "config" / f"talk-help-{kind}.txt",
    ]
    for path in candidates:
        if path.is_file():
            return path
    return candidates[0]


def load_help_text(room_token: str, family_hub_room: str | None = None) -> str:
    fam = family_hub_room or os.environ.get("SKYLIGHT_FAMILY_TALK_ROOM") or "9x4f25n3"
    path = _help_file_for_room(room_token, fam)
    if path.is_file():
        return path.read_text(encoding="utf-8").strip()
    mention = os.environ.get("OPENCLAW_AGENT_MENTION") or "@alfred"
    if room_token == fam.strip():
        return (
            f"Alfred (Family Hub)\n"
            f"- Ask calendar/chore questions — no {mention} needed\n"
            f"- Proposals: {mention} YES enrich-chore-001 / {mention} NO enrich-chore-001\n"
            f"- Subaru: {mention} subaru status\n"
            f"- Forge: {mention} print status\n"
            f"- Help: {mention} help"
        )
    return (
        f"Alfred (Ops)\n"
        f"- Mention {mention} for fleet/ops questions\n"
        f"- Email proposals: {mention} YES e2e-… / {mention} NO e2e-…\n"
        f"- Subaru: {mention} subaru status\n"
        f"- Forge: {mention} print status\n"
        f"- Help: {mention} help"
    )
