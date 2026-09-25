@echo off
setlocal

REM ==============================================================================
REM Description: Commits local changes onto a temporary branch with a
REM   deterministic sync(codecommit) subject/body (locale-independent),
REM   pushes it with a plain push (force-push forbidden), tags the sync commit
REM   as sync-vYYYY.MM.DD-N, prepends a CHANGELOG.md entry, and opens a PR to
REM   target branch. The API call is idempotent: an already-open PR between the
REM   same branches is reused instead of duplicated. The API token is NEVER a
REM   CLI argument; it is read from the GH_TOKEN environment variable, which
REM   Jenkins injects via withCredentials with log masking.
REM Author: pipeline-security implementer
REM Usage: PushAndPullRequestToGitHubRemoteRepository.bat <LocalPath> <owner/repo> <UserName> <Email> <TempBranch> <BaseBranch>
REM   Help: PushAndPullRequestToGitHubRemoteRepository.bat /?
REM Env Vars: GH_TOKEN (required, API token), WORKSPACE (optional, response file target)
REM   SYNC_SHA (required, 40-hex CodeCommit HEAD set by Jenkins 'Generate sync
REM   metadata' stage), SYNC_TIMESTAMP, BUILD_TAG, BUILD_URL (traceability;
REM   unset values default to "unknown", and an unknown timestamp is replaced
REM   with the current UTC time in strict Zulu form).
REM Dependencies: git, curl (7.76+ for --fail-with-body), python3 (JSON checks)
REM   plus py\format_sync_message.py and py\next_sync_tag.py (repo's py dir).
REM Output: pullrequest_response.json in %WORKSPACE% (or cwd when WORKSPACE is
REM   unset); sync-v tag pushed to origin; CHANGELOG.md seeded/prepended at the
REM   repo root; informational messages on stdout, errors on stderr.
REM   Exit codes: 0 success (or nothing to commit), 1 any failure.
REM ==============================================================================

REM ==============================
REM Help and argument validation
REM ==============================

IF "%~1"=="/?" (
    echo Usage: PushAndPullRequestToGitHubRemoteRepository.bat ^<LocalPath^> ^<owner/repo^> ^<UserName^> ^<Email^> ^<TempBranch^> ^<BaseBranch^>
    exit /b 0
)
IF "%~6"=="" (
    echo [ERROR] Missing arguments. Expected: ^<LocalPath^> ^<owner/repo^> ^<UserName^> ^<Email^> ^<TempBranch^> ^<BaseBranch^> 1>&2
    exit /b 1
)

REM ==============================
REM Parameters (token is NOT one of them)
REM ==============================

SET "GitHubLocalRepositoryPath=%~1"
SET "GitHubRepositoryName=%~2"
SET "GitHubRepositoryUsername=%~3"
SET "GitHubRepositoryEmail=%~4"
SET "TemporaryBranch=%~5"
SET "PullRequestBranch=%~6"

REM ==============================
REM Secret hygiene: refuse a token passed as argument
REM ==============================

echo %* | findstr /R "ghp_ github_pat_ gho_ ghu_" >NUL
IF %ERRORLEVEL% EQU 0 (
    echo [ERROR] token MUST NOT be passed as argument. Provide it via the GH_TOKEN environment variable. 1>&2
    exit /b 1
)
IF NOT DEFINED GH_TOKEN (
    echo [ERROR] GH_TOKEN environment variable is not set. 1>&2
    exit /b 1
)

REM ==============================
REM Internal Variables
REM ==============================

SET "PullRequestTitle=Update from CodeCommit repository"
SET "PullRequestBody=Update from CodeCommit repository on branch %TemporaryBranch% of repository %GitHubRepositoryName%."
REM Traceability: PR body carries CodeCommit SHA, Jenkins build tag/url, UTC ts.
IF NOT DEFINED SYNC_SHA SET "SYNC_SHA=unknown"
IF NOT DEFINED BUILD_TAG SET "BUILD_TAG=unknown"
IF NOT DEFINED BUILD_URL SET "BUILD_URL=unknown"
IF NOT DEFINED SYNC_TIMESTAMP SET "SYNC_TIMESTAMP=unknown"
REM Versioning helpers live in the repo's py dir (parent of this bat dir).
SET "PyDir=%~dp0..\py"
SET "ChangelogFile=%~dp0..\CHANGELOG.md"
REM A missing/placeholder timestamp becomes current UTC in strict Zulu form,
REM so the sync(codecommit) subject is always locale-independent.
IF "%SYNC_TIMESTAMP%"=="unknown" (
    FOR /F "delims=" %%T IN ('powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')"') DO SET "SYNC_TIMESTAMP=%%T"
)
SET "PullRequestTitle=Update from CodeCommit repository (%SYNC_SHA:~0,7%)"
SET "PullRequestBody=Update from CodeCommit repository on branch %TemporaryBranch% of repository %GitHubRepositoryName%.\n\nCodeCommit SHA: %SYNC_SHA%\nJenkins Build: %BUILD_TAG% %BUILD_URL%\nTimestamp UTC: %SYNC_TIMESTAMP%"
IF DEFINED WORKSPACE (
    SET "ResponseFile=%WORKSPACE%\pullrequest_response.json"
) ELSE (
    SET "ResponseFile=%CD%\pullrequest_response.json"
)
SET "PR_RESPONSE_FILE=%ResponseFile%"
FOR /F "tokens=1 delims=/" %%O IN ("%GitHubRepositoryName%") DO SET "RepoOwner=%%O"

REM ==============================
REM Script
REM ==============================

cd /d "%GitHubLocalRepositoryPath%" || (
    echo [ERROR] Could not access directory "%GitHubLocalRepositoryPath%" 1>&2
    exit /b 1
)

REM Configuring Git identity
git config user.name "%GitHubRepositoryUsername%" || (
    echo [ERROR] git config user.name failed 1>&2
    exit /b 1
)
git config user.email "%GitHubRepositoryEmail%" || (
    echo [ERROR] git config user.email failed 1>&2
    exit /b 1
)

REM Creating or updating temporary branch
git checkout -B "%TemporaryBranch%" || (
    echo [ERROR] git checkout failed 1>&2
    exit /b 1
)

REM Traceability guard: sync-metadata.json and pullrequest_response.json live
REM in WORKSPACE, never inside the clone; drop strays and refuse to commit them.
IF EXIST "pullrequest_response.json" DEL /F /Q "pullrequest_response.json"
IF EXIST "sync-metadata.json" DEL /F /Q "sync-metadata.json"
git status --porcelain -- "pullrequest_response.json" "sync-metadata.json" | findstr /R "." >NUL
IF %ERRORLEVEL% EQU 0 (
    echo [ERROR] traceability JSON must not be committed from the clone 1>&2
    exit /b 1
)

REM Adding changes to staging area
git add -A || (
    echo [ERROR] git add failed 1>&2
    exit /b 1
)

git diff --cached --quiet
IF %ERRORLEVEL% EQU 0 (
    echo No changes to commit. Exiting.
    exit /b 0
)

REM Committing changes with a deterministic sync(codecommit) subject/body.
REM A malformed SYNC_SHA aborts here so it can never become the identifier.
SET "SyncSubject="
FOR /F "delims=" %%S IN ('python "%PyDir%\format_sync_message.py" --sha "%SYNC_SHA%" --timestamp "%SYNC_TIMESTAMP%" --build-tag "%BUILD_TAG%" --build-url "%BUILD_URL%" 2^>NUL') DO SET "SyncSubject=%%S"
IF NOT DEFINED SyncSubject (
    echo [ERROR] invalid SYNC_SHA. Set it to the 40-hex CodeCommit HEAD SHA. 1>&2
    exit /b 1
)
python "%PyDir%\format_sync_message.py" --sha "%SYNC_SHA%" --timestamp "%SYNC_TIMESTAMP%" --build-tag "%BUILD_TAG%" --build-url "%BUILD_URL%" --format body > "%TEMP%\sync_body.txt" || (
    echo [ERROR] could not build sync commit body 1>&2
    exit /b 1
)
git commit -m "%SyncSubject%" -F "%TEMP%\sync_body.txt" || (
    echo [ERROR] git commit failed 1>&2
    exit /b 1
)
DEL /F /Q "%TEMP%\sync_body.txt" >NUL 2>&1

REM Pushing changes to GitHub temporary branch (plain push; force-push forbidden)
git push origin "%TemporaryBranch%" || (
    echo [ERROR] git push failed 1>&2
    exit /b 1
)

REM Versioning: daily incremental sync-vYYYY.MM.DD-N tag on the sync commit.
REM No-changes runs exit before the commit above, so they never reach this tag.
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyy.MM.dd')"') DO SET "SyncDate=%%D"
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')"') DO SET "SyncDateIso=%%D"
git fetch --tags origin || (
    echo [ERROR] git fetch --tags failed 1>&2
    exit /b 1
)
git tag --list "sync-v%SyncDate%-*" > "%TEMP%\sync_tags.txt" || (
    echo [ERROR] git tag --list failed 1>&2
    exit /b 1
)
SET "SyncTag="
FOR /F "delims=" %%T IN ('python "%PyDir%\next_sync_tag.py" --date "%SyncDate%" --tags-file "%TEMP%\sync_tags.txt" 2^>NUL') DO SET "SyncTag=%%T"
DEL /F /Q "%TEMP%\sync_tags.txt" >NUL 2>&1
IF NOT DEFINED SyncTag (
    echo [ERROR] could not compute sync tag 1>&2
    exit /b 1
)
git tag "%SyncTag%" || (
    echo [ERROR] git tag failed 1>&2
    exit /b 1
)
git push origin "%SyncTag%" || (
    echo [ERROR] git push tag failed 1>&2
    exit /b 1
)

