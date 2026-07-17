#!/usr/bin/env bash
# Ensure CloudFormation stack exists (at least ECR). Idempotent.
#
# Required: SECRET_NAME, CFN_STACK_NAME (or PROJECT_NAME + ENVIRONMENT)
# Optional: AWS_REGION, TEMPLATE_FILE

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PROJECT_NAME="${PROJECT_NAME:-onecgiar-ibd-platform}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
STACK_NAME="${CFN_STACK_NAME:-${STACK_NAME:-${PROJECT_NAME}-${ENVIRONMENT}}}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SECRET_NAME="${SECRET_NAME:?SECRET_NAME is required}"
TEMPLATE_FILE="${TEMPLATE_FILE:-infrastructure/cloudformation.yaml}"

lambda_exists() {
  aws lambda get-function \
    --region "${AWS_REGION}" \
    --function-name "${LAMBDA_FUNCTION_NAME:?LAMBDA_FUNCTION_NAME is required}" \
    >/dev/null 2>&1
}

stack_exists() {
  aws cloudformation describe-stacks \
    --region "${AWS_REGION}" \
    --stack-name "${STACK_NAME}" \
    >/dev/null 2>&1
}

echo "==> Ensuring ECR stack (${STACK_NAME})"
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --tags \
    "Project=${PROJECT_NAME}-${ENVIRONMENT}" \
    "Environment=${ENVIRONMENT}" \
    "ManagedBy=CloudFormation" \
  --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "Environment=${ENVIRONMENT}" \
    "SecretName=${SECRET_NAME}" \
    "DeployApp=false" \
    "ImageUri="

if lambda_exists; then
  echo "Lambda ${LAMBDA_FUNCTION_NAME} exists — infrastructure ready"
  exit 0
fi

echo "Lambda ${LAMBDA_FUNCTION_NAME} not found — will be created on deploy (CloudFormation DeployApp=true)"
