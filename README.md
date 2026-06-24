# Data Pipeline CI/CD Demo

ETL Lambda (S3 → DynamoDB) with GitHub Actions CI and AWS CodePipeline CD.

**Setup guides:**
- **[SETUP-WALKTHROUGH.md](SETUP-WALKTHROUGH.md)** — Console + GitHub (7 steps)
- **[SETUP-WALKTHROUGH-CLI.md](SETUP-WALKTHROUGH-CLI.md)** — AWS CLI (install → CodePipeline)

## Repo structure

```
.github/workflows/ci-data-pipeline.yml   # CI: lint + pytest
buildspec.yml                            # CD: CodeBuild steps
lambda/etl_customer/                     # Lambda source
tests/                                   # Unit tests
infra/                                   # IAM + CodePipeline templates
scripts/                                 # Optional CLI setup
```

## Architecture

```
git push main → GitHub Actions (CI) + CodePipeline (CD)
CodePipeline: Source → CodeBuild → Lambda Deploy (alias prod)
```
