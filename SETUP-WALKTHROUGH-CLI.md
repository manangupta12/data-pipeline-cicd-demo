# CI/CD Setup Walkthrough (AWS CLI)

Step-by-step guide to provision **AWS CodePipeline** and all required resources using the **AWS CLI**.

**Companion:** [SETUP-WALKTHROUGH.md](SETUP-WALKTHROUGH.md) (Console + GitHub steps)  
**Shared code:** https://github.com/manangupta12/data-pipeline-cicd-demo

---

## Overview

```
GitHub repo (your code)
    │
    ├─ GitHub Actions  →  CI (flake8 + pytest)
    └─ CodePipeline    →  Source → CodeBuild → Lambda Deploy
```

This guide covers the **AWS side** after your code is pushed to GitHub.

---

## Step 0 — Install AWS CLI

**What:** Install the command-line tool used to manage AWS resources.

**macOS (Homebrew):**
```bash
brew install awscli
```

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install
```

**Verify:**
```bash
aws --version
# aws-cli/2.x.x ...
```

---

## Step 1 — Log in / configure credentials

**What:** Link the CLI to your AWS account so commands are authenticated.

```bash
aws configure
```

Enter when prompted:

| Prompt | Value |
|--------|-------|
| AWS Access Key ID | Your IAM user access key |
| AWS Secret Access Key | Your secret key |
| Default region name | e.g. `eu-north-1` |
| Default output format | `json` |

**Verify login:**
```bash
aws sts get-caller-identity
```

You should see your `Account`, `UserId`, and `Arn`.

> **Tip:** Use an IAM user with permissions for Lambda, S3, IAM, CodeBuild, CodePipeline, and CodeStar Connections.

---

## Step 2 — Clone repo and set variables

**What:** Work from your project folder and define values reused in every command.

Complete [SETUP-WALKTHROUGH.md](SETUP-WALKTHROUGH.md) Steps 1–4 first (create repo, copy shared code, push to GitHub).

```bash
cd my-data-pipeline-cicd   # your repo root (contains infra/, buildspec.yml, etc.)

