@echo off

REM ===============================================
REM Script: PushAndPullRequestToGitHubRemoteRepository.bat
REM Description: Performs commit and push to a temporary branch and creates a Pull Request to the target branch in GitHub.
REM ===============================================

REM ==============================
REM Parameters
REM ==============================

SET GitHubLocalRepositoryPath=%1
SET GitHubRepositoryName=%2
SET GitHubRepositoryToken=%3
SET GitHubRepositoryUsername=%4
SET GitHubRepositoryEmail=%5
SET TemporaryBranch=%6
SET PullRequestBranch=%7

REM ==============================
REM Internal Variables
REM ==============================

SET PullRequestTitle=Update from CodeCommit repository
SET PullRequestBody=Update from CodeCommit repository on branch %TemporaryBranch% of repository %GitHubRepositoryName%.

REM ==============================
REM Script
REM ==============================

cd /d %GitHubLocalRepositoryPath% || (
    echo [ERROR] Could not access directory %GitHubLocalRepositoryPath%
    exit /b 1
)

REM [INFO] Configuring Git identity
git config user.name %GitHubRepositoryUsername%
git config user.email %GitHubRepositoryEmail%

REM Creating or updating temporary branch
git checkout -B %TemporaryBranch%

REM Adding changes to staging area
git add -A

git diff --cached --quiet
IF %ERRORLEVEL% EQU 0 (

    echo No changes to commit. Exiting.
    exit /b 0

) 

REM Committing changes
git commit -m "CodeCommit repository update performed on (%DATE% %TIME%)"

REM Pushing changes to GitHub temporary branch
git push origin %TemporaryBranch% --force

@REM REM Creating Pull Request on GitHub
curl -s -X POST ^
        -H "Accept: application/vnd.github+json" ^
        -H "Authorization: Bearer %GitHubRepositoryToken%" ^
        -H "X-GitHub-Api-Version: 2022-11-28" ^
        https://api.github.com/repos/%GitHubRepositoryName%/pulls ^
        -d "{\"title\":\"%PullRequestTitle%\",\"body\":\"%PullRequestBody%\",\"head\":\"%TemporaryBranch%\",\"base\":\"%PullRequestBranch%\"}" ^
        > pullrequest_response.json

REM Verify if the file was generated correctly
if not exist pullrequest_response.json (
    echo [ERROR] pullrequest_response.json not found. Something failed in the API call.
    exit /b 1
)

REM Perform some status check in the pullrequest_response.json file

echo [INFO] Pull Request to branch %PullRequestBranch% from branch %TemporaryBranch% completed.
exit /b 0
