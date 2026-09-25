@echo off
setlocal

REM ==============================================================================
REM Description: Commits local changes onto a temporary branch, pushes it with
REM   a temporary branch, pushes it with a plain push (force-push forbidden),
REM   target branch. The API call is idempotent: an already-open PR between the
REM   same branches is reused instead of duplicated. The API token is NEVER a
REM   CLI argument; it is read from the GH_TOKEN environment variable, which
REM   Jenkins injects via withCredentials with log masking.
REM Author: pipeline-security implementer
REM Usage: PushAndPullRequestToGitHubRemoteRepository.bat <LocalPath> <owner/repo> <UserName> <Email> <TempBranch> <BaseBranch>
REM   Help: PushAndPullRequestToGitHubRemoteRepository.bat /?
REM Env Vars: GH_TOKEN (required, API token), WORKSPACE (optional, response file target)
REM Dependencies: git, curl (7.76+ for --fail-with-body), python3 (JSON checks)
REM Output: pullrequest_response.json in %WORKSPACE% (or cwd when WORKSPACE is
REM   unset); informational messages on stdout, errors on stderr.
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

REM Committing changes
git commit -m "CodeCommit repository update performed on (%DATE% %TIME%)" || (
    echo [ERROR] git commit failed 1>&2
    exit /b 1
)

REM Pushing changes to GitHub temporary branch (plain push; force-push forbidden)
git push origin "%TemporaryBranch%" || (
    echo [ERROR] git push failed 1>&2
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
IF DEFINED ExistingPrUrl (
    echo [INFO] Reusing existing Pull Request: %ExistingPrUrl%
    exit /b 0
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

echo [INFO] Pull Request to branch %PullRequestBranch% from branch %TemporaryBranch% completed.
exit /b 0
