# =============================================================================
# Description: Strict TDD tests for ExtractGitHubRepositoryName extractor.
#   Covers https/ssh, .git suffix, trailing slash, empty, invalid,
#   uppercase/whitespace. Also verifies CLI contract: stdout carries only
#   owner/repo, errors go to stderr with exit 1.
# Author: pipeline-security implementer
# Usage: python3 -m pytest tests/ -q
# Env Vars: none
# Dependencies: pytest
# =============================================================================
"""Tests for py.ExtractGitHubRepositoryName (strict extractor)."""

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "py" / "ExtractGitHubRepositoryName.py"


def _load_module():
    """Load the extractor by file path (avoids top-level 'py' collisions)."""
    spec = importlib.util.spec_from_file_location("extract_repo", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


extract_repo_name = _load_module().extract_repo_name


def test_https_url() -> None:
    """HTTPS URL yields owner/repo."""
    assert extract_repo_name("https://github.com/acme/myrepo") == "acme/myrepo"


def test_ssh_url() -> None:
    """SSH SCP-like URL yields owner/repo."""
    assert extract_repo_name("git@github.com:acme/myrepo") == "acme/myrepo"


def test_git_suffix_stripped() -> None:
    """Optional .git suffix is stripped for both URL forms."""
    assert extract_repo_name("https://github.com/acme/myrepo.git") == "acme/myrepo"
    assert extract_repo_name("git@github.com:acme/myrepo.git") == "acme/myrepo"


def test_trailing_slash_accepted() -> None:
    """Optional trailing slash is accepted."""
    assert extract_repo_name("https://github.com/acme/myrepo/") == "acme/myrepo"


def test_uppercase_and_surrounding_spaces() -> None:
    """Case is preserved and surrounding whitespace is tolerated."""
    assert extract_repo_name("  https://github.com/Acme/MyRepo  ") == "Acme/MyRepo"


def test_empty_url_raises() -> None:
    """Empty input raises ValueError."""
    with pytest.raises(ValueError):
        extract_repo_name("")


def test_invalid_url_raises() -> None:
    """Non-GitHub URL raises ValueError (never invents owner/repo)."""
    with pytest.raises(ValueError):
        extract_repo_name("not-a-url")


def test_cli_prints_only_owner_repo() -> None:
    """CLI prints exactly owner/repo on stdout (no ';' prefix)."""
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "https://github.com/acme/myrepo"],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0
    assert proc.stdout.strip() == "acme/myrepo"
    assert ";" not in proc.stdout


def test_cli_invalid_goes_to_stderr_exit_1() -> None:
    """CLI failure exits 1, writes stderr, prints no owner/repo on stdout."""
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "not-a-url"],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 1
    assert proc.stdout.strip() == ""
    assert proc.stderr.strip() != ""
