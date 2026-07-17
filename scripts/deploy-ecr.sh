#!/usr/bin/env bash
# Build Docker image, push to ECR, and update Lambda (container image).
#
# Required env vars:
#   ECR_REPO
#   LAMBDA_FUNCTION_NAME
#
# Optional:
#   ECR_REGISTRY           defaults to <account>.dkr.ecr.<region>.amazonaws.com via STS
#   IMAGE_TAG              defaults to BUILD_NUMBER or latest
#   AWS_REGION             defaults to us-east-1
#   CLOUDFRONT_DISTRIBUTION_ID
#   CFN_STACK_NAME         if set and CLOUDFRONT_DISTRIBUTION_ID is empty, read from stack outputs

set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO="${ECR_REPO:?ECR_REPO is required}"
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:?LAMBDA_FUNCTION_NAME is required}"
IMAGE_TAG="${IMAGE_TAG:-${BUILD_NUMBER:-latest}}"

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
      --output text
  )"
fi

IMAGE_URI="${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"

echo "Building image: ${IMAGE_URI}"
docker build -t "${IMAGE_URI}" .

echo "Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "Pushing image..."
docker push "${IMAGE_URI}"

echo "Updating Lambda function: ${LAMBDA_FUNCTION_NAME}"
aws lambda update-function-code \
  --region "${AWS_REGION}" \
  --function-name "${LAMBDA_FUNCTION_NAME}" \
  --image-uri "${IMAGE_URI}"

aws lambda wait function-updated-v2 \
  --region "${AWS_REGION}" \
  --function-name "${LAMBDA_FUNCTION_NAME}"

if [ -n "${CLOUDFRONT_DISTRIBUTION_ID:-}" ] && [ "${CLOUDFRONT_DISTRIBUTION_ID}" != "None" ]; then
  echo "Invalidating CloudFront: ${CLOUDFRONT_DISTRIBUTION_ID}"
  aws cloudfront create-invalidation \
    --distribution-id "${CLOUDFRONT_DISTRIBUTION_ID}" \
    --paths '/*'
fi

echo "Deploy complete: ${IMAGE_URI}"
