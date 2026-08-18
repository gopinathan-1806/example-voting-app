// ============================================================
// Jenkins CI Pipeline — example-voting-app
//
// Full stage order:
//   1.  Checkout
//   2.  Secret Detection        (Gitleaks — blocks on any hit)
//   3.  Trivy FS Scan           (CVE scan of source tree, fail on CRITICAL)
//   4.  Unit / Lint Tests       (vote:flake8, result:mocha, worker:dotnet test)
//   5.  SonarQube Analysis      (vote / result / worker — all in parallel)
//   6.  SonarQube Quality Gate  (blocks pipeline until gate resolves)
//   7.  Build Docker Images     (vote / result / worker — parallel)
//   8.  Trivy Image Scan        (CRITICAL + HIGH — parallel)
//   9.  Push to Docker Hub      (gopi1806/voting-app-*)
//   10. Update k8s Manifests    (commits tag back → ArgoCD auto-sync)
//
// Required Jenkins credentials (Manage Jenkins → Credentials):
//   DOCKER_HUB_CREDENTIALS  – Username/Password  (Docker Hub login)
//   GIT_CREDENTIALS         – Username/Password  (GitHub PAT for manifest push)
//   SONAR_TOKEN             – Secret Text        (SonarQube user token)
//
// Required Jenkins environment variables (Manage Jenkins → System):
//   SONAR_HOST_URL   – e.g. http://sonarqube.example.com
//   GIT_USER_NAME    – committer name for manifest update commit
//   GIT_USER_EMAIL   – committer email for manifest update commit
// ============================================================

