# AWS infrastructure checklist — OneCGIAR IBD Platform (DEV)

This checklist covers what you create manually vs what CloudFormation creates.

## You create manually (before bootstrap)

- [ ] **Secrets Manager secret** — choose any name; pass it as `SECRET_NAME` to bootstrap
  - Store a **JSON object**. The app loads **all keys** via `getRuntimeConfig()`.
  - Example shape (keys are yours to define; values must never be committed):

    ```json
    {
      "SOME_API_KEY": "...",
      "OTHER_SETTING": "..."
    }
    ```

- [ ] **CI/CD AWS principal** (Jenkins credential or equivalent IAM user/role) with permission to:
  - ECR login / push
  - `lambda:UpdateFunctionCode`, `lambda:UpdateFunctionConfiguration`
  - `cloudfront:CreateInvalidation`
  - (optional) `cloudformation:DescribeStacks` if relying on `CFN_STACK_NAME` for distribution ID

- [ ] **CI job** that runs Node 22 + Docker and invokes `scripts/deploy-ecr.sh` after tests/build

- [ ] Ensure the Lambda env var `SECRET_NAME` matches the secret you created

## CloudFormation creates (via `scripts/bootstrap-infra.sh`)

Run once (requires Docker + AWS CLI + `SECRET_NAME` exported):

```bash
export SECRET_NAME='<your-secrets-manager-secret-name>'
export AWS_REGION=us-east-1
chmod +x scripts/bootstrap-infra.sh
./scripts/bootstrap-infra.sh
```

The script deploys `infrastructure/cloudformation.yaml` in two phases:

| Resource | Name (defaults) | Notes |
| --- | --- | --- |
| ECR repository | `onecgiar-ibd-platform-dev` | Retained on stack delete |
| IAM role | `onecgiar-ibd-platform-dev-lambda-role` | Logs + `GetSecretValue` on your secret |
| Lambda (container) | `onecgiar-ibd-platform-dev` | ≥1024 MB, 30s timeout, `SECRET_NAME` env |
| Lambda Function URL | (output `LambdaFunctionUrl`) | `AuthType: NONE` (public) |
| CloudFront | (output `CloudFrontDistributionId`) | Origin = Function URL; SSR cache disabled |

## After bootstrap — copy outputs into CI

From stack outputs (or the script summary):

| Deploy env | Source |
| --- | --- |
| `ECR_REGISTRY` | Output `EcrRegistry` (or auto via STS in `deploy-ecr.sh`) |
| `ECR_REPO` | `onecgiar-ibd-platform-dev` |
| `LAMBDA_FUNCTION_NAME` | `onecgiar-ibd-platform-dev` |
| `CLOUDFRONT_DISTRIBUTION_ID` | Output `CloudFrontDistributionId` (optional if `CFN_STACK_NAME` is set) |
| `SECRET_NAME` | The secret you created |
| Public URL | `https://<CloudFrontDomainName>/` |

## Ongoing deploys

1. Test → Build → set Lambda `SECRET_NAME` → `scripts/deploy-ecr.sh`
2. Image tag = CI build number (or chosen tag)
3. CloudFront invalidation `/*` after Lambda update

## Not used in this project

- `PUBLIC_VIDEOS_BASE_URL` — omitted on purpose
