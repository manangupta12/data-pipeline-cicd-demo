#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
: "${GITHUB_USER:?Set GITHUB_USER}"
: "${REPO_NAME:?Set REPO_NAME}"
: "${LAMBDA_NAME:?Set LAMBDA_NAME}"
: "${ARTIFACT_BUCKET:?Set ARTIFACT_BUCKET}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Creating S3 artifact bucket"
aws s3 mb "s3://${ARTIFACT_BUCKET}" --region "$AWS_REGION" 2>/dev/null || true

echo "==> Creating GitHub CodeStar connection"
CONN=$(aws codestar-connections create-connection \
  --provider-type GitHub \
  --connection-name github-cicd-demo \
  --region "$AWS_REGION" \
  --query ConnectionArn --output text 2>/dev/null || \
  aws codestar-connections list-connections --region "$AWS_REGION" \
  --query "Connections[?ConnectionName=='github-cicd-demo'].ConnectionArn | [0]" --output text)
export CONNECTION_ARN="$CONN"
echo "Connection ARN: $CONNECTION_ARN"
echo ">>> Authorize in Console: Developer Tools > Connections > github-cicd-demo"

./scripts/render-infra.sh

OUT="$ROOT/infra/rendered"

echo "==> Creating IAM roles"
aws iam create-role --role-name data-pipeline-codebuild-role \
  --assume-role-policy-document "file://${OUT}/codebuild-trust-policy.json" 2>/dev/null || true
aws iam put-role-policy --role-name data-pipeline-codebuild-role \
  --policy-name codebuild-cicd-policy \
  --policy-document "file://${OUT}/codebuild-policy.json"

aws iam create-role --role-name data-pipeline-codepipeline-role \
  --assume-role-policy-document "file://${OUT}/codepipeline-trust-policy.json" 2>/dev/null || true
aws iam put-role-policy --role-name data-pipeline-codepipeline-role \
  --policy-name codepipeline-cicd-policy \
  --policy-document "file://${OUT}/codepipeline-policy.json"

echo "==> Creating CodeBuild project"
aws codebuild create-project \
  --cli-input-json "file://${OUT}/codebuild-project.json" \
  --region "$AWS_REGION" 2>/dev/null || \
  aws codebuild update-project \
  --cli-input-json "file://${OUT}/codebuild-project.json" \
  --region "$AWS_REGION"

echo "==> Creating CodePipeline"
aws codepipeline create-pipeline \
  --cli-input-json "file://${OUT}/codepipeline.json" \
  --region "$AWS_REGION" 2>/dev/null || \
  aws codepipeline update-pipeline \
  --cli-input-json "file://${OUT}/codepipeline.json" \
  --region "$AWS_REGION"

echo ""
echo "Done. After authorizing GitHub connection, run:"
echo "  aws codepipeline start-pipeline-execution --name data-pipeline-etl-cd --region $AWS_REGION"
