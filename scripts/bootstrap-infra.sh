#!/usr/bin/env bash
# One-time / bootstrap infrastructure for OneCGIAR IBD Platform.
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
TEMPLATE_FILE="${TEMPLATE_FILE:-infrastructure/cloudformation.yaml}"

RESOURCE_NAME="${PROJECT_NAME}-${ENVIRONMENT}"

echo "==> Phase 1: Deploy ECR-only stack (${STACK_NAME})"
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "Environment=${ENVIRONMENT}" \
    "SecretName=${SECRET_NAME}" \
    "DeployApp=false" \
    "ImageUri="

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
echo "Copy these into Jenkinsfile / CI env:"
echo "  ECR_REGISTRY=${ECR_REGISTRY}"
echo "  ECR_REPO=${RESOURCE_NAME}"
echo "  LAMBDA_FUNCTION_NAME=${RESOURCE_NAME}"
echo "  CFN_STACK_NAME=${STACK_NAME}"
echo "  CLOUDFRONT_DISTRIBUTION_ID=<CloudFrontDistributionId from outputs above>"
echo "  SECRET_NAME=${SECRET_NAME}"
