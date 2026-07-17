#!/usr/bin/env bash
# One-time / manual bootstrap (optional — Jenkins deploy-ecr.sh handles first run).
#
# Phase 1: Create ECR repository via CloudFormation (DeployApp=false).
# Phase 2: Build & push a bootstrap image.
# Phase 3: Update the stack with Lambda + Function URL + CloudFront (DeployApp=true).
#
# Prerequisites:
#   - AWS CLI configured with permissions for CFN, ECR, IAM, Lambda, CloudFront
#   - Docker available
#   - Secrets Manager secret already created (pass its name as SECRET_NAME)
#
# Usage:
#   export SECRET_NAME='<your-secrets-manager-secret-name>'
#   export AWS_REGION=us-east-1
#   ./scripts/bootstrap-infra.sh
#
# Optional overrides:
#   PROJECT_NAME=onecgiar-ibd-platform
#   ENVIRONMENT=dev
#   STACK_NAME=onecgiar-ibd-platform-dev
#   IMAGE_TAG=bootstrap

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PROJECT_NAME="${PROJECT_NAME:-onecgiar-ibd-platform}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
STACK_NAME="${STACK_NAME:-${PROJECT_NAME}-${ENVIRONMENT}}"
AWS_REGION="${AWS_REGION:-us-east-1}"
IMAGE_TAG="${IMAGE_TAG:-bootstrap}"
SECRET_NAME="${SECRET_NAME:?SECRET_NAME is required (create the secret in Secrets Manager first)}"
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-${PROJECT_NAME}-${ENVIRONMENT}}"
TEMPLATE_FILE="${TEMPLATE_FILE:-infrastructure/cloudformation.yaml}"

RESOURCE_NAME="${PROJECT_NAME}-${ENVIRONMENT}"

stack_exists() {
  aws cloudformation describe-stacks \
    --region "${AWS_REGION}" \
    --stack-name "${STACK_NAME}" \
    >/dev/null 2>&1
}

lambda_exists() {
  aws lambda get-function \
    --region "${AWS_REGION}" \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    >/dev/null 2>&1
}

if lambda_exists; then
  echo "Lambda ${LAMBDA_FUNCTION_NAME} already exists. Use scripts/deploy-ecr.sh instead."
  exit 0
fi

if ! stack_exists; then
  echo "==> Phase 1: Deploy ECR-only stack (${STACK_NAME})"
  aws cloudformation deploy \
    --region "${AWS_REGION}" \
    --template-file "${TEMPLATE_FILE}" \
    --stack-name "${STACK_NAME}" \
    --capabilities CAPABILITY_NAMED_IAM \
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
else
  echo "==> Phase 1: Stack ${STACK_NAME} already exists — skipping ECR-only deploy"
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${ECR_REGISTRY}/${RESOURCE_NAME}:${IMAGE_TAG}"

echo "==> Phase 2: Build and push bootstrap image (${IMAGE_URI})"
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker build -t "${IMAGE_URI}" .
docker push "${IMAGE_URI}"

echo "==> Phase 3: Deploy Lambda + Function URL + CloudFront"
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags \
    "Project=${PROJECT_NAME}-${ENVIRONMENT}" \
    "Environment=${ENVIRONMENT}" \
    "ManagedBy=CloudFormation" \
  --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "Environment=${ENVIRONMENT}" \
    "SecretName=${SECRET_NAME}" \
    "DeployApp=true" \
    "ImageUri=${IMAGE_URI}"

echo "==> Stack outputs"
aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs' \
  --output table

echo
echo "Bootstrap complete."
echo "  ECR_REGISTRY=${ECR_REGISTRY}"
echo "  ECR_REPO=${RESOURCE_NAME}"
echo "  LAMBDA_FUNCTION_NAME=${RESOURCE_NAME}"
echo "  CFN_STACK_NAME=${STACK_NAME}"
echo "  SECRET_NAME=${SECRET_NAME}"
