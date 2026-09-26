# =============================================================================
# Description: TDD tests for pipeline portability. Verifies the Jenkinsfile
#   declares typed parameters + robustness options, dispatches bat/sh via
#   isUnix(), and that the POSIX mirror scripts (sh/*.sh) quote paths with
#   spaces, mirror robocopy exclusions via rsync, and handle errors robustly.
# Author: pipeline-portability implementer
# Usage: python3 -m pytest tests/test_portability.py -q
# Env Vars: none
# Dependencies: pytest, python3 (standard library only), rsync + bash for sync test
# =============================================================================
"""Tests for pipeline portability (Windows/Linux parity, params, options)."""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
JENKINSFILE = ROOT / "Jenkinsfile"
COPY_SH = ROOT / "sh" / "copy-content.sh"
PUSH_SH = ROOT / "sh" / "push-and-pr.sh"
COPY_BAT = ROOT / "bat" / "CopyContentToLocalRepository.bat"

# Contract: the 7 current job params, typed in a parameters block.
EXPECTED_PARAMS = [
    "Force Pipeline Run",
    "Local Folder Path",
    "CodeCommit Repository URL",
    "CodeCommit Repository Branch",
    "GitHub Repository URL",
    "GitHub Repository Pull/PR Branch",
    "GitHub Repository Push Branch",
]


def _jenkinsfile() -> str:
    assert JENKINSFILE.exists(), "Jenkinsfile missing"
    return JENKINSFILE.read_text(encoding="utf-8", errors="replace")


def test_parameters_block_declares_current_params() -> None:
    """Jenkinsfile declares a parameters block with the 7 current params."""
    text = _jenkinsfile()
    assert re.search(r"(?m)^\s*parameters\s*\{", text), "missing parameters block"
    for name in EXPECTED_PARAMS:
        assert name in text, f"parameter {name!r} not declared"


def test_parameters_agent_label_and_options() -> None:
    """AGENT_LABEL param (default SERVER_1) + robustness options present."""
    text = _jenkinsfile()
    assert "AGENT_LABEL" in text, "missing AGENT_LABEL parameter"
    assert "SERVER_1" in text, "AGENT_LABEL must default to SERVER_1"
    for token in (
        "timestamps()",
        "disableConcurrentBuilds()",
        "ansiColor('xterm')",
        "timeout(",
        "buildDiscarder(",
    ):
        assert token in text, f"options missing {token}"
    assert re.search(r"agent\s*\{\s*label\s*['\"]?\$\{params\.AGENT_LABEL\}", text), (
        "agent label must be parameterized as ${params.AGENT_LABEL}"
    )


def test_jenkinsfile_dispatches_isunix() -> None:
    """Every bat/sh invocation is wrapped in isUnix() dispatch (copy + push)."""
    text = _jenkinsfile()
    hits = re.findall(r"isUnix\(\)", text)
    assert len(hits) >= 2, f"expected >=2 isUnix() dispatches, found {len(hits)}"
    assert "copy-content.sh" in text, "missing sh dispatch for copy script"
    assert "push-and-pr.sh" in text, "missing sh dispatch for push script"


def test_sh_scripts_strict_mode_and_quoting() -> None:
    """Both sh scripts use set -euo pipefail and quote positional params."""
    for script in (COPY_SH, PUSH_SH):
        assert script.exists(), f"{script} missing"
        text = script.read_text(encoding="utf-8", errors="replace")
        assert "set -euo pipefail" in text, f"{script.name} missing strict mode"
        assert '"$' in text or '"${' in text, f"{script.name} missing quoted vars"


def test_copy_sh_mirrors_bat_exclusions() -> None:
    """copy-content.sh rsync excludes match the .bat robocopy XD/XF list."""
    bat = COPY_BAT.read_text(encoding="utf-8", errors="replace")
    excluded = [".git", ".github", ".cursor", "docker-compose.yaml", "README.md"]
    for token in excluded:
        assert token in bat, f".bat missing exclusion {token}"
    text = COPY_SH.read_text(encoding="utf-8", errors="replace")
    assert "rsync" in text and "--delete" in text, "copy-content.sh must rsync --delete"
    for token in excluded:
        assert token in text, f"copy-content.sh missing exclusion {token}"


def test_copy_sh_sync_with_spaces_in_paths() -> None:
    """Sync with spaces in src/dst exits 0 and mirrors content minus excludes."""
    if shutil.which("rsync") is None or shutil.which("bash") is None:
        pytest.skip("rsync/bash required for sync test")
    import tempfile

    with tempfile.TemporaryDirectory(prefix="port src ") as tmp:
        src = Path(tmp) / "code commit"
        dst = Path(tmp) / "git hub"
        (src / ".git").mkdir(parents=True)
        (src / ".github").mkdir(parents=True)
        (src / "sub dir").mkdir(parents=True)
        (src / "keep me.txt").write_text("hello", encoding="utf-8")
        (src / "sub dir" / "nested.txt").write_text("nested", encoding="utf-8")
        (src / ".git" / "config").write_text("x", encoding="utf-8")
        (src / ".github" / "w.yml").write_text("y", encoding="utf-8")
        proc = subprocess.run(
            ["bash", str(COPY_SH), str(src), str(dst)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert proc.returncode == 0, f"copy-content.sh exit {proc.returncode}: {proc.stderr}"
        assert (dst / "keep me.txt").read_text(encoding="utf-8") == "hello"
        assert (dst / "sub dir" / "nested.txt").read_text(encoding="utf-8") == "nested"
        assert not (dst / ".git").exists(), ".git must be excluded"
        assert not (dst / ".github").exists(), ".github must be excluded"


def test_push_sh_contract() -> None:
    """push-and-pr.sh reads GH_TOKEN env and uses curl --fail-with-body."""
    assert PUSH_SH.exists(), "sh/push-and-pr.sh missing"
    text = PUSH_SH.read_text(encoding="utf-8", errors="replace")
    assert "GH_TOKEN" in text, "push-and-pr.sh must read GH_TOKEN env"
    assert "--fail-with-body" in text, "push-and-pr.sh must use curl --fail-with-body"
    assert re.search(r"(?m)^\s*usage\(\)", text) or "--help" in text, (
        "push-and-pr.sh must expose usage()/--help"
    )


def test_copy_bat_quoting_and_exit_mapping() -> None:
    """.bat copy uses setlocal, %~1/%~2 quoting, and LEQ 7 -> exit 0."""
    text = COPY_BAT.read_text(encoding="utf-8", errors="replace")
    assert re.search(r"(?im)^\s*setlocal", text), ".bat copy missing setlocal"
    assert "%~1" in text and "%~2" in text, ".bat copy must use %~1/%~2"
    assert re.search(r"LEQ\s+7", text, re.IGNORECASE), ".bat copy missing LEQ 7 mapping"
    assert "endlocal" in text.lower(), ".bat copy missing endlocal"
