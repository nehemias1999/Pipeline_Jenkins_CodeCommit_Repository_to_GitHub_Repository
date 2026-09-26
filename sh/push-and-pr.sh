#!/usr/bin/env bash
# ==============================================================================
# Description: Commits local changes onto a temporary branch with a
#   deterministic sync(codecommit) subject/body (locale-independent), pushes
#   it with a plain push (force-push forbidden), tags the sync commit as
#   sync-vYYYY.MM.DD-N, prepends a CHANGELOG.md entry, and opens a PR to the
#   target branch. POSIX counterpart of
#   bat/PushAndPullRequestToGitHubRemoteRepository.bat: same CLI contract and
#   exit codes. The API call is idempotent: an already-open PR between the
#   same branches is reused instead of duplicated. The API token is NEVER a
#   CLI argument; it is read from the GH_TOKEN environment variable.
# Author: pipeline-portability implementer
# Usage: ./push-and-pr.sh "<local-path>" "<owner/repo>" "<user>" "<email>" "<temp-branch>" "<base-branch>"
# Env Vars: GH_TOKEN (required, API token), WORKSPACE (optional, response file
#   target), SYNC_SHA (required, 40-hex CodeCommit HEAD), SYNC_TIMESTAMP,
#   BUILD_TAG, BUILD_URL (traceability; unset values default to "unknown",
#   and an unknown timestamp becomes current UTC in strict Zulu form).
# Dependencies: git, curl (7.76+ for --fail-with-body), python3, date,
#   plus ../py/format_sync_message.py and ../py/next_sync_tag.py.
# Output: pullrequest_response.json in $WORKSPACE (or cwd when unset);
#   sync-v tag pushed to origin; CHANGELOG.md seeded/prepended at repo root;
#   info to stdout, errors to stderr. Exit 0 success (or nothing to commit),
#   1 any failure.
# =============================================================================
set -euo pipefail

# usage: print help to STDOUT and exit 0.
usage() {
    cat <<'EOF'
Usage: push-and-pr.sh "<local-path>" "<owner/repo>" "<user>" "<email>" "<temp-branch>" "<base-branch>"

Sync contract: commit + plain push + sync-v tag + CHANGELOG entry + PR.
Token via GH_TOKEN env only (never as argument).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 6 ]]; then
    echo "[ERROR] Expected: push-and-pr.sh <LocalPath> <owner/repo> <UserName> <Email> <TempBranch> <BaseBranch>" >&2
    exit 1
fi

repo_path="$1"
repo_name="$2"
git_user="$3"
git_email="$4"
temp_branch="$5"
base_branch="$6"

# Secret hygiene: refuse a token passed as argument.
if [[ "$*" =~ (ghp_|github_pat_|gho_|ghu_) ]]; then
    echo "[ERROR] token MUST NOT be passed as argument. Provide it via the GH_TOKEN environment variable." >&2
    exit 1
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "[ERROR] GH_TOKEN environment variable is not set." >&2
    exit 1
fi

SYNC_SHA="${SYNC_SHA:-unknown}"
BUILD_TAG="${BUILD_TAG:-unknown}"
BUILD_URL="${BUILD_URL:-unknown}"
SYNC_TIMESTAMP="${SYNC_TIMESTAMP:-unknown}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_DIR="${SCRIPT_DIR}/../py"
CHANGELOG_FILE="${SCRIPT_DIR}/../CHANGELOG.md"

# A missing/placeholder timestamp becomes current UTC in strict Zulu form.
if [[ "${SYNC_TIMESTAMP}" == "unknown" ]]; then
    SYNC_TIMESTAMP="$(date --utc +%Y-%m-%dT%H:%M:%SZ)"
fi
short_sha="${SYNC_SHA:0:7}"
pr_title="Update from CodeCommit repository (${short_sha})"

if [[ -n "${WORKSPACE:-}" ]]; then
    response_file="${WORKSPACE}/pullrequest_response.json"
else
    response_file="${PWD}/pullrequest_response.json"
fi
export PR_RESPONSE_FILE="${response_file}"
repo_owner="${repo_name%%/*}"

if [[ ! -d "${repo_path}" ]]; then
    echo "[ERROR] Could not access directory \"${repo_path}\"" >&2
    exit 1
fi
cd "${repo_path}"

git config user.name "${git_user}"
git config user.email "${git_email}"
git checkout -B "${temp_branch}"

# Traceability guard: sync/pullrequest JSON live in WORKSPACE, never the clone.
rm --force pullrequest_response.json sync-metadata.json
if git status --porcelain -- pullrequest_response.json sync-metadata.json | grep --quiet .; then
    echo "[ERROR] traceability JSON must not be committed from the clone" >&2
    exit 1
fi

git add --all
if git diff --cached --quiet; then
    echo "No changes to commit. Exiting."
    exit 0
fi

