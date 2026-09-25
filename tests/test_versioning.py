# =============================================================================
# Description: TDD tests for pipeline versioning. Verifies deterministic sync
#   commit subjects (py/format_sync_message.py), daily incremental sync tags
#   (py/next_sync_tag.py), and that the push script + CHANGELOG carry the
#   sync(codecommit) subject, sync-v tag and prepended changelog entry.
# Author: pipeline-versioning implementer
# Usage: python3 -m pytest tests/test_versioning.py -q
# Env Vars: none
# Dependencies: pytest, python3 (standard library only)
# =============================================================================
"""Tests for pipeline versioning (deterministic sync commits, tags, changelog)."""

import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BAT = ROOT / "bat" / "PushAndPullRequestToGitHubRemoteRepository.bat"
CHANGELOG = ROOT / "CHANGELOG.md"

sys.path.insert(0, str(ROOT / "py"))

from format_sync_message import format_sync_message  # noqa: E402
from next_sync_tag import next_sync_tag  # noqa: E402

SUBJECT_RE = re.compile(
    r"^sync\(codecommit\): [0-9a-f]{7} \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
)
SHA = "abc1234567890def1234567890abcdef12345678"
TS = "2026-09-25T12:34:56Z"


def test_subject_valid() -> None:
    """A full SHA + UTC timestamp produce a subject matching the contract."""
    subject, body = format_sync_message(SHA, TS, "jenkins-sync-1", "http://x/1/")
    assert SUBJECT_RE.match(subject)
    assert subject == "sync(codecommit): abc1234 2026-09-25T12:34:56Z"
    assert SHA in body
    assert "jenkins-sync-1" in body and "http://x/1/" in body


def test_sha_too_short_invalid() -> None:
    """A truncated SHA is rejected instead of producing a bad subject."""
    with pytest.raises(ValueError):
        format_sync_message("abc123", TS, "b", "http://x/")


def test_sha_too_long_or_nonhex_invalid() -> None:
    """Overlong or non-hex SHAs are rejected instead of being truncated."""
    with pytest.raises(ValueError):
        format_sync_message(SHA + "00", TS, "b", "http://x/")
    with pytest.raises(ValueError):
        format_sync_message("z" * 40, TS, "b", "http://x/")


def test_timestamp_invalid() -> None:
    """Locale-dependent or malformed timestamps are rejected."""
    with pytest.raises(ValueError):
        format_sync_message(SHA, "25/09/2026 12:34", "b", "http://x/")
    with pytest.raises(ValueError):
        format_sync_message(SHA, "not-a-date", "b", "http://x/")


def test_next_tag_increments_same_day() -> None:
    """A second sync the same day bumps the numeric suffix."""
    tag = next_sync_tag(["sync-v2026.09.25-1"], "2026.09.25")
    assert tag == "sync-v2026.09.25-2"


def test_next_tag_new_day_resets() -> None:
    """The first sync of a new day starts back at suffix -1."""
    tag = next_sync_tag(["sync-v2026.09.25-3"], "2026.09.26")
    assert tag == "sync-v2026.09.26-1"


def test_changelog_prepend_and_push_script() -> None:
    """Push script versions the sync (subject/tag/changelog); CHANGELOG seeded."""
    bat = BAT.read_text(encoding="utf-8", errors="replace")
    assert "sync(codecommit)" in bat
    assert "sync-v" in bat and "CHANGELOG" in bat
    assert "%DATE% %TIME%" not in bat
    seed = CHANGELOG.read_text(encoding="utf-8")
    assert seed.startswith("# Changelog") and "## Unreleased" in seed