export AWS_REGION=eu-north-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export GITHUB_USER=YOUR_GITHUB_USER
export REPO_NAME=my-data-pipeline-cicd
export LAMBDA_NAME=etl-customer-s3-to-dynamodb
export ARTIFACT_BUCKET=cicd-artifacts-${AWS_ACCOUNT_ID}-${AWS_REGION}
export S3_BUCKET=testingrawdata
export DYNAMODB_TABLE=etl-test
```

**Maps to:** placeholders in `infra/*.json` (`__AWS_REGION__`, `__LAMBDA_NAME__`, etc.)

---

## Step 3 — Prepare Lambda (version + alias)

**What:** CodePipeline Lambda deploy requires a **published version** and **alias** (`prod`).  
**Code deployed:** `lambda/etl_customer/` → handler `lambda_function.lambda_handler`

**Check function exists:**
```bash
aws lambda get-function \
  --function-name "$LAMBDA_NAME" \
  --region "$AWS_REGION"
```

**Publish version:**
```bash
aws lambda publish-version \
  --function-name "$LAMBDA_NAME" \
  --region "$AWS_REGION"
```

**Create prod alias (first time only):**
```bash
aws lambda create-alias \
  --function-name "$LAMBDA_NAME" \
  --name prod \
  --function-version 1 \
  --region "$AWS_REGION"
```

**Verify:**
```bash
aws lambda list-aliases \
  --function-name "$LAMBDA_NAME" \
  --region "$AWS_REGION"
```

> If creating Lambda from scratch, deploy `lambda/etl_customer/` first and attach IAM from `infra/lambda-permissions-policy.json` (update bucket/table names).

---

## Step 4 — Create S3 artifact bucket

**What:** CodePipeline stores build artifacts (the Lambda zip) between stages.  
**Maps to:** `artifactStore.location` in `infra/codepipeline.json`

```bash
aws s3 mb "s3://${ARTIFACT_BUCKET}" --region "$AWS_REGION"
```

**Verify:**
```bash
aws s3 ls "s3://${ARTIFACT_BUCKET}" --region "$AWS_REGION"
```

---

## Step 5 — Create GitHub connection (CodeStar)

**What:** Lets CodePipeline pull source code from your GitHub repo.  
**Maps to:** Source stage `ConnectionArn` in `infra/codepipeline.json`

```bash
aws codestar-connections create-connection \
  --provider-type GitHub \
  --connection-name github-cicd-demo \
  --region "$AWS_REGION"
```

Copy the `ConnectionArn` from the output, then:

```bash
export CONNECTION_ARN="arn:aws:codestar-connections:eu-north-1:ACCOUNT:connection/xxxx"
```

**Authorize (one-time, browser required):**
```bash
aws codestar-connections get-connection \
  --connection-arn "$CONNECTION_ARN" \
  --region "$AWS_REGION" \
  --query Connection.ConnectionStatus
```

While status is `PENDING`, open **AWS Console → Developer Tools → Connections → github-cicd-demo → Update pending connection** and authorize GitHub.

**Poll until Available:**
```bash
aws codestar-connections get-connection \
  --connection-arn "$CONNECTION_ARN" \
  --region "$AWS_REGION" \
  --query Connection.ConnectionStatus
```

---

## Step 6 — Render infra templates

**What:** Replace `__PLACEHOLDERS__` in `infra/*.json` with your account values.  
**Output:** `infra/rendered/*.json` (used by commands below)

```bash
chmod +x scripts/render-infra.sh
./scripts/render-infra.sh
```

Or set `CONNECTION_ARN` before running if not already exported.

**Verify rendered pipeline references your repo:**
```bash
grep FullRepositoryId infra/rendered/codepipeline.json
# "__GITHUB_USER__/__REPO_NAME__" → your-user/your-repo
```

---

## Step 7 — Create IAM roles

**What:** Service roles so CodeBuild and CodePipeline can access S3, Lambda, and GitHub.  
**Maps to:** `infra/codebuild-trust-policy.json`, `infra/codepipeline-policy.json`, etc.

**CodeBuild role:**
```bash
aws iam create-role \
  --role-name data-pipeline-codebuild-role \
  --assume-role-policy-document file://infra/rendered/codebuild-trust-policy.json

aws iam put-role-policy \
  --role-name data-pipeline-codebuild-role \
  --policy-name codebuild-cicd-policy \
  --policy-document file://infra/rendered/codebuild-policy.json
```

**CodePipeline role:**
```bash
aws iam create-role \
  --role-name data-pipeline-codepipeline-role \
  --assume-role-policy-document file://infra/rendered/codepipeline-trust-policy.json

aws iam put-role-policy \
  --role-name data-pipeline-codepipeline-role \
  --policy-name codepipeline-cicd-policy \
  --policy-document file://infra/rendered/codepipeline-policy.json
```

**Verify:**
```bash
aws iam get-role --role-name data-pipeline-codepipeline-role
```

> If roles already exist, skip `create-role` and run only `put-role-policy`.

---

## Step 8 — Create CodeBuild project

**What:** Runs `buildspec.yml` — lint, test, and zip `lambda/etl_customer/` into `function.zip`.  
**Maps to:** `infra/codebuild-project.json` → Build stage in `infra/codepipeline.json`

```bash
aws codebuild create-project \
  --cli-input-json file://infra/rendered/codebuild-project.json \
  --region "$AWS_REGION"
```

**Verify:**
```bash
aws codebuild batch-get-projects \
  --names etl-customer-build \
  --region "$AWS_REGION" \
  --query "projects[0].name"
```

---

## Step 9 — Create CodePipeline (V2)

**What:** Wires Source → Build → Deploy into one automated release pipeline.  
**Maps to:** `infra/codepipeline.json`

```bash
aws codepipeline create-pipeline \
  --cli-input-json file://infra/rendered/codepipeline.json \
  --region "$AWS_REGION"
```

**Pipeline stages:**

| Stage | CLI config key | Repo file |
|-------|----------------|-----------|
| Source | `CodeStarSourceConnection` | GitHub repo `main` |
| Build | `ProjectName: etl-customer-build` | runs `buildspec.yml` |
| Deploy | `FunctionName` + `FunctionAlias: prod` | deploys `function.zip` |

**Verify pipeline exists:**
```bash
aws codepipeline get-pipeline \
  --name data-pipeline-etl-cd \
  --region "$AWS_REGION" \
  --query "pipeline.stages[].name"
# ["Source", "Build", "Deploy"]
```

---

## Step 10 — Trigger the pipeline

**What:** Start the first execution (or re-run after a code change).

```bash
aws codepipeline start-pipeline-execution \
  --name data-pipeline-etl-cd \
  --region "$AWS_REGION"
```

Copy the `pipelineExecutionId` from the output.

**Watch status:**
```bash
aws codepipeline get-pipeline-state \
  --name data-pipeline-etl-cd \
  --region "$AWS_REGION" \
  --query "stageStates[].{Stage:stageName,Status:latestExecution.status}"
```

Repeat until all stages show `"Succeeded"`.

---

## Step 11 — Verify deployment

**What:** Confirm CD ran end-to-end and Lambda was updated.

**Pipeline execution detail:**
```bash
aws codepipeline list-pipeline-executions \
  --pipeline-name data-pipeline-etl-cd \
  --region "$AWS_REGION" \
  --max-items 1
```

**Lambda updated:**
```bash
aws lambda get-function \
  --function-name "$LAMBDA_NAME" \
  --region "$AWS_REGION" \
  --query "Configuration.{LastModified:LastModified,CodeSize:CodeSize}"

aws lambda list-aliases \
  --function-name "$LAMBDA_NAME" \
  --region "$AWS_REGION"
```

**Invoke deployed function:**
```bash
aws lambda invoke \
  --function-name "${LAMBDA_NAME}:prod" \
  --payload "{\"bucket\":\"${S3_BUCKET}\",\"key\":\"data-etl-test1/customer.csv\"}" \
  --region "$AWS_REGION" \
  /tmp/lambda-out.json

cat /tmp/lambda-out.json
```

Expected: `"message": "ETL completed successfully"`.

---

## One-command shortcut (Steps 4–9)

After Steps 0–3 and GitHub connection is **Available**:

```bash
export CONNECTION_ARN="arn:aws:codestar-connections:..."
chmod +x scripts/setup-aws.sh
./scripts/setup-aws.sh
aws codepipeline start-pipeline-execution \
  --name data-pipeline-etl-cd --region "$AWS_REGION"
```

`scripts/setup-aws.sh` runs Steps 4–9 automatically.

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `Connection ... is not available` | Complete Step 5 authorization in Console |
| Deploy `PermissionError` on logs | Add CloudWatch permissions to `infra/codepipeline-policy.json`, re-run Step 7 |
| Build fails on pytest | Ensure `pytest.ini` and `tests/` were pushed to GitHub |
| Source fails | Check `FullRepositoryId` matches `GITHUB_USER/REPO_NAME` |

---

## Cleanup

```bash
aws codepipeline delete-pipeline --name data-pipeline-etl-cd --region "$AWS_REGION"
aws codebuild delete-project --name etl-customer-build --region "$AWS_REGION"
aws s3 rb "s3://${ARTIFACT_BUCKET}" --force
aws iam delete-role-policy --role-name data-pipeline-codepipeline-role --policy-name codepipeline-cicd-policy
aws iam delete-role --role-name data-pipeline-codepipeline-role
aws iam delete-role-policy --role-name data-pipeline-codebuild-role --policy-name codebuild-cicd-policy
aws iam delete-role --role-name data-pipeline-codebuild-role
aws codestar-connections delete-connection --connection-arn "$CONNECTION_ARN" --region "$AWS_REGION"
```

---

## File reference

| File | Used in step |
|------|--------------|
| `buildspec.yml` | 8, 9 — CodeBuild lint/test/zip |
| `infra/codepipeline.json` | 9 — pipeline definition |
| `infra/codebuild-project.json` | 8 — CodeBuild project |
| `infra/codepipeline-policy.json` | 7 — pipeline IAM permissions |
| `infra/codebuild-policy.json` | 7 — CodeBuild IAM permissions |
| `scripts/render-infra.sh` | 6 — substitute placeholders |
| `scripts/setup-aws.sh` | shortcut — Steps 4–9 |
