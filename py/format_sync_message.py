#!/usr/bin/env python3
"""Deterministic sync commit messages for the CodeCommit-to-GitHub pipeline.

Description: Builds the ``sync(codecommit): <short7> <timestamp>`` subject
    plus a traceability body (full SHA, Jenkins build tag/url). Rejects
    locale-dependent timestamps and malformed SHAs so a bad identifier can
    never become the sole sync marker.
Author: pipeline-versioning implementer
Usage: python3 py/format_sync_message.py --sha <40hex> --timestamp <iso8601>
           --build-tag <tag> --build-url <url> [--format subject|body]
Env Vars: none
Dependencies: python3 (standard library only)
"""

import argparse
import re
import sys
from datetime import datetime, timezone

SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")
FRACTION_RE = re.compile(r"(\.\d{6})\d+")


def _normalize_timestamp(timestamp_utc: str) -> str:
    """Normalize an ISO-8601 timestamp to ``YYYY-MM-DDTHH:MM:SSZ``.

    Accepts strict Zulu form plus offsets/fractions (e.g. Jenkins ``o``
    format); raises ValueError for anything else.
    """
    try:
        trimmed = FRACTION_RE.sub(
            r"\1", timestamp_utc.replace("Z", "+00:00"), count=1
        )
        parsed = datetime.fromisoformat(trimmed)
    except ValueError:
        raise ValueError(
            f"Invalid timestamp {timestamp_utc!r}. "
            "Expected ISO-8601 UTC, e.g. 2026-09-25T12:34:56Z."
        ) from None
    if parsed.tzinfo is None:
        raise ValueError(
            f"Invalid timestamp {timestamp_utc!r}. "
            "Expected ISO-8601 UTC, e.g. 2026-09-25T12:34:56Z."
        )
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def format_sync_message(
    sha_full: str, timestamp_utc: str, build_tag: str, build_url: str
) -> tuple[str, str]:
    """Build the deterministic sync commit subject and body.

    Args:
        sha_full: 40-hex CodeCommit HEAD SHA (case-insensitive).
        timestamp_utc: ISO-8601 UTC timestamp (normalized to Zulu).
        build_tag: Jenkins BUILD_TAG for traceability.
        build_url: Jenkins BUILD_URL for traceability.

    Returns:
        (subject, body) where subject matches
        ``^sync\\(codecommit\\): [0-9a-f]{7} \\d{4}-...Z$``.

    Raises:
        ValueError: if the SHA is not 40 hex chars or the timestamp is
            not ISO-8601 UTC.
    """
    if not SHA_RE.match(sha_full or ""):
        raise ValueError(
            f"Invalid sha {sha_full!r}. Expected 40 hex chars from "
            "git rev-parse HEAD."
        )
    sha = sha_full.lower()
    timestamp = _normalize_timestamp(timestamp_utc)
    subject = f"sync(codecommit): {sha[:7]} {timestamp}"
    body = (
        f"CodeCommit sync {sha[:7]}.\n"
        f"\nCodeCommit SHA: {sha}\n"
        f"Jenkins Build: {build_tag} {build_url}\n"
        f"Timestamp UTC: {timestamp}"
    )
    return subject, body


def _parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse CLI arguments (all required except --format)."""
    parser = argparse.ArgumentParser(
        description="Print a deterministic sync(codecommit) commit subject/body."
    )
    parser.add_argument("--sha", required=True, help="40-hex CodeCommit HEAD SHA")
    parser.add_argument(
        "--timestamp", required=True, help="ISO-8601 UTC timestamp from Jenkins"
    )
    parser.add_argument("--build-tag", required=True, help="Jenkins BUILD_TAG")
    parser.add_argument("--build-url", required=True, help="Jenkins BUILD_URL")
    parser.add_argument(
        "--format",
        choices=("subject", "body"),
        default="subject",
        help="which part to print (default: subject)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """CLI entry point: print subject or body; exit 2 on invalid input."""
    args = _parse_args(argv)
    try:
        subject, body = format_sync_message(
            args.sha, args.timestamp, args.build_tag, args.build_url
        )
    except ValueError as err:
        print(f"[ERROR] {err}", file=sys.stderr)
        return 2
    print(body if args.format == "body" else subject)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
