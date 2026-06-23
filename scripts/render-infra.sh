#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
: "${GITHUB_USER:?Set GITHUB_USER}"
: "${REPO_NAME:?Set REPO_NAME}"
: "${LAMBDA_NAME:?Set LAMBDA_NAME}"
: "${ARTIFACT_BUCKET:?Set ARTIFACT_BUCKET}"

CONNECTION_ARN="${CONNECTION_ARN:-__REPLACE_AFTER_create-connection__}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/infra/rendered"
mkdir -p "$OUT"

render() {
  local src="$1" dst="$2"
  sed \
    -e "s/__AWS_ACCOUNT_ID__/${AWS_ACCOUNT_ID}/g" \
    -e "s/__AWS_REGION__/${AWS_REGION}/g" \
    -e "s/__GITHUB_USER__/${GITHUB_USER}/g" \
    -e "s/__REPO_NAME__/${REPO_NAME}/g" \
    -e "s/__LAMBDA_NAME__/${LAMBDA_NAME}/g" \
    -e "s/__ARTIFACT_BUCKET__/${ARTIFACT_BUCKET}/g" \
    -e "s|__CONNECTION_ARN__|${CONNECTION_ARN}|g" \
    "$src" > "$dst"
  echo "Rendered $dst"
}

render "$ROOT/infra/codebuild-trust-policy.json" "$OUT/codebuild-trust-policy.json"
render "$ROOT/infra/codepipeline-trust-policy.json" "$OUT/codepipeline-trust-policy.json"
render "$ROOT/infra/codebuild-policy.json" "$OUT/codebuild-policy.json"
render "$ROOT/infra/codepipeline-policy.json" "$OUT/codepipeline-policy.json"
render "$ROOT/infra/codebuild-project.json" "$OUT/codebuild-project.json"
render "$ROOT/infra/codepipeline.json" "$OUT/codepipeline.json"

echo ""
echo "Rendered files in infra/rendered/"
echo "Update CONNECTION_ARN after: aws codestar-connections create-connection ..."