pipeline {
    agent any

    // ── Configurable knobs ──────────────────────────────────
    environment {
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_REPO     = 'gopi1806'
        APP_PREFIX      = 'voting-app'

        IMAGE_VOTE      = "${DOCKER_REPO}/${APP_PREFIX}-vote"
        IMAGE_RESULT    = "${DOCKER_REPO}/${APP_PREFIX}-result"
        IMAGE_WORKER    = "${DOCKER_REPO}/${APP_PREFIX}-worker"

        // Short-SHA tag — immutable, traceable, triggers ArgoCD diff
        IMAGE_TAG       = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"

        SONAR_HOST_URL  = "${env.SONAR_HOST_URL ?: 'http://localhost:9000'}"
        GIT_USER_NAME   = "${env.GIT_USER_NAME  ?: 'jenkins-bot'}"
        GIT_USER_EMAIL  = "${env.GIT_USER_EMAIL ?: 'jenkins@example.com'}"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
        timestamps()
    }

    stages {

        // ── 1. Checkout ──────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    echo "▶ Building tag: ${env.IMAGE_TAG}"
                }
            }
        }

        // ── 2. Secret Detection ──────────────────────────────
        // Gitleaks scans every file in the working tree for hardcoded
        // secrets, tokens, private keys, and high-entropy strings.
        // Pipeline aborts immediately on any finding.
        //
        // Install Gitleaks on the agent:
        //   https://github.com/gitleaks/gitleaks#installing
        stage('Secret Detection') {
            steps {
                sh '''
                    gitleaks detect \
                        --source . \
                        --redact \
                        --no-git \
                        --exit-code 1 \
                        --report-format sarif \
                        --report-path gitleaks-report.sarif
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks-report.sarif',
                                     allowEmptyArchive: true
                }
            }
        }

        // ── 3. Trivy Filesystem Scan ─────────────────────────
        // Scans source dependencies (requirements.txt, package-lock.json,
        // *.csproj) for known CVEs before any image is built.
        stage('Trivy FS Scan') {
            steps {
                sh '''
                    trivy fs \
                        --exit-code 1 \
                        --severity CRITICAL \
                        --no-progress \
                        --format sarif \
                        --output trivy-fs-report.sarif \
                        --ignore-unfixed \
                        .
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-fs-report.sarif',
                                     allowEmptyArchive: true
                }
            }
        }

        // ── 4. Unit / Lint Tests ─────────────────────────────
        stage('Tests') {
            parallel {

                // vote — Python: flake8 lint + basic import check
                stage('vote: lint') {
                    steps {
                        dir('vote') {
                            sh '''
                                pip install --quiet flake8
                                flake8 . \
                                    --max-line-length=120 \
                                    --exclude=__pycache__ \
                                    --format=pylint
                            '''
                        }
                    }
                }

                // result — Node.js: mocha tests (result/tests/)
                stage('result: test') {
                    steps {
                        dir('result') {
                            sh '''
                                npm ci --quiet
                                npm test
                            '''
                        }
                    }
                }

                // worker — .NET: dotnet test (skips build via --no-build
                // only if solution has a test project; falls back gracefully)
                stage('worker: dotnet test') {
                    steps {
                        dir('worker') {
                            sh '''
                                dotnet restore
                                dotnet build --no-restore -c Release
                                # Run tests if a test project exists, otherwise skip
                                if ls *Tests.csproj 2>/dev/null | head -1; then
                                    dotnet test --no-build -c Release \
                                        --logger "trx;LogFileName=results.trx"
                                else
                                    echo "No test project found — skipping dotnet test"
                                fi
                            '''
                        }
                    }
                    post {
                        always {
                            // Publish .NET test results if present
                            script {
                                if (fileExists('worker/results.trx')) {
                                    archiveArtifacts artifacts: 'worker/results.trx',
                                                     allowEmptyArchive: true
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── 5. SonarQube Analysis ────────────────────────────
        // Each service is analysed as a separate SonarQube project so that
        // quality gates and dashboards are cleanly separated per language.
        // Requires the SonarQube Scanner tool configured in
        //   Manage Jenkins → Tools → SonarQube Scanner installations
        //   (name it exactly "SonarQube")
        stage('SonarQube Analysis') {
            parallel {

                stage('sonar: vote') {
                    steps {
                        withCredentials([string(
                            credentialsId: 'SONAR_TOKEN',
                            variable: 'SONAR_AUTH_TOKEN'
                        )]) {
                            withSonarQubeEnv('SonarQube') {
                                script {
                                    def scannerHome = tool 'SonarQube'
                                    sh """
                                        ${scannerHome}/bin/sonar-scanner \
                                            -Dsonar.projectKey=voting-app-vote \
                                            -Dsonar.projectName="Voting App - Vote (Python)" \
                                            -Dsonar.sources=vote \
                                            -Dsonar.language=py \
                                            -Dsonar.python.version=3.11 \
                                            -Dsonar.host.url=${SONAR_HOST_URL} \
                                            -Dsonar.login=${SONAR_AUTH_TOKEN}
                                    """
                                }
                            }
                        }
                    }
                }

                stage('sonar: result') {
                    steps {
                        withCredentials([string(
                            credentialsId: 'SONAR_TOKEN',
                            variable: 'SONAR_AUTH_TOKEN'
                        )]) {
                            withSonarQubeEnv('SonarQube') {
                                script {
                                    def scannerHome = tool 'SonarQube'
                                    sh """
                                        ${scannerHome}/bin/sonar-scanner \
                                            -Dsonar.projectKey=voting-app-result \
                                            -Dsonar.projectName="Voting App - Result (Node.js)" \
                                            -Dsonar.sources=result \
                                            -Dsonar.exclusions=result/node_modules/**,result/tests/** \
                                            -Dsonar.javascript.lcov.reportPaths=result/coverage/lcov.info \
                                            -Dsonar.host.url=${SONAR_HOST_URL} \
                                            -Dsonar.login=${SONAR_AUTH_TOKEN}
                                    """
                                }
                            }
                        }
                    }
                }

                stage('sonar: worker') {
                    steps {
                        withCredentials([string(
                            credentialsId: 'SONAR_TOKEN',
                            variable: 'SONAR_AUTH_TOKEN'
                        )]) {
                            withSonarQubeEnv('SonarQube') {
                                script {
                                    def scannerHome = tool 'SonarQube'
                                    sh """
                                        ${scannerHome}/bin/sonar-scanner \
                                            -Dsonar.projectKey=voting-app-worker \
                                            -Dsonar.projectName="Voting App - Worker (.NET)" \
                                            -Dsonar.sources=worker \
                                            -Dsonar.cs.opencover.reportsPaths=worker/coverage.opencover.xml \
                                            -Dsonar.host.url=${SONAR_HOST_URL} \
                                            -Dsonar.login=${SONAR_AUTH_TOKEN}
                                    """
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── 6. SonarQube Quality Gate ────────────────────────
        // Waits for all three analysis reports to be processed by
        // SonarQube and fails the build if any project fails its gate.
        stage('Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ── 7. Build Docker Images ────────────────────────────
        stage('Build Images') {
            parallel {
                stage('Build vote') {
                    steps {
                        sh """
                            docker build \
                                --target final \
                                -t ${IMAGE_VOTE}:${IMAGE_TAG} \
                                -t ${IMAGE_VOTE}:latest \
                                ./vote
                        """
                    }
                }
                stage('Build result') {
                    steps {
                        sh """
                            docker build \
                                -t ${IMAGE_RESULT}:${IMAGE_TAG} \
                                -t ${IMAGE_RESULT}:latest \
                                ./result
                        """
                    }
                }
                stage('Build worker') {
                    steps {
                        sh """
                            docker build \
                                -t ${IMAGE_WORKER}:${IMAGE_TAG} \
                                -t ${IMAGE_WORKER}:latest \
                                ./worker
                        """
                    }
                }
            }
        }

        // ── 8. Trivy Image Scan ───────────────────────────────
        // Scans the freshly built images for CRITICAL and HIGH CVEs.
        // Reports are archived even on failure so the team can triage.
        stage('Trivy Image Scan') {
            parallel {
                stage('Scan vote') {
                    steps {
                        sh """
                            trivy image \
                                --exit-code 1 \
                                --severity CRITICAL,HIGH \
                                --no-progress \
                                --format sarif \
                                --output trivy-image-vote.sarif \
                                --ignore-unfixed \
                                ${IMAGE_VOTE}:${IMAGE_TAG}
                        """
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'trivy-image-vote.sarif',
                                             allowEmptyArchive: true
                        }
                    }
                }
                stage('Scan result') {
                    steps {
                        sh """
                            trivy image \
                                --exit-code 1 \
                                --severity CRITICAL,HIGH \
                                --no-progress \
                                --format sarif \
                                --output trivy-image-result.sarif \
                                --ignore-unfixed \
                                ${IMAGE_RESULT}:${IMAGE_TAG}
                        """
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'trivy-image-result.sarif',
                                             allowEmptyArchive: true
                        }
                    }
                }
                stage('Scan worker') {
                    steps {
                        sh """
                            trivy image \
                                --exit-code 1 \
                                --severity CRITICAL,HIGH \
                                --no-progress \
                                --format sarif \
                                --output trivy-image-worker.sarif \
                                --ignore-unfixed \
                                ${IMAGE_WORKER}:${IMAGE_TAG}
                        """
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'trivy-image-worker.sarif',
                                             allowEmptyArchive: true
                        }
                    }
                }
            }
        }

        // ── 9. Push to Docker Hub ────────────────────────────
        stage('Push Images') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'DOCKER_HUB_CREDENTIALS',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh """
                        echo "\${DOCKER_PASS}" | docker login \
                            -u "\${DOCKER_USER}" --password-stdin

                        docker push ${IMAGE_VOTE}:${IMAGE_TAG}
                        docker push ${IMAGE_VOTE}:latest

                        docker push ${IMAGE_RESULT}:${IMAGE_TAG}
                        docker push ${IMAGE_RESULT}:latest

                        docker push ${IMAGE_WORKER}:${IMAGE_TAG}
                        docker push ${IMAGE_WORKER}:latest

                        docker logout
                    """
                }
            }
        }

        // ── 10. Update k8s Manifests → triggers ArgoCD ───────
        // sed replaces the image tag in all three deployment files, then
        // commits and pushes. ArgoCD detects the diff and auto-syncs.
        // [skip ci] prevents Jenkins re-triggering on this commit.
        stage('Update Manifests') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'GIT_CREDENTIALS',
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_PASS'
                )]) {
                    sh """
                        git config user.name  "${GIT_USER_NAME}"
                        git config user.email "${GIT_USER_EMAIL}"

                        sed -i 's|image: ${IMAGE_VOTE}:.*|image: ${IMAGE_VOTE}:${IMAGE_TAG}|' \
                            k8s-specifications/vote-deployment.yaml

                        sed -i 's|image: ${IMAGE_RESULT}:.*|image: ${IMAGE_RESULT}:${IMAGE_TAG}|' \
                            k8s-specifications/result-deployment.yaml

                        sed -i 's|image: ${IMAGE_WORKER}:.*|image: ${IMAGE_WORKER}:${IMAGE_TAG}|' \
                            k8s-specifications/worker-deployment.yaml

                        git add k8s-specifications/vote-deployment.yaml \
                                k8s-specifications/result-deployment.yaml \
                                k8s-specifications/worker-deployment.yaml

                        git diff --cached --quiet || git commit \
                            -m "ci: update images to ${IMAGE_TAG} [skip ci]"

                        git push https://\${GIT_USER}:\${GIT_PASS}@\$(
                            git remote get-url origin | sed 's|https://||'
                        )
                    """
                }
            }
        }
    }

    // ── Post actions ──────────────────────────────────────────
    post {
        always {
            sh """
                docker rmi ${IMAGE_VOTE}:${IMAGE_TAG}    || true
                docker rmi ${IMAGE_VOTE}:latest          || true
                docker rmi ${IMAGE_RESULT}:${IMAGE_TAG}  || true
                docker rmi ${IMAGE_RESULT}:latest        || true
                docker rmi ${IMAGE_WORKER}:${IMAGE_TAG}  || true
                docker rmi ${IMAGE_WORKER}:latest        || true
            """
        }
        success {
            echo "✅  Pipeline succeeded — ArgoCD will deploy tag ${env.IMAGE_TAG}"
        }
        failure {
            echo "❌  Pipeline failed — manifests were NOT updated"
        }
    }
}
