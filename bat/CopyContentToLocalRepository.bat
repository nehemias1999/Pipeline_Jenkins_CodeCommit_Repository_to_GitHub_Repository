@echo off

REM ===============================================
REM Script: CopyContentToLocalRepository.bat
REM Description: Copies content from a source local repository to a destination local repository.
REM ===============================================

REM ==============================
REM Parameters
REM ==============================

SET SourceRepositoryPath=%1
SET DestinyRepositoryPath=%2

REM ==============================
REM Script
REM ==============================

REM Synchronize content from the source local repository to the destination local repository (excluding specific files and folders)
robocopy %SourceRepositoryPath% %DestinyRepositoryPath% /E /MIR /XD ".git" ".github" ".cursor" /XF "docker-compose.yaml" "docker-compose.yml" ".gitignore" ".gitattributes" "README.md" ".cursorrules"

REM Verify if the robocopy command was successful
if %ERRORLEVEL% LEQ 7 (

    echo "Content copied from source local repository (%SourceRepositoryPath%) to destination local repository (%DestinyRepositoryPath%)."

    exit /b 0

) else (

    exit /b %ERRORLEVEL%
    
)