REM Idempotency: reuse an already-open PR between the same branches
curl --fail-with-body --silent --show-error --request GET ^
        --header "Accept: application/vnd.github+json" ^
        --header "Authorization: Bearer %GH_TOKEN%" ^
        --header "X-GitHub-Api-Version: 2022-11-28" ^
        "https://api.github.com/repos/%GitHubRepositoryName%/pulls?head=%RepoOwner%:%TemporaryBranch%^&base=%PullRequestBranch%^&state=open" ^
        --output "%ResponseFile%" || (
    echo [ERROR] Failed to search existing Pull Requests. See output above ^(token redacted^). 1>&2
    exit /b 1
)

SET "ExistingPrUrl="
FOR /F "delims=" %%U IN ('python -c "import json,os; p=os.environ.get('PR_RESPONSE_FILE',''); d=json.load(open(p)) if p else []; print((d[0].get('html_url') or '') if isinstance(d,list) and d else '')" 2^>NUL') DO SET "ExistingPrUrl=%%U"
SET "PrUrl="
IF DEFINED ExistingPrUrl (
    echo [INFO] Reusing existing Pull Request: %ExistingPrUrl%
    SET "PrUrl=%ExistingPrUrl%"
    GOTO :prepend_changelog
)

REM Creating Pull Request on GitHub
curl --fail-with-body --silent --show-error --request POST ^
        --header "Accept: application/vnd.github+json" ^
        --header "Authorization: Bearer %GH_TOKEN%" ^
        --header "X-GitHub-Api-Version: 2022-11-28" ^
        "https://api.github.com/repos/%GitHubRepositoryName%/pulls" ^
        --data "{\"title\":\"%PullRequestTitle%\",\"body\":\"%PullRequestBody%\",\"head\":\"%TemporaryBranch%\",\"base\":\"%PullRequestBranch%\"}" ^
        --output "%ResponseFile%" || (
    echo [ERROR] Pull Request creation failed at the API call ^(token redacted^). 1>&2
    exit /b 1
)

