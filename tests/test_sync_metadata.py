# =============================================================================
# Description: TDD tests for py/generate_sync_metadata.py. Verifies the CLI
#   writes sync-metadata.json with the 7 traceability keys, validates SHA hex
#   and ISO-8601 UTC timestamp (exit 2 on error), and rejects missing fields.
# Author: pipeline-traceability implementer
# Usage: python3 -m pytest tests/test_sync_metadata.py -q
# Env Vars: none
# Dependencies: pytest, python3 (standard library only)
# =============================================================================
"""Tests for py.generate_sync_metadata (sync traceability metadata)."""

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "py" / "generate_sync_metadata.py"

BASE_ARGS = [
    "--sha", "a" * 40,
    "--branch", "main",
    "--base", "main",
    "--head", "sync/codecommit",
    "--build-tag", "jenkins-sync-42",
    "--build-url", "http://jenkins/job/sync/42/",
    "--timestamp", "2026-09-25T12:00:00Z",
]


def _run(args, output):
    """Run the CLI with the given extra args and output path."""
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args, "--output", str(output)],
        capture_output=True,
        text=True,
    )


def test_valid_metadata_written(tmp_path) -> None:
    """Valid args write JSON with the 7 required non-empty keys."""
    out = tmp_path / "sync-metadata.json"
    proc = _run(BASE_ARGS, out)
    assert proc.returncode == 0, proc.stderr
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data == {
        "codecommit_sha": "a" * 40,
        "codecommit_branch": "main",
        "github_base": "main",
        "github_head": "sync/codecommit",
        "jenkins_build_tag": "jenkins-sync-42",
        "jenkins_build_url": "http://jenkins/job/sync/42/",
        "timestamp_utc": "2026-09-25T12:00:00Z",
    }


def test_invalid_sha_exits_2(tmp_path) -> None:
    """Non-hex or short SHA fails with exit 2 and stderr, no output file."""
    out = tmp_path / "sync-metadata.json"
    args = [a if a != "a" * 40 else "xyz-not-hex" for a in BASE_ARGS]
    proc = _run(args, out)
    assert proc.returncode == 2
    assert proc.stderr.strip() != ""
    assert not out.exists()


def test_invalid_timestamp_exits_2(tmp_path) -> None:
    """Non-ISO-8601 timestamp fails with exit 2 and stderr."""
    out = tmp_path / "sync-metadata.json"
    args = [a if a != "2026-09-25T12:00:00Z" else "25/09/2026" for a in BASE_ARGS]
    proc = _run(args, out)
    assert proc.returncode == 2
    assert proc.stderr.strip() != ""
    assert not out.exists()


def test_missing_field_exits_2(tmp_path) -> None:
    """Missing required field fails with exit 2 and stderr (argparse error)."""
    out = tmp_path / "sync-metadata.json"
    args = [a for a in BASE_ARGS if a != "--build-url" and a != "http://jenkins/job/sync/42/"]
    # argparse exits 2 on missing required option
    proc = _run(args, out)
    assert proc.returncode == 2
    assert proc.stderr.strip() != ""
    assert not out.exists()


def test_round_trip_json_parseable(tmp_path) -> None:
    """Written file is valid JSON and stable across a second parse/dump."""
    out = tmp_path / "sync-metadata.json"
    proc = _run(BASE_ARGS, out)
    assert proc.returncode == 0, proc.stderr
    raw = out.read_text(encoding="utf-8")
    assert json.loads(raw) == json.loads(json.dumps(json.loads(raw)))