# Deterministic sync(codecommit) subject/body; a malformed SYNC_SHA aborts.
sync_subject="$(python3 "${PY_DIR}/format_sync_message.py" --sha "${SYNC_SHA}" --timestamp "${SYNC_TIMESTAMP}" --build-tag "${BUILD_TAG}" --build-url "${BUILD_URL}")"
if [[ -z "${sync_subject}" ]]; then
    echo "[ERROR] invalid SYNC_SHA. Set it to the 40-hex CodeCommit HEAD SHA." >&2
    exit 1
fi
body_file="$(mktemp)"
python3 "${PY_DIR}/format_sync_message.py" --sha "${SYNC_SHA}" --timestamp "${SYNC_TIMESTAMP}" --build-tag "${BUILD_TAG}" --build-url "${BUILD_URL}" --format body > "${body_file}"
git commit --message "${sync_subject}" --file "${body_file}"
rm --force "${body_file}"

# Plain push; force-push forbidden.
git push origin "${temp_branch}"

# Daily incremental sync-vYYYY.MM.DD-N tag on the sync commit.
sync_date="$(date --utc +%Y.%m.%d)"
sync_date_iso="$(date --utc +%Y-%m-%d)"
git fetch --tags origin
tags_file="$(mktemp)"
git tag --list "sync-v${sync_date}-*" > "${tags_file}"
sync_tag="$(python3 "${PY_DIR}/next_sync_tag.py" --date "${sync_date}" --tags-file "${tags_file}")"
rm --force "${tags_file}"
if [[ -z "${sync_tag}" ]]; then
    echo "[ERROR] could not compute sync tag" >&2
    exit 1
fi
git tag "${sync_tag}"
git push origin "${sync_tag}"

# Idempotency: reuse an already-open PR between the same branches.
curl --fail-with-body --silent --show-error --request GET \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${GH_TOKEN}" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${repo_name}/pulls?head=${repo_owner}:${temp_branch}&base=${base_branch}&state=open" \
    --output "${response_file}"

existing_pr_url="$(python3 -c "import json,os; p=os.environ.get('PR_RESPONSE_FILE',''); d=json.load(open(p)) if p else []; print((d[0].get('html_url') or '') if isinstance(d,list) and d else '')")"
pr_url=""
if [[ -n "${existing_pr_url}" ]]; then
    echo "[INFO] Reusing existing Pull Request: ${existing_pr_url}"
    pr_url="${existing_pr_url}"
else
    pr_body="Update from CodeCommit repository on branch ${temp_branch} of repository ${repo_name}. CodeCommit SHA: ${SYNC_SHA} Jenkins Build: ${BUILD_TAG} ${BUILD_URL} Timestamp UTC: ${SYNC_TIMESTAMP}"
    payload="$(PR_TITLE="${pr_title}" PR_BODY="${pr_body}" TEMP_BRANCH="${temp_branch}" BASE_BRANCH="${base_branch}" python3 -c "import json,os; print(json.dumps({'title': os.environ['PR_TITLE'], 'body': os.environ['PR_BODY'], 'head': os.environ['TEMP_BRANCH'], 'base': os.environ['BASE_BRANCH']}))")"
    curl --fail-with-body --silent --show-error --request POST \
        --header "Accept: application/vnd.github+json" \
        --header "Authorization: Bearer ${GH_TOKEN}" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${repo_name}/pulls" \
        --data "${payload}" \
        --output "${response_file}"
    if [[ ! -f "${response_file}" ]]; then
        echo "[ERROR] pullrequest_response.json not found. Something failed in the API call." >&2
        exit 1
    fi
    pr_url="$(python3 -c "import json,os,sys; d=json.load(open(os.environ['PR_RESPONSE_FILE'])); e=d.get('message','') if isinstance(d,dict) else 'Unexpected API response'; u=d.get('html_url','') if isinstance(d,dict) else ''; sys.stderr.write('[ERROR] GitHub API: ' + e + '\n') if e else None; sys.stderr.write('[ERROR] API response has no Pull Request URL.\n') if not e and not u else None; sys.exit(1) if e or not u else print(u)")"
fi

# Seed CHANGELOG.md once, then prepend one entry per sync tag.
if [[ ! -f "${CHANGELOG_FILE}" ]]; then
    printf '# Changelog\n\n## Unreleased\n' > "${CHANGELOG_FILE}"
fi
entry="## ${sync_tag} - ${sync_date_iso} / ${SYNC_SHA} / ${pr_url}"
awk -v entry="${entry}" 'BEGIN{done=0} /^## Unreleased$/{print; print entry; done=1; next} {print} END{if(!done) print entry}' "${CHANGELOG_FILE}" > "${CHANGELOG_FILE}.tmp"
mv --force "${CHANGELOG_FILE}.tmp" "${CHANGELOG_FILE}"

echo "[INFO] Pull Request to branch ${base_branch} from branch ${temp_branch} completed."
exit 0
