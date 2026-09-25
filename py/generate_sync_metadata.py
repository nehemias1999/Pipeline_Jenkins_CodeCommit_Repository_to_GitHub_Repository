#!/usr/bin/env python3
# =============================================================================
# Description: Generates sync-metadata.json for CodeCommit-to-GitHub sync runs.
#   Records the CodeCommit source SHA/branch, GitHub base/head branches, and
#   Jenkins build tag/URL plus a UTC timestamp so every sync is auditable
#   from the archived artifact without opening Jenkins.
# Author: pipeline-traceability implementer
# Usage: python py/generate_sync_metadata.py --sha <40hex> --branch <name>
#        --base <gh-base> --head <gh-head> --build-tag <tag>
#        --build-url <url> --timestamp <iso8601-utc> --output <path>
# Env Vars: none
# Dependencies: python3 (standard library only)
# Output: writes JSON with codecommit_sha, codecommit_branch, github_base,
#   github_head, jenkins_build_tag, jenkins_build_url, timestamp_utc.
#   Errors go to stderr. Exit codes: 0 success (incl. --help), 2 invalid input.
# =============================================================================
"""Sync traceability metadata generator (CodeCommit SHA + Jenkins build)."""

import argparse
import json
import re
import sys
from datetime import datetime

_SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")

_USAGE = (
    "Usage: python py/generate_sync_metadata.py --sha <40hex> --branch <name> "
    "--base <gh-base> --head <gh-head> --build-tag <tag> --build-url <url> "
    "--timestamp <iso8601-utc> --output <path>"
)


def _parse_timestamp(value: str) -> str:
    """Validate an ISO-8601 timestamp and return it unchanged.

    Args:
        value: Candidate timestamp string (e.g. ``2026-09-25T12:00:00Z``).

    Returns:
        The original string when it parses as ISO-8601.

    Raises:
        ValueError: If the value is empty or not ISO-8601.
    """
    if not value or not value.strip():
        raise ValueError("timestamp must be a non-empty ISO-8601 UTC string.")
    candidate = value.strip().replace("Z", "+00:00")
    try:
        datetime.fromisoformat(candidate)
    except ValueError as exc:
        raise ValueError(
            f"Invalid timestamp {value!r}: expected ISO-8601 (e.g. 2026-09-25T12:00:00Z)."
        ) from exc
    return value.strip()


def build_metadata(
    sha: str,
    branch: str,
    base: str,
    head: str,
    build_tag: str,
    build_url: str,
    timestamp: str,
) -> dict:
    """Build the validated metadata mapping.

    Args:
        sha: 40-char hex CodeCommit SHA.
        branch: CodeCommit source branch.
        base: GitHub PR base branch.
        head: GitHub PR head (temporary) branch.
        build_tag: Jenkins BUILD_TAG.
        build_url: Jenkins BUILD_URL.
        timestamp: ISO-8601 UTC timestamp.

    Returns:
        Dict with the 7 traceability keys.

    Raises:
        ValueError: If any field is invalid.
    """
    if not sha or not _SHA_RE.match(sha.strip()):
        raise ValueError(f"Invalid sha {sha!r}: expected 40 hex characters.")
    fields = {
        "codecommit_branch": branch,
        "github_base": base,
        "github_head": head,
        "jenkins_build_tag": build_tag,
        "jenkins_build_url": build_url,
    }
    for key, val in fields.items():
        if not val or not val.strip():
            raise ValueError(f"Field {key} must be non-empty.")
    return {
        "codecommit_sha": sha.strip(),
        "codecommit_branch": branch.strip(),
        "github_base": base.strip(),
        "github_head": head.strip(),
        "jenkins_build_tag": build_tag.strip(),
        "jenkins_build_url": build_url.strip(),
        "timestamp_utc": _parse_timestamp(timestamp),
    }


def _parser() -> argparse.ArgumentParser:
    """Create the CLI argument parser (argparse exits 2 on missing args)."""
    parser = argparse.ArgumentParser(
        description="Generate sync-metadata.json for a CodeCommit-to-GitHub sync.",
        usage=_USAGE,
    )
    parser.add_argument("--sha", required=True, help="CodeCommit SHA (40 hex chars).")
    parser.add_argument("--branch", required=True, help="CodeCommit source branch.")
    parser.add_argument("--base", required=True, help="GitHub PR base branch.")
    parser.add_argument("--head", required=True, help="GitHub PR head branch.")
    parser.add_argument("--build-tag", required=True, help="Jenkins BUILD_TAG.")
    parser.add_argument("--build-url", required=True, help="Jenkins BUILD_URL.")
    parser.add_argument("--timestamp", required=True, help="UTC timestamp (ISO-8601).")
    parser.add_argument("--output", required=True, help="Destination JSON path.")
    return parser


def main(argv: list) -> int:
    """CLI entry point: validate, write JSON, report errors to stderr."""
    args = _parser().parse_args(argv[1:])
    try:
        data = build_metadata(
            args.sha, args.branch, args.base, args.head,
            args.build_tag, args.build_url, args.timestamp,
        )
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    try:
        with open(args.output, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2)
            handle.write("\n")
    except OSError as exc:
        print(f"Error: cannot write {args.output}: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
