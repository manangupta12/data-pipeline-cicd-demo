# CI/CD Setup Walkthrough

Follow these **7 steps** to set up GitHub Actions (CI) + AWS CodePipeline (CD) using the shared course code.

**Shared code repo:** https://github.com/manangupta12/data-pipeline-cicd-demo  
**Time:** ~30 min | **AWS region:** pick one (e.g. `eu-north-1`) and use it throughout.

---

## Before you start

| Item | Your value (fill in) |
|------|----------------------|
| Your GitHub username | `________________` |
| Your new repo name | `________________` |
| AWS Lambda function name | `________________` |
| S3 source bucket | `________________` |
| DynamoDB table | `________________` |

**Prerequisites:** GitHub account, AWS console access, Lambda + S3 + DynamoDB (or create in Step 6).

---

## Step 1 — Create a new repo

1. Go to [github.com/new](https://github.com/new)
2. Repository name: e.g. `my-data-pipeline-cicd`
3. Visibility: Public or Private
4. **Do not** add README, `.gitignore`, or license (keeps the repo empty)
5. Click **Create repository**

---

## Step 2 — Clone the shared code

Clone the **course shared code** (not your new repo yet):

```bash
git clone https://github.com/manangupta12/data-pipeline-cicd-demo.git shared-code
cd shared-code
```

**What's inside:**

| Folder / file | Purpose |
|---------------|---------|
| `.github/workflows/ci-data-pipeline.yml` | GitHub Actions CI |
| `lambda/etl_customer/` | ETL Lambda code |
| `tests/` | Unit tests |
| `buildspec.yml` | CodeBuild steps for CD |
| `infra/` | IAM + CodePipeline JSON templates |
| `data/` | Sample CSV |
| `requirements-dev.txt`, `pytest.ini` | Local lint/test config |

---

## Step 3 — Copy shared code into your new repo (local)

```bash
# From inside shared-code/
cd ..

git clone https://github.com/YOUR_GITHUB_USER/my-data-pipeline-cicd.git my-repo
cd my-repo

# Copy everything except .git
cp -R ../shared-code/.github .
cp -R ../shared-code/lambda .
cp -R ../shared-code/tests .
cp -R ../shared-code/infra .
cp -R ../shared-code/data .
cp -R ../shared-code/scripts .
cp ../shared-code/buildspec.yml .
cp ../shared-code/requirements-dev.txt .
cp ../shared-code/pytest.ini .
cp ../shared-code/.gitignore .
cp ../shared-code/README.md .
cp ../shared-code/SETUP-WALKTHROUGH.md .
```

Replace `YOUR_GITHUB_USER` and `my-data-pipeline-cicd` with your values.

**Optional — verify locally before pushing:**

```bash
pip install -r requirements-dev.txt
flake8 lambda tests --max-line-length=100
pytest tests/ -v
```

---

## Step 4 — Push to GitHub

```bash
git add .
git commit -m "Add CI/CD data pipeline code from shared course repo"
git branch -M main
git push -u origin main
```

Confirm files on GitHub: `.github/workflows/`, `lambda/`, `tests/`, `buildspec.yml`, `infra/`.

---

## Step 5 — Check GitHub Actions triggered

1. Open your repo on GitHub → **Actions** tab
2. You should see workflow **CI - Data Pipeline** running (or completed)
3. Click the latest run → confirm both jobs pass:
   - **PEP8 lint (flake8)** — uses commands from `.github/workflows/ci-data-pipeline.yml`
   - **Unit tests (pytest)** — runs `tests/test_transform.py`

**If no run appears:** ensure `.github/workflows/ci-data-pipeline.yml` was pushed and the push was to `main`.

**If it fails:** open the failed step logs, fix code locally, commit, and push again.

---

## Step 6 — Integrate with AWS CodePipeline

Complete these in the **AWS Console** before creating the pipeline. Use `infra/*.json` as reference.

### 6a. Prepare Lambda (one-time)

**Console:** [Lambda → Functions](https://console.aws.amazon.com/lambda/home)

1. Create function (or use existing) — Python **3.12**, handler `lambda_function.lambda_handler`
2. **Configuration → Environment variables:** `S3_BUCKET`, `S3_KEY`, `DYNAMODB_TABLE`
3. **Permissions:** attach S3 read + DynamoDB write (see `infra/lambda-permissions-policy.json`)
4. **Actions → Publish new version**
5. **Aliases → Create alias** — name `prod`, version `1`

### 6b. S3 artifact bucket

**Console:** [S3 → Create bucket](https://s3.console.aws.amazon.com/s3/create)

- Name: `cicd-artifacts-<account-id>-<region>` (matches `artifactStore.location` in `infra/codepipeline.json`)

### 6c. GitHub connection

**Console:** [Developer Tools → Connections](https://console.aws.amazon.com/codesuite/settings/connections)

1. **Create connection** → GitHub → name `github-cicd-demo`
2. **Update pending connection** → authorize → status **Available**
3. Note the **Connection ARN** for the pipeline

### 6d. IAM roles

**Console:** [IAM → Roles](https://console.aws.amazon.com/iam/home#/roles)

| Role | Trust policy | Permissions |
|------|--------------|-------------|
| `data-pipeline-codebuild-role` | `infra/codebuild-trust-policy.json` | `infra/codebuild-policy.json` |
| `data-pipeline-codepipeline-role` | `infra/codepipeline-trust-policy.json` | `infra/codepipeline-policy.json` |

Update placeholders in policy JSON (`__ARTIFACT_BUCKET__`, `__LAMBDA_NAME__`, `__CONNECTION_ARN__`, etc.) to match your account.

### 6e. CodeBuild project

**Console:** [CodeBuild → Create project](https://console.aws.amazon.com/codesuite/codebuild/projects/create)

| Setting | Value |
|---------|-------|
| Name | `etl-customer-build` |
| Source | CodePipeline |
| Buildspec | `buildspec.yml` (from your repo) |
| Service role | `data-pipeline-codebuild-role` |

See `infra/codebuild-project.json` for full reference.

### 6f. CodePipeline (V2)

**Console:** [CodePipeline → Create pipeline](https://console.aws.amazon.com/codesuite/codepipeline/pipelines/create)

| Stage | Provider | Points to |
|-------|----------|-----------|
| **Source** | GitHub (CodeStar Connection) | **Your repo** from Step 1, branch `main` |
| **Build** | CodeBuild | `etl-customer-build` → runs `buildspec.yml` |
| **Deploy** | AWS Lambda | Your function + alias `prod` |

See `infra/codepipeline.json` for stage layout. Pipeline name: `data-pipeline-etl-cd`.

---

## Step 7 — Check CodePipeline triggered

After Step 6, either **Release change** in CodePipeline or **push a new commit** to `main`.

### Verify in AWS Console

**Console:** [CodePipeline → `data-pipeline-etl-cd`](https://console.aws.amazon.com/codesuite/codepipeline/pipelines)

| Stage | Expected | What to check |
|-------|----------|---------------|
| **Source** | Succeeded | Pulls latest commit from your GitHub repo |
| **Build** | Succeeded | CodeBuild logs show flake8, pytest, `function.zip` created |
| **Deploy** | Succeeded | Message: updated function code, published new version |

### Confirm Lambda updated

**Console:** [Lambda → your function](https://console.aws.amazon.com/lambda/home)

- **Last modified** time is recent
- **Aliases** → `prod` points to a new version

### Test the pipeline output

**Console:** Lambda → **Test** with event:

```json
{"bucket": "YOUR_S3_BUCKET", "key": "data-etl-test1/customer.csv"}
```

**Console:** [DynamoDB → Explore items](https://console.aws.amazon.com/dynamodbv2/home) — confirm records written.

---

## End-to-end flow

```
Step 4: git push main
    │
    ├─ Step 5: GitHub Actions (.github/workflows/ci-data-pipeline.yml)
    │           flake8 + pytest
    │
    └─ Step 7: CodePipeline (infra/codepipeline.json)
                Source → Build (buildspec.yml) → Deploy (Lambda prod)
```

---

## Customize

| Goal | Edit |
|------|------|
| Lint/test rules | `buildspec.yml` + `.github/workflows/ci-data-pipeline.yml` |
| Deploy target | `infra/codepipeline.json` Deploy stage |
| Different branch | Source `BranchName` in `infra/codepipeline.json` |
| Manual approval | CodePipeline → Edit → Add Approval stage before Deploy |

---

## Cleanup (Console)

Delete in order: CodePipeline → CodeBuild project → S3 artifact bucket → IAM roles → GitHub connection.

---

## Optional CLI automation

- **[SETUP-WALKTHROUGH-CLI.md](SETUP-WALKTHROUGH-CLI.md)** — full AWS CLI guide (install, login, all resources)
- `scripts/setup-aws.sh` — shortcut for Steps 4–9 after connection is authorized
