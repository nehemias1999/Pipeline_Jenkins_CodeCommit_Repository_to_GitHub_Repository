// ==============================================================================
 // Jenkins Declarative Pipeline: sync AWS CodeCommit to GitHub via PR.
 // Purpose: detect CodeCommit changes, mirror content into the GitHub clone,
 //   push a temp branch with a plain push (force-push forbidden) and open
 // Trigger: parameterized manual/scheduled run (params) + change detection.
 // Secrets: credentialsId 'GITHUB_TOKEN' is bound ONLY inside the push stage
 //   via withCredentials (env GH_TOKEN, masked); the secret never appears in
 //   echo output, or bat/sh arguments. Requires the Mask Passwords plugin
 //   for options { maskPasswords() }; withCredentials masks GH_TOKEN regardless.
// Dependencies: agent label from params.AGENT_LABEL (default SERVER_1 Windows;
//   any Linux label runs the POSIX mirror), git, curl, python3, Jenkins
//   CredentialsBinding + Mask Passwords plugins. Linux agents additionally
//   require rsync + bash for sh/copy-content.sh; every bat/sh invocation is
//   chosen with isUnix() so both OS families run the same contract.
// Traceability: 'Generate sync metadata' records the CodeCommit HEAD SHA +
//   Jenkins build tag/url into sync-metadata.json (WORKSPACE root, never the
//   clone) and exposes SYNC_SHA/SYNC_TIMESTAMP to the push script so the PR
//   body carries SHA/build/url/timestamp; both JSON artifacts are archived.
// Versioning: the push script commits with a deterministic
//   'sync(codecommit): <short7> <timestamp>' subject/body (py/format_sync_message),
//   tags the sync commit 'sync-vYYYY.MM.DD-N' (py/next_sync_tag, incremental per
//   day), and prepends a '## sync-v... - <date> / SHA / PR' entry to CHANGELOG.md
//   (seeded with '# Changelog' + '## Unreleased'). Runs with no staged changes
//   exit before committing, so they create neither tag nor changelog entry.
// =============================================================================
 pipeline {

    agent { label "${params.AGENT_LABEL}" }

    // Declared job parameters (defaults = current job values; AGENT_LABEL
    // keeps today's Windows agent while allowing a Linux agent override).
    parameters {
        booleanParam(name: 'Force Pipeline Run', defaultValue: false, description: 'Force execution of the pipeline regardless of changes')
        string(name: 'Local Folder Path', defaultValue: '', description: 'Base local directory path for cloning repositories')
        string(name: 'CodeCommit Repository URL', defaultValue: '', description: 'URL of the source AWS CodeCommit repository')
        string(name: 'CodeCommit Repository Branch', defaultValue: 'main', description: 'Branch to check for changes and clone from CodeCommit')
        string(name: 'GitHub Repository URL', defaultValue: '', description: 'URL of the destination GitHub repository')
        string(name: 'GitHub Repository Pull/PR Branch', defaultValue: 'main', description: 'Target branch in GitHub where the Pull Request will be created')
        string(name: 'GitHub Repository Push Branch', defaultValue: 'update-from-codecommit', description: 'Temporary branch name to be created and pushed to GitHub')
        string(name: 'AGENT_LABEL', defaultValue: 'SERVER_1', description: 'Jenkins agent label (Windows SERVER_1 today, Linux label for POSIX runs)')
    }

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
        disableConcurrentBuilds()
        ansiColor('xterm')
        maskPasswords()
    }

     environment {

        /* Pipeline Parameters */

        ForcePipelineRun = "${params['Force Pipeline Run']}" // Force execution of the pipeline regardless of changes
        LocalFolderPath = "${params['Local Folder Path']}" // Base local directory path for cloning repositories
        CodeCommitRepositoryURL = "${params['CodeCommit Repository URL']}" // URL of the source AWS CodeCommit repository
        CodeCommitRepositoryBranch = "${params['CodeCommit Repository Branch']}" // Branch to check for changes and clone from CodeCommit
        GitHubRepositoryURL = "${params['GitHub Repository URL']}" // URL of the destination GitHub repository
        GitHubRepositoryDestinyBranch = "${params['GitHub Repository Pull/PR Branch']}" // Target branch in GitHub where the Pull Request will be created
        GitHubRepositoryTemporaryBranch = "${params['GitHub Repository Push Branch']}" // Temporary branch name to be created and pushed to GitHub

        /* Stage: Clone CodeCommit repository */

        // Local path where CodeCommit repository will be cloned
        CodeCommitRepositoryPath = "${LocalFolderPath}/CodeCommit"
        // Jenkins Credentials ID for accessing AWS CodeCommit
        CodeCommitRepositoryCredentials = 'CODECOMMIT_CREDENTIALS'

        /* Stage: Clone GitHub repository */

        // Local path where GitHub repository will be cloned
        GitHubLocalRepositoryPath = "${LocalFolderPath}/GitHub"
        // Jenkins Credentials ID for accessing GitHub
        GitHubRepositoryCredentials = 'GITHUB_CREDENTIALS'
        
        /* Stage: Copy CodeCommit repository content into GitHub repository */

        // Command to execute the script that copies content from CodeCommit to GitHub repo
        // (both args quoted: paths may contain spaces; the .bat strips quotes via %~1/%~2)
        CopyContentToLocalRepositoryScript = '"bat\\CopyContentToLocalRepository.bat" ' +
                                             '"%CodeCommitRepositoryPath%" ' +
                                             '"%GitHubLocalRepositoryPath%"'

        /* Stage: Push updated GitHub repository */

        // Username to be used for Git commits
        GitHubRepositoryUsername = 'github_username'
        // Email to be used for Git commits
        GitHubRepositoryEmail = 'github_email@gmail.com'
        // NOTE: the GitHub API token (credentialsId 'GITHUB_TOKEN') is bound
        // exclusively inside the push stage via withCredentials as GH_TOKEN;
        // it MUST NOT live in environment (leaks to every stage/log).

    }

    stages {

        // Fail fast on malformed repository URLs before any git clone or API call.
        stage('Validate repository URLs') {

            steps {

                echo 'Start Validate repository URLs'

                script {

                    // Portable URL validation: native shell per agent OS.
                    def gitHubUrlOk
                    def codeCommitUrlOk
                    if (isUnix()) {
                        gitHubUrlOk = sh(script: """
                            python3 "py/ExtractGitHubRepositoryName.py" "${env.GitHubRepositoryURL}" > /dev/null
                        """, returnStatus: true)

                        codeCommitUrlOk = sh(script: """
                            printf '%s' "${env.CodeCommitRepositoryURL}" | grep -Eq '^(https://|ssh://|git@|codecommit://)'
                        """, returnStatus: true)
                    } else {
                        gitHubUrlOk = bat(script: """
                            python "py\\ExtractGitHubRepositoryName.py" "${env.GitHubRepositoryURL}" > NUL
                        """, returnStatus: true)

                        codeCommitUrlOk = powershell(script: """
                            if ('${env.CodeCommitRepositoryURL}' -notmatch '^(https://|ssh://|git@|codecommit://)') { exit 1 } else { exit 0 }
                        """, returnStatus: true)
                    }

                    if (gitHubUrlOk != 0) {
                        error("Invalid GitHubRepositoryURL. Expected 'https://github.com/{owner}/{repo}[.git]' or 'git@github.com:{owner}/{repo}[.git]'.")
                    }

                    if (codeCommitUrlOk != 0) {
                        error("Invalid CodeCommitRepositoryURL. Expected an HTTPS or SSH remote URL.")
                    }

                }

                echo 'End Validate repository URLs'

            }

        }

        stage('Checking Changes') {

            steps {

                echo 'Start Checking Changes'

                script {

                    if (!fileExists("${env.CodeCommitRepositoryPath}")) {
                        echo "CodeCommit repository not found. Cloning..."
                        dir("${env.CodeCommitRepositoryPath}") {
                            git branch: "${env.CodeCommitRepositoryBranch}",
                                credentialsId: "${env.CodeCommitRepositoryCredentials}",
                                url: "${env.CodeCommitRepositoryURL}"
                        }
                    }

                    dir("${env.CodeCommitRepositoryPath}") { 

                        def changes = powershell(script: """
                            git fetch origin
                            echo (git diff --name-only ${env.CodeCommitRepositoryBranch} origin/${env.CodeCommitRepositoryBranch} | Measure-Object -Line).Lines
                        """, returnStdout: true).trim()

                        if (changes != "0") {

                            echo "Changes found in branch ${env.CodeCommitRepositoryBranch}. Proceeding..."
                            env.hasChanges = "true"

                        } else {

                            echo "No changes in branch ${env.CodeCommitRepositoryBranch}. Subsequent stages will not run."
                            env.hasChanges = "false"

                            if (env.ForcePipelineRun != "true") {

                                currentBuild.result = 'NOT_BUILT'

                            }

                        }

                    }

                }

                echo 'End Checking Changes'

            }

        }

        stage('Clone CodeCommit repository') {

            when {
                expression { return env.hasChanges == "true" || env.ForcePipelineRun == "true" }
            }

            steps {

                echo 'Start Clone CodeCommit repository'

                script {

                    try {

                        dir("${env.CodeCommitRepositoryPath}") {

                            git branch: "${env.CodeCommitRepositoryBranch}",
                                credentialsId: "${env.CodeCommitRepositoryCredentials}",
                                url: "${env.CodeCommitRepositoryURL}"

                        }

                        echo "Successfully cloned CodeCommit repository to folder: ${env.CodeCommitRepositoryPath}"

                    } catch (err) {

                        echo "Repository clone failed. Check credentials or CodeCommit connection."
                        error("Error cloning repository: ${err.message}")

                    }

                }

                echo 'End Clone CodeCommit repository'

            }

        }

        stage('Clone GitHub repository') {

            when {
                expression { return env.hasChanges == "true" || env.ForcePipelineRun == "true" }
            }

            steps {

                echo 'Start Clone GitHub repository'

                script {

                    try {

                        dir("${env.GitHubLocalRepositoryPath}") {

                            git branch: "${env.GitHubRepositoryDestinyBranch}",
                                credentialsId: "${env.GitHubRepositoryCredentials}",
                                url: "${env.GitHubRepositoryURL}"

                        }

                        echo "Successfully cloned GitHub repository to folder: ${env.GitHubLocalRepositoryPath}"

                    } catch (err) {

                        echo "Repository clone failed. Check credentials or GitHub connection."
                        error("Error cloning repository: ${err.message}")

                    }

                }

                echo 'End Clone GitHub repository'

            }

        }

        stage('Copy CodeCommit repository content into GitHub repository') {

            when {
                expression { return env.hasChanges == "true" || env.ForcePipelineRun == "true" }
            }

            steps {

                echo 'Start Copy CodeCommit repository content into GitHub repository'

                script {

                    try {

                        // Portable copy: rsync mirror on Linux, robocopy on Windows.
                        if (isUnix()) {
                            sh """
                                "sh/copy-content.sh" "${env.CodeCommitRepositoryPath}" "${env.GitHubLocalRepositoryPath}"
                            """
                        } else {
                            bat """
                                ${env.CopyContentToLocalRepositoryScript}
                            """
                        }

                    } catch (err) {

                        echo "Failed to copy content from local CodeCommit repository to GitHub repository."
                        error("Error copying files: ${err.message}")

                    }

                }

                echo 'End Copy CodeCommit repository content into GitHub repository'

            }

        }

        stage('Generate sync metadata') {

            when {
                expression { return env.hasChanges == "true" || env.ForcePipelineRun == "true" }
            }

            steps {

                echo 'Start Generate sync metadata'

                script {

                    // Source of truth: HEAD SHA of the CodeCommit clone, post-fetch.
                    dir("${env.CodeCommitRepositoryPath}") {
                        def rawSha
                        if (isUnix()) {
                            rawSha = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                        } else {
                            rawSha = bat(script: 'git rev-parse HEAD', returnStdout: true).trim()
                        }
                        env.SYNC_SHA = rawSha.split("\\r?\\n")[-1].trim()
                    }

                    if (!(env.SYNC_SHA ==~ /^[0-9a-fA-F]{40}$/)) {
                        error("Invalid SYNC_SHA '${env.SYNC_SHA}'. Expected 40 hex chars from git rev-parse HEAD.")
                    }

                    // UTC timestamp in ISO-8601 (sortable, locale-independent).
                    if (isUnix()) {
                        env.SYNC_TIMESTAMP = sh(script: 'date --utc +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim()
                    } else {
                        env.SYNC_TIMESTAMP = powershell(script: '(Get-Date).ToUniversalTime().ToString("o")', returnStdout: true).trim()
                    }

                    // Metadata lives in WORKSPACE root, never inside either clone.
                    if (isUnix()) {
                        sh """
                            python3 "py/generate_sync_metadata.py" --sha ${env.SYNC_SHA} --branch "${env.CodeCommitRepositoryBranch}" --base "${env.GitHubRepositoryDestinyBranch}" --head "${env.GitHubRepositoryTemporaryBranch}" --build-tag "${env.BUILD_TAG}" --build-url "${env.BUILD_URL}" --timestamp "${env.SYNC_TIMESTAMP}" --output "${env.WORKSPACE}/sync-metadata.json"
                        """
                    } else {
                        bat """
                            python "py\\generate_sync_metadata.py" --sha ${env.SYNC_SHA} --branch "${env.CodeCommitRepositoryBranch}" --base "${env.GitHubRepositoryDestinyBranch}" --head "${env.GitHubRepositoryTemporaryBranch}" --build-tag "${env.BUILD_TAG}" --build-url "${env.BUILD_URL}" --timestamp "${env.SYNC_TIMESTAMP}" --output "%WORKSPACE%\\sync-metadata.json"
                        """
                    }

                }

                echo 'End Generate sync metadata'

            }

        }

        stage('Push updated GitHub repository') {

            when {
                expression { return env.hasChanges == "true" || env.ForcePipelineRun == "true" }
            }

            steps {

                echo 'Start Push updated GitHub repository'

                script {

                    try {

                        // Secret handling: GH_TOKEN is injected by withCredentials
                        // as a masked env var for this block only. It is NEVER
                        // interpolated into echo/bat arguments (would leak via ps/logs).
                        withCredentials([string(credentialsId: 'GITHUB_TOKEN', variable: 'GH_TOKEN')]) {

                            def gitHubRepositoryName
                            if (isUnix()) {
                                gitHubRepositoryName = sh(script: """
                                    python3 "py/ExtractGitHubRepositoryName.py" "${env.GitHubRepositoryURL}"
                                """, returnStdout: true).trim()
                            } else {
                                gitHubRepositoryName = bat(script: """
                                    python "py\\ExtractGitHubRepositoryName.py" "${env.GitHubRepositoryURL}"
                                """, returnStdout: true).trim()
                            }

                            // BREAKING: push script no longer takes a token argument;
                            // it reads GH_TOKEN from the environment.
                            // SYNC_SHA/SYNC_TIMESTAMP flow to the script via env so the
                            // PR title/body carries CodeCommit SHA, BUILD_TAG,
                            // BUILD_URL and UTC timestamp, and so the script can
                            // commit with the sync(codecommit) subject, push the
                            // sync-v tag, and prepend the CHANGELOG.md entry.
                            // Portable push: POSIX script on Linux, .bat on Windows.
                            if (isUnix()) {
                                sh """
                                    "sh/push-and-pr.sh" "${env.GitHubLocalRepositoryPath}" ${gitHubRepositoryName} "${env.GitHubRepositoryUsername}" "${env.GitHubRepositoryEmail}" ${env.GitHubRepositoryTemporaryBranch} ${env.GitHubRepositoryDestinyBranch}
                                """
                            } else {
                                bat """
                                    "bat\\PushAndPullRequestToGitHubRemoteRepository.bat" "${env.GitHubLocalRepositoryPath}" ${gitHubRepositoryName} "${env.GitHubRepositoryUsername}" "${env.GitHubRepositoryEmail}" ${env.GitHubRepositoryTemporaryBranch} ${env.GitHubRepositoryDestinyBranch}
                                """
                            }

                        }

                        // Traceability artifacts: archived from WORKSPACE root.
                        archiveArtifacts artifacts: 'sync-metadata.json,pullrequest_response.json', allowEmptyArchive: false

                    } catch (err) {

                        echo "Failed to push to GitHub repository."
                        error("Error pushing to GitHub: ${err.message}")

                    }

                }

                echo 'End Push updated GitHub repository'

            }

        }
      
    }

}
