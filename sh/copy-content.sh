#!/usr/bin/env bash
# ==============================================================================
# Description: Mirrors content from a source local repository into a
#   destination local repository. POSIX counterpart of
#   bat/CopyContentToLocalRepository.bat (robocopy /MIR): uses rsync with
#   --delete and the same exclusion list, so Linux agents produce the same
#   synced content as Windows agents.
# Author: pipeline-portability implementer
# Usage: ./copy-content.sh "<source>" "<dest>" (quote paths with spaces)
# Env Vars: none
# Dependencies: rsync, bash
# Output: info to stdout, errors to stderr; exit 0 on success, 1 on failure.
# =============================================================================
set -euo pipefail

# usage: print help to STDOUT and exit 0.
usage() {
    cat <<'EOF'
Usage: copy-content.sh "<source>" "<dest>"

Mirror <source> into <dest> with rsync (delete extraneous files in <dest>),
excluding .git/.github/.cursor metadata and compose/git/readme files.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 2 ]]; then
    echo "[ERROR] Expected: copy-content.sh \"<source>\" \"<dest>\"" >&2
    usage >&2
    exit 1
fi

src="$1"
dst="$2"

if [[ ! -d "${src}" ]]; then
    echo "[ERROR] Source directory not found: ${src}" >&2
    exit 1
fi
mkdir -p "${dst}"

rsync --archive --delete \
    --exclude '.git/' \
    --exclude '.github/' \
    --exclude '.cursor/' \
    --exclude 'docker-compose.yaml' \
    --exclude 'docker-compose.yml' \
    --exclude '.gitignore' \
    --exclude '.gitattributes' \
    --exclude 'README.md' \
    --exclude '.cursorrules' \
    "${src}/" "${dst}/"

echo "Content copied from source local repository (${src}) to destination local repository (${dst})."
exit 0
