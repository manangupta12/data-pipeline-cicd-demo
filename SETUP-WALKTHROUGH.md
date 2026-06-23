# CI/CD Setup Walkthrough

Deploy this ETL Lambda pipeline with **GitHub Actions (CI)** + **AWS CodePipeline (CD)**.

**Time:** ~30 min | **Region example:** `eu-north-1`

---

## Prerequisites

- GitHub account + [new empty repo](https://github.com/new)
- AWS account with CLI configured (`aws sts get-caller-identity`)
- Existing or new Lambda, S3 bucket, DynamoDB table for ETL

---

## 1. Clone and configure variables

```bash
git clone https://github.com/YOUR_GITHUB_USER/data-pipeline-cicd-demo.git
cd data-pipeline-cicd-demo

export AWS_REGION=eu-north-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export GITHUB_USER=YOUR_GITHUB_USER
export REPO_NAME=data-pipeline-cicd-demo
export LAMBDA_NAME=etl-customer-s3-to-dynamodb
export ARTIFACT_BUCKET=cicd-artifacts-${AWS_ACCOUNT_ID}-${AWS_REGION}
export S3_BUCKET=testingrawdata          # your source bucket
export DYNAMODB_TABLE=etl-test           # your destination table
```

Replace `YOUR_GITHUB_USER` and bucket/table names to match your environment.

---

## 2. Application code (already in repo)

| File | Purpose |
|------|---------|
| `lambda/etl_customer/transform.py` | Pure ETL logic — unit tested |
| `lambda/etl_customer/lambda_function.py` | Lambda handler — S3 → DynamoDB |
| `tests/test_transform.py` | Unit tests |
| `buildspec.yml` | CodeBuild: lint → test → zip |
| `.github/workflows/ci-data-pipeline.yml` | GitHub Actions CI on push/PR |

**Verify locally:**

```bash
pip install -r requirements-dev.txt
flake8 lambda tests --max-line-length=100
pytest tests/ -v
```

**Push to GitHub** → check **Actions** tab for green CI run.

---

## 3. Lambda runtime (one-time)

Create Lambda (if needed) with handler `lambda_function.lambda_handler`, Python 3.12.

Attach IAM policy from `infra/lambda-permissions-policy.json` — update bucket/table ARNs for your account.

Publish version + alias (required for CodePipeline deploy):

```bash
aws lambda publish-version --function-name $LAMBDA_NAME --region $AWS_REGION
aws lambda create-alias --function-name $LAMBDA_NAME --name prod \
  --function-version 1 --region $AWS_REGION
```

---

## 4. AWS CD infrastructure

Run the setup script (renders templates + creates resources):

```bash
chmod +x scripts/setup-aws.sh
./scripts/setup-aws.sh
```

**Or manually** — render templates first:

```bash
./scripts/render-infra.sh   # creates infra/rendered/*.json
```

Then follow the commands printed by the script.

### What gets created

| Resource | Defined in |
|----------|------------|
| S3 artifact bucket | `infra/codepipeline.json` → `artifactStore.location` |
| CodeBuild project | `infra/codebuild-project.json` |
| CodePipeline V2 | `infra/codepipeline.json` (Source → Build → Deploy) |
| IAM roles | `infra/*-trust-policy.json`, `infra/*-policy.json` |

### GitHub connection (manual step)

After `./scripts/setup-aws.sh`:

1. AWS Console → **Developer Tools → Connections**
2. Open **`github-cicd-demo`** → **Update pending connection** → authorize GitHub
3. Trigger pipeline:

```bash
aws codepipeline start-pipeline-execution \
  --name data-pipeline-etl-cd --region $AWS_REGION
```

---

## 5. How it flows on `git push main`

```
Push to main
  ├─ GitHub Actions (.github/workflows/ci-data-pipeline.yml)
  │    └─ flake8 + pytest
  └─ CodePipeline (infra/codepipeline.json)
       ├─ Source  → pull repo via CodeStar connection
       ├─ Build   → buildspec.yml → function.zip
       └─ Deploy  → Lambda $LAMBDA_NAME alias prod
```

---

## 6. Verify

```bash
# Pipeline status
aws codepipeline get-pipeline-state --name data-pipeline-etl-cd --region $AWS_REGION

# Lambda updated?
aws lambda list-aliases --function-name $LAMBDA_NAME --region $AWS_REGION

# Invoke
aws lambda invoke --function-name ${LAMBDA_NAME}:prod \
  --payload '{"bucket":"'"$S3_BUCKET"'","key":"data-etl-test1/customer.csv"}' \
  --region $AWS_REGION /tmp/out.json && cat /tmp/out.json
```

---

## Customize

| Change | Edit |
|--------|------|
| Lint/test rules | `buildspec.yml` pre_build + `.github/workflows/ci-data-pipeline.yml` |
| Deploy target | `infra/codepipeline.json` → Deploy stage `FunctionName` / `FunctionAlias` |
| Trigger branch | `infra/codepipeline.json` → Source `BranchName` |
| Add manual approval | Insert Approval stage in `infra/codepipeline.json` between Build and Deploy |

---

## Cleanup

```bash
aws codepipeline delete-pipeline --name data-pipeline-etl-cd --region $AWS_REGION
aws codebuild delete-project --name etl-customer-build --region $AWS_REGION
aws s3 rb s3://$ARTIFACT_BUCKET --force
# Delete IAM roles: data-pipeline-codepipeline-role, data-pipeline-codebuild-role
```
