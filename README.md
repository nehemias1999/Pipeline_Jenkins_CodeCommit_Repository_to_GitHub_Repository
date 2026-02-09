# Pipeline Jenkins CodeCommit Repository to GitHub Repository

This project defines a Jenkins pipeline designed to automatically synchronize an AWS CodeCommit repository to a GitHub repository. It checks for changes in the source CodeCommit repository, clones it, and then pushes the changes to a temporary branch in the destination GitHub repository, creating a Pull Request for review.

## Technologies Used

*   **Jenkins**: Automation server for building, deploying, and automating the project.
*   **Groovy**: Language used for the Jenkins Pipeline script (`Jenkinsfile`).
*   **Batch Scripting (.bat)**: Used for Windows-based command execution (Git operations, file copying).
*   **Python**: Used to extract the GitHub repository name from the URL.
*   **Git**: Version control system for cloning, fetching, and pushing changes.
*   **AWS CodeCommit**: Source repository.
*   **GitHub**: Destination repository.

## Prerequisites

Before running this pipeline, ensure the following requirements are met on the Jenkins server (agent):

1.  **Software Installed**:
    *   **Git**: Accessible via command line.
    *   **Python 3.x**: Accessible via command line.
    *   **PowerShell**: Version 5.0 or later.
2.  **Jenkins Credentials**:
    *   `CODECOMMIT_CREDENTIALS`: Credentials for accessing AWS CodeCommit (Username/Password or SSH Key).
    *   `GITHUB_CREDENTIALS`: Credentials for accessing GitHub (Username/Password or Token).
    *   `GITHUB_TOKEN`: A GitHub Personal Access Token (PAT) with `repo` scope permissions to create Pull Requests via the API.
3.  **Jenkins Plugins**:
    *   **Git Plugin**: For Git operations.
    *   **Pipeline**: For declarative pipeline support.
    *   **Credentials Binding**: To securely handle credentials.

## Pipeline Workflow

The pipeline consists of the following stages:

1.  **Checking Changes**:
    *   Checks if the local CodeCommit repository exists. If not, it clones it.
    *   Fetches updates from the remote CodeCommit repository.
    *   Compares the local branch with the remote branch to detect changes.
    *   If changes are detected (or `Force Pipeline Run` is true), the pipeline proceeds. Otherwise, it stops.

2.  **Clone CodeCommit repository**:
    *   Clones the source repository from AWS CodeCommit to a local `CodeCommit` folder.

3.  **Clone GitHub repository**:
    *   Clones the destination repository from GitHub to a local `GitHub` folder.

4.  **Copy CodeCommit repository content into GitHub repository**:
    *   Executes `bat\CopyContentToLocalRepository.bat`.
    *   Uses `robocopy` to mirror the content from the CodeCommit folder to the GitHub folder.
    *   **Exclusions**: It excludes `.git`, `.github`, `.cursor` directories and specific files like `docker-compose.yaml`, `README.md`, etc., to avoid overwriting repository-specific configurations.

5.  **Push updated GitHub repository**:
    *   Extracts the GitHub repository name using `py\ExtractGitHubRepositoryName.py`.
    *   Executes `bat\PushAndPullRequestToGitHubRemoteRepository.bat`.
    *   Configures Git identity.
    *   Creates or switches to a temporary branch.
    *   Commits the changes with a timestamped message.
    *   Pushes the temporary branch to GitHub.
    *   Uses `curl` to call the GitHub API and create a Pull Request from the temporary branch to the target branch.

## Parameters

The pipeline accepts the following parameters:

*   **Force Pipeline Run**: (Boolean) If checked, forces the pipeline to run even if no changes are detected in CodeCommit.
*   **Local Folder Path**: The base directory on the Jenkins agent where repositories will be cloned.
*   **CodeCommit Repository URL**: The HTTP(S) or SSH URL of the source AWS CodeCommit repository.
*   **CodeCommit Repository Branch**: The branch in CodeCommit to monitor and sync.
*   **GitHub Repository URL**: The HTTP(S) or SSH URL of the destination GitHub repository.
*   **GitHub Repository Pull/PR Branch**: The target branch in GitHub (e.g., `main` or `master`) where the changes will be merged.
*   **GitHub Repository Push Branch**: The name of the temporary branch to create and push to GitHub (e.g., `update-from-codecommit`).

## Scripts Description

*   **`Jenkinsfile`**: Main pipeline definition.
*   **`py\ExtractGitHubRepositoryName.py`**: Python script to parse the GitHub URL and extract the "owner/repo" string required for the API call.
*   **`bat\CopyContentToLocalRepository.bat`**: Batch script using `robocopy` to sync files from source to destination, handling exclusions.
*   **`bat\PushAndPullRequestToGitHubRemoteRepository.bat`**: Batch script to handle Git commit, push, and GitHub API call for Pull Request creation.
