#!/usr/bin/env bash
# Build Docker image, push to ECR, deploy to Lambda (create on first run).
#
# First run:  ensure ECR → build/push → CloudFormation (Lambda + Function URL + CloudFront)
# Later runs:  build/push → lambda update-function-code → CloudFront invalidation
#
# Required env vars:
#   ECR_REPO
#   LAMBDA_FUNCTION_NAME
#   SECRET_NAME
#
# Optional:
#   ECR_REGISTRY           defaults to <account>.dkr.ecr.<region>.amazonaws.com via STS
#   IMAGE_TAG              defaults to BUILD_NUMBER or latest
#   AWS_REGION             defaults to us-east-1
#   CLOUDFRONT_DISTRIBUTION_ID
#   CFN_STACK_NAME         stack name (default: onecgiar-ibd-platform-dev)
#   PROJECT_NAME           default: onecgiar-ibd-platform
#   ENVIRONMENT            default: dev
#   TEMPLATE_FILE          default: infrastructure/cloudformation.yaml

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO="${ECR_REPO:?ECR_REPO is required}"
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:?LAMBDA_FUNCTION_NAME is required}"
SECRET_NAME="${SECRET_NAME:?SECRET_NAME is required}"
IMAGE_TAG="${IMAGE_TAG:-${BUILD_NUMBER:-latest}}"

PROJECT_NAME="${PROJECT_NAME:-onecgiar-ibd-platform}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
CFN_STACK_NAME="${CFN_STACK_NAME:-${PROJECT_NAME}-${ENVIRONMENT}}"
TEMPLATE_FILE="${TEMPLATE_FILE:-infrastructure/cloudformation.yaml}"

if [ -z "${ECR_REGISTRY:-}" ]; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi

if [ -z "${CLOUDFRONT_DISTRIBUTION_ID:-}" ] && [ -n "${CFN_STACK_NAME:-}" ]; then
  CLOUDFRONT_DISTRIBUTION_ID="$(
    aws cloudformation describe-stacks \
      --region "${AWS_REGION}" \
      --stack-name "${CFN_STACK_NAME}" \
      --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
      --output text 2>/dev/null || true
  )"
fi

lambda_exists() {
  aws lambda get-function \
    --region "${AWS_REGION}" \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    >/dev/null 2>&1
}

stack_exists() {
  aws cloudformation describe-stacks \
    --region "${AWS_REGION}" \
    --stack-name "${CFN_STACK_NAME}" \
    >/dev/null 2>&1
}

if ! stack_exists; then
  echo "==> Creating CloudFormation stack (ECR only)"
  aws cloudformation deploy \
    --region "${AWS_REGION}" \
    --template-file "${TEMPLATE_FILE}" \
    --stack-name "${CFN_STACK_NAME}" \
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
elif lambda_exists; then
  echo "==> Stack and Lambda exist — skipping ECR-only CloudFormation step"
else
  echo "==> Stack exists without Lambda — will create app resources after image push"
fi

IMAGE_URI="${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"

echo "Building image: ${IMAGE_URI}"
docker build -t "${IMAGE_URI}" .

echo "Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "Pushing image..."
docker push "${IMAGE_URI}"

if lambda_exists; then
  echo "Updating Lambda function: ${LAMBDA_FUNCTION_NAME}"
  aws lambda update-function-code \
    --region "${AWS_REGION}" \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --image-uri "${IMAGE_URI}"

  aws lambda wait function-updated-v2 \
    --region "${AWS_REGION}" \
    --function-name "${LAMBDA_FUNCTION_NAME}"
else
  echo "First deploy — creating Lambda + Function URL + CloudFront via CloudFormation"
  aws cloudformation deploy \
    --region "${AWS_REGION}" \
    --template-file "${TEMPLATE_FILE}" \
    --stack-name "${CFN_STACK_NAME}" \
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

  aws cloudformation wait stack-update-complete \
    --region "${AWS_REGION}" \
    --stack-name "${CFN_STACK_NAME}" 2>/dev/null || \
  aws cloudformation wait stack-create-complete \
    --region "${AWS_REGION}" \
    --stack-name "${CFN_STACK_NAME}"

  CLOUDFRONT_DISTRIBUTION_ID="$(
    aws cloudformation describe-stacks \
      --region "${AWS_REGION}" \
      --stack-name "${CFN_STACK_NAME}" \
      --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
      --output text
  )"

  echo "Infrastructure created."
  aws cloudformation describe-stacks \
    --region "${AWS_REGION}" \
    --stack-name "${CFN_STACK_NAME}" \
    --query 'Stacks[0].Outputs' \
    --output table
fi

if [ -n "${CLOUDFRONT_DISTRIBUTION_ID:-}" ] && [ "${CLOUDFRONT_DISTRIBUTION_ID}" != "None" ]; then
  echo "Invalidating CloudFront: ${CLOUDFRONT_DISTRIBUTION_ID}"
  aws cloudfront create-invalidation \
    --distribution-id "${CLOUDFRONT_DISTRIBUTION_ID}" \
    --paths '/*'
fi

echo "Deploy complete: ${IMAGE_URI}"