REM Verify if the file was generated correctly
if not exist "%ResponseFile%" (
    echo [ERROR] pullrequest_response.json not found. Something failed in the API call. 1>&2
    exit /b 1
)

REM Fail the build when the API reports an error (message/errors) or no PR URL
python -c "import json,os,sys; d=json.load(open(os.environ['PR_RESPONSE_FILE'])); e=d.get('message','') if isinstance(d,dict) else 'Unexpected API response'; u=d.get('html_url','') if isinstance(d,dict) else ''; sys.stderr.write('[ERROR] GitHub API: ' + e + '\n') if e else None; sys.stderr.write('[ERROR] API response has no Pull Request URL.\n') if not e and not u else None; sys.exit(1) if e or not u else print(u)" || (
    echo [ERROR] Pull Request was not created successfully. 1>&2
    exit /b 1
)

FOR /F "delims=" %%U IN ('python -c "import json,os; d=json.load(open(os.environ['PR_RESPONSE_FILE'])); print(d.get('html_url','') if isinstance(d,dict) else '')" 2^>NUL') DO SET "PrUrl=%%U"

:prepend_changelog
REM Versioning: seed CHANGELOG.md once, then prepend one entry per sync tag.
REM Only reached after a real commit+tag, never on the no-changes early exit.
SET "PR_URL=%PrUrl%"
SET "SYNC_TAG_VALUE=%SyncTag%"
powershell -NoProfile -Command "$p=$env:ChangelogFile; if (!(Test-Path $p)) { Set-Content -Path $p -Value \"# Changelog`n`n## Unreleased`n\" }; $l=[System.Collections.ArrayList]@(Get-Content $p); $e=\"## $($env:SYNC_TAG_VALUE) - $($env:SyncDateIso) / $($env:SYNC_SHA) / $($env:PR_URL)\"; $i=$l.IndexOf('## Unreleased'); if ($i -lt 0) { $i=0 }; $l.Insert($i+1,$e); Set-Content -Path $p -Value $l" || (
    echo [ERROR] CHANGELOG prepend failed 1>&2
    exit /b 1
)

echo [INFO] Pull Request to branch %PullRequestBranch% from branch %TemporaryBranch% completed.
exit /b 0
