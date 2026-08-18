# Jenkins Credentials & Environment Setup

## 1. Required Credentials

Add all of these under **Manage Jenkins → Credentials → System → Global credentials**.

| Credential ID             | Kind                | What to put in it                                               |
|--------------------------|---------------------|-----------------------------------------------------------------|
| `DOCKER_HUB_CREDENTIALS` | Username / Password | Docker Hub username: `gopi1806` / Password: Docker Hub PAT     |
| `GIT_CREDENTIALS`        | Username / Password | GitHub username / Personal Access Token (`repo` write scope)    |
| `SONAR_TOKEN`            | Secret Text         | SonarQube user token (My Account → Security → Generate Token)  |

> **Docker Hub PAT**: Hub → Account Settings → Security → New Access Token (Read/Write).  
> **Never** use your account password — use tokens for both.

---

## 2. Required Environment Variables

Set these under **Manage Jenkins → System → Global properties → Environment variables**.

| Variable          | Example value              | Description                                     |
|------------------|----------------------------|-------------------------------------------------|
| `SONAR_HOST_URL` | `http://sonarqube.myco.com`| Full URL to your SonarQube instance             |
| `GIT_USER_NAME`  | `Jenkins Bot`              | Committer name for manifest-update commits      |
| `GIT_USER_EMAIL` | `jenkins@example.com`      | Committer email for manifest-update commits     |

---

## 3. SonarQube Plugin & Scanner Setup

### Jenkins Plugin
Install **SonarQube Scanner for Jenkins** (Manage Jenkins → Plugins → Available):
- Plugin ID: `sonarqube-scanner`

### Configure the SonarQube server
**Manage Jenkins → System → SonarQube servers → Add SonarQube**:
- Name: `SonarQube`  ← must match exactly what's in the Jenkinsfile
- Server URL: your `SONAR_HOST_URL` value
- Server authentication token: select the `SONAR_TOKEN` credential

### Install the Scanner tool
**Manage Jenkins → Tools → SonarQube Scanner → Add**:
- Name: `SonarQube`  ← must match `tool 'SonarQube'` in the Jenkinsfile
- Install automatically: ✅ (pick latest version)

### SonarQube: create three projects
In SonarQube UI (Projects → Create Project → Manually):

| Project Key           | Display name                      |
|----------------------|-----------------------------------|
| `voting-app-vote`    | Voting App - Vote (Python)        |
| `voting-app-result`  | Voting App - Result (Node.js)     |
| `voting-app-worker`  | Voting App - Worker (.NET)        |

Configure a **Webhook** so the Quality Gate stage works:
- SonarQube → Administration → Configuration → Webhooks → Create
- Name: `Jenkins`
- URL: `http://<jenkins-host>/sonarqube-webhook/`

---

## 4. Gitleaks Installation on the Jenkins Agent

```bash
# macOS
brew install gitleaks

# Linux (amd64)
GITLEAKS_VER=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
    | grep tag_name | cut -d'"' -f4 | tr -d 'v')
curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_linux_x64.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks

# Verify
gitleaks version
```

---

## 5. Trivy Installation on the Jenkins Agent

```bash
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin

# Verify
trivy --version
```

---

## 6. Pipeline Job Configuration

1. **New Item → Pipeline**
2. Under **Pipeline**, choose **Pipeline script from SCM**
3. SCM → Git → paste your repo URL
4. Credentials → select `GIT_CREDENTIALS`
5. Branch → `*/main`
6. Script Path → `Jenkinsfile`
7. ✅ **Lightweight checkout** (improves speed for large repos)
8. Save → **Build Now** for first run

---

## 7. Docker Hub Repository Setup

Create the three public (or private) repositories on Docker Hub before the first push:

| Repository                     | Maps to                  |
|-------------------------------|--------------------------|
| `gopi1806/voting-app-vote`    | vote service (Python)    |
| `gopi1806/voting-app-result`  | result service (Node.js) |
| `gopi1806/voting-app-worker`  | worker service (.NET)    |

Hub → Repositories → Create Repository (one per service).

---

## 8. ArgoCD Application

```yaml
# argocd-app.yaml — apply once: kubectl apply -f argocd-app.yaml -n argocd
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: voting-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/example-voting-app.git
    targetRevision: main
    path: k8s-specifications
  destination:
    server: https://kubernetes.default.svc
    namespace: voting-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## 9. Full Pipeline Flow

```
git push (main)
  │
  ▼
Jenkins triggers
  ├─ [1] Checkout              → capture short SHA as IMAGE_TAG
  ├─ [2] Secret Detection      → Gitleaks scans all files (blocks on hit)
  ├─ [3] Trivy FS Scan         → dependency CVE scan (blocks on CRITICAL)
  ├─ [4] Tests (parallel)
  │       ├─ vote: flake8 lint
  │       ├─ result: npm test
  │       └─ worker: dotnet test
  ├─ [5] SonarQube Analysis (parallel)
  │       ├─ vote project
  │       ├─ result project
  │       └─ worker project
  ├─ [6] Quality Gate          → waits for SonarQube; blocks on fail
  ├─ [7] Build Images (parallel)
  │       ├─ gopi1806/voting-app-vote:<sha>
  │       ├─ gopi1806/voting-app-result:<sha>
  │       └─ gopi1806/voting-app-worker:<sha>
  ├─ [8] Trivy Image Scan (parallel)  → CRITICAL + HIGH (blocks on hit)
  ├─ [9] Push Images           → push :<sha> + :latest to Docker Hub
  └─ [10] Update Manifests     → sed + git commit [skip ci] + push
                                       │
                                       ▼
                                  ArgoCD detects diff
                                       │
                                       ▼
                                  kubectl rollout → new pods running :<sha>
```

The `[skip ci]` trailer in the manifest commit prevents Jenkins from
re-triggering itself on that push (supported by GitHub Branch Source,
GitLab Branch Source, and Gitea plugins out of the box).
