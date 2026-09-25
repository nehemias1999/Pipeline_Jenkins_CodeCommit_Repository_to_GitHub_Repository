#!/usr/bin/env python3
# =============================================================================
# Description: Extracts "owner/repo" from a GitHub HTTPS or SSH remote URL.
#   Strict validation: only github.com HTTPS/SCP-like forms are accepted;
#   anything else fails with exit 1 and an stderr message, never inventing
#   a name on stdout. Used by Jenkins to derive the API repo path.
# Author: pipeline-security implementer
# Usage: python py/ExtractGitHubRepositoryName.py <url>
#        python py/ExtractGitHubRepositoryName.py --help
# Env Vars: none
# Dependencies: python3 (standard library only)
# Output: stdout carries exactly "owner/repo" on success; errors go to
#   stderr. Exit codes: 0 success (incl. --help), 1 invalid input.
# =============================================================================
"""Strict GitHub repository name extractor (HTTPS or SSH only)."""

import re
import sys

# Accepts only github.com remotes: https://github.com/{owner}/{repo}[.git][/]
# or git@github.com:{owner}/{repo}[.git]. Owner/repo never contain whitespace
# or extra path segments; case is preserved.
_GITHUB_URL_RE = re.compile(
    r"^(?:https://github\.com/|git@github\.com:)"
    r"([^/\s]+/[^/\s]+?)"
    r"(\.git)?/?$"
)

_USAGE = "Usage: python py/ExtractGitHubRepositoryName.py <GitHub repository URL>"


def extract_repo_name(url: str) -> str:
    """Return the ``owner/repo`` slug for a GitHub remote URL.

    Args:
        url: HTTPS (``https://github.com/...``) or SSH (``git@github.com:...``)
            remote URL, optionally suffixed with ``.git`` and/or ``/``.

    Returns:
        The ``owner/repo`` slug, case-preserved, without suffixes.

    Raises:
        ValueError: If the URL is empty or not a valid GitHub remote.
    """
    if not url or not url.strip():
        raise ValueError("Must provide a valid GitHub repository URL.")
    match = _GITHUB_URL_RE.match(url.strip())
    if not match:
        raise ValueError(
            "Invalid GitHub repository URL: expected "
            "'https://github.com/{owner}/{repo}[.git]' or "
            "'git@github.com:{owner}/{repo}[.git]'."
        )
    return match.group(1)


def main(argv: list) -> int:
    """CLI entry point: prints ``owner/repo`` to stdout, errors to stderr."""
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(_USAGE)
        return 0
    try:
        print(extract_repo_name(argv[1]))
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
