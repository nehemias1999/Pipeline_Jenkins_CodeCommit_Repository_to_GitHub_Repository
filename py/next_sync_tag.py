#!/usr/bin/env python3
"""Daily incremental sync tags for the CodeCommit-to-GitHub pipeline.

Description: Computes the next ``sync-vYYYY.MM.DD-N`` tag for a sync, where
    N increments per day so every sync commit can be reverted and audited.
Author: pipeline-versioning implementer
Usage: python3 py/next_sync_tag.py --date <YYYY.MM.DD> [--tag <tag> ...]
           [--tags-file <path>]
Env Vars: none
Dependencies: python3 (standard library only)
"""

import argparse
import re
import sys
from datetime import datetime

DATE_RE = re.compile(r"^\d{4}\.\d{2}\.\d{2}$")


def next_sync_tag(existing_tags: list[str], date_utc: str) -> str:
    """Compute the next ``sync-v{date}-N`` tag for the given UTC date.

    Args:
        existing_tags: tags already present (only ``sync-v{date}-N``
            entries for this date count toward N).
        date_utc: UTC date as ``YYYY.MM.DD``.

    Returns:
        ``sync-v{date}-{max_N + 1}``, or ``sync-v{date}-1`` when no tag
        exists yet for that date.

    Raises:
        ValueError: if the date is not a valid ``YYYY.MM.DD`` calendar date.
    """
    if not DATE_RE.match(date_utc or ""):
        raise ValueError(
            f"Invalid date {date_utc!r}. Expected YYYY.MM.DD, e.g. 2026.09.25."
        )
    try:
        datetime.strptime(date_utc, "%Y.%m.%d")
    except ValueError:
        raise ValueError(
            f"Invalid date {date_utc!r}. Expected a real YYYY.MM.DD date."
        ) from None
    prefix = f"sync-v{date_utc}-"
    suffixes = [
        int(tag[len(prefix):])
        for tag in existing_tags
        if tag.startswith(prefix) and tag[len(prefix):].isdigit()
    ]
    return f"{prefix}{max(suffixes, default=0) + 1}"


def _parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse CLI arguments (--date required, tags via --tag/--tags-file)."""
    parser = argparse.ArgumentParser(
        description="Print the next sync-vYYYY.MM.DD-N tag."
    )
    parser.add_argument("--date", required=True, help="UTC date as YYYY.MM.DD")
    parser.add_argument(
        "--tag", action="append", default=[], help="existing tag (repeatable)"
    )
    parser.add_argument(
        "--tags-file",
        default=None,
        help="file with one existing tag per line (e.g. git tag --list output)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """CLI entry point: print the next tag; exit 2 on invalid input."""
    args = _parse_args(argv)
    tags = list(args.tag)
    if args.tags_file:
        try:
            with open(args.tags_file, encoding="utf-8") as handle:
                tags.extend(line.strip() for line in handle if line.strip())
        except OSError as err:
            print(f"[ERROR] cannot read tags file: {err}", file=sys.stderr)
            return 2
    try:
        print(next_sync_tag(tags, args.date))
    except ValueError as err:
        print(f"[ERROR] {err}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
