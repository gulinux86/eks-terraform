# bootstrap — GitHub Actions OIDC role (one-time, per account)

Creates the prerequisites the CI pipeline needs to authenticate to AWS **without
static keys**:

- a GitHub Actions **OIDC identity provider** (`token.actions.githubusercontent.com`);
- an **IAM role** the workflows assume, trust-scoped to this repository.

This layer uses **local state** on purpose — it cannot depend on the very access
it bootstraps. Apply it once per AWS account, using administrator credentials,
from your machine (not from CI).

## Usage

```bash
cd bootstrap
terraform init
terraform apply           # uses your local admin AWS credentials

# Grab the role ARN to use as the GitHub secret:
terraform output -raw role_arn
```

Then set the GitHub secret for the matching environment:

```bash
gh secret set HML_AWS_ROLE_ARN  --repo gulinux86/eks-terraform --body "<role_arn>"
# later, in the PROD account:
gh secret set PROD_AWS_ROLE_ARN --repo gulinux86/eks-terraform --body "<prod_role_arn>"
```

## Notes

- **One provider per account.** If `token.actions.githubusercontent.com` already
  exists in the account, import it: `terraform import aws_iam_openid_connect_provider.github_actions <arn>`.
- **Permissions.** Defaults to `AdministratorAccess` for simplicity. For real
  production, replace `policy_arn` with a scoped custom policy and/or a permission
  boundary.
- **Trust scope.** Defaults to `repo:<owner>/<repo>:*` so both the plan job
  (no environment) and the deploy job (`environment: hml|prod`) can assume it.
  Tighten via `local.allowed_subs` if you want per-environment roles.
- **Multi-account PROD.** When you create the separate PROD account, run this same
  `bootstrap/` there (different credentials) to get the PROD role ARN.
```
