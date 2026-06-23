# Data Pipeline CI/CD Demo

ETL Lambda (S3 → DynamoDB) with GitHub Actions CI and AWS CodePipeline CD.

## Quick start

1. Read **[SETUP-WALKTHROUGH.md](SETUP-WALKTHROUGH.md)**
2. Set environment variables (`AWS_REGION`, `GITHUB_USER`, etc.)
3. Push code → verify GitHub Actions CI
4. Run `./scripts/setup-aws.sh` → authorize GitHub connection → trigger pipeline

## Repo structure

```
.github/workflows/ci-data-pipeline.yml   # CI: lint + pytest
buildspec.yml                            # CD: CodeBuild steps
lambda/etl_customer/                     # Lambda source
tests/                                   # Unit tests
infra/                                   # IAM + CodePipeline templates (__PLACEHOLDERS__)
scripts/setup-aws.sh                     # One-command AWS provisioning
```

## Architecture

```
git push main → GitHub Actions (CI) + CodePipeline (CD)
CodePipeline: Source → CodeBuild → Lambda Deploy (alias prod)
```
