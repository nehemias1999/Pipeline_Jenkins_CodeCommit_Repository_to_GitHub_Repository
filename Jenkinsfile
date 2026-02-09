pipeline {

    agent { label 'SERVER_1' }

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

        // GitHub Personal Access Token for API authentication
        GitHubRepositoryToken = credentials('GITHUB_TOKEN')
        // Username to be used for Git commits
        GitHubRepositoryUsername = 'github_username'
        // Email to be used for Git commits
        GitHubRepositoryEmail = 'github_email@gmail.com'

    }

    stages {

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

                        def gitHubRepositoryName = bat(script: """
                            python "py\\ExtractGitHubRepositoryName.py" "${env.GitHubRepositoryURL}" 
                        """, returnStdout: true).trim()

                        gitHubRepositoryName = gitHubRepositoryName.split(";")[-1].trim()

                        bat """
                            "bat\\PushAndPullRequestToGitHubRemoteRepository.bat" "${env.GitHubLocalRepositoryPath}" ${gitHubRepositoryName} "${env.GitHubRepositoryToken}" "${env.GitHubRepositoryUsername}" "${env.GitHubRepositoryEmail}" ${env.GitHubRepositoryTemporaryBranch} ${env.GitHubRepositoryDestinyBranch}
                        """

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
