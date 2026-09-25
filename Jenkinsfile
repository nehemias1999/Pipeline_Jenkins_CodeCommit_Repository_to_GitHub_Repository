// ==============================================================================
 // Jenkins Declarative Pipeline: sync AWS CodeCommit to GitHub via PR.
 // Purpose: detect CodeCommit changes, mirror content into the GitHub clone,
 //   push a temp branch with a plain push (force-push forbidden) and open
 // Trigger: parameterized manual/scheduled run (params) + change detection.
 // Secrets: credentialsId 'GITHUB_TOKEN' is bound ONLY inside the push stage
 //   via withCredentials (env GH_TOKEN, masked); the secret never appears in
 //   echo output, or bat/sh arguments. Requires the Mask Passwords plugin
 //   for options { maskPasswords() }; withCredentials masks GH_TOKEN regardless.
 // Dependencies: Windows agent SERVER_1, git, curl, python3, Jenkins
 //   CredentialsBinding + Mask Passwords plugins.
 // =============================================================================
 pipeline {

     agent { label 'SERVER_1' }

     options { maskPasswords() }

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
        CopyContentToLocalRepositoryScript = '"bat\\CopyContentToLocalRepository.bat" ' +
                                             '"%CodeCommitRepositoryPath%" ' +
                                             "%GitHubLocalRepositoryPath%"

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

                    def gitHubUrlOk = bat(script: """
                        python "py\\ExtractGitHubRepositoryName.py" "${env.GitHubRepositoryURL}" > NUL
                    """, returnStatus: true)

                    if (gitHubUrlOk != 0) {
                        error("Invalid GitHubRepositoryURL. Expected 'https://github.com/{owner}/{repo}[.git]' or 'git@github.com:{owner}/{repo}[.git]'.")
                    }

                    def codeCommitUrlOk = powershell(script: """
                        if ('${env.CodeCommitRepositoryURL}' -notmatch '^(https://|ssh://|git@|codecommit://)') { exit 1 } else { exit 0 }
                    """, returnStatus: true)

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

                        bat """
                            ${env.CopyContentToLocalRepositoryScript}
                        """

                    } catch (err) {

                        echo "Failed to copy content from local CodeCommit repository to GitHub repository."
                        error("Error copying files: ${err.message}")

                    }

                }

                echo 'End Copy CodeCommit repository content into GitHub repository'

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

                            def gitHubRepositoryName = bat(script: """
                                python "py\\ExtractGitHubRepositoryName.py" "${env.GitHubRepositoryURL}"
                            """, returnStdout: true).trim()

                            // BREAKING: push script no longer takes a token argument;
                            // it reads GH_TOKEN from the environment.
                            bat """
                                "bat\\PushAndPullRequestToGitHubRemoteRepository.bat" "${env.GitHubLocalRepositoryPath}" ${gitHubRepositoryName} "${env.GitHubRepositoryUsername}" "${env.GitHubRepositoryEmail}" ${env.GitHubRepositoryTemporaryBranch} ${env.GitHubRepositoryDestinyBranch}
                            """

                        }

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
