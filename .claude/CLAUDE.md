# terraform-tfe-mcaf-agent

## Purpose

Deploys an HCP Terraform (Terraform Cloud) self-hosted agent as an ECS Fargate task. Primary use case: workspaces that need connectivity to resources inside a VPC that are not publicly accessible.

## Architecture

Currently everything lives in `modules/ecs/` — TFE agent pool/token creation and ECS compute infrastructure in a single submodule. The plan is to later refactor TFE resources into a root module or `modules/tfe/` submodule using `moved` blocks, keeping `modules/ecs/` purely for AWS compute.

### Provider contract

The `modules/ecs/` submodule requires both `aws` and `tfe` providers configured by the caller.

### Bootstrap sequence

1. First apply runs with remote execution (HCP Terraform hosted runners) — creates agent pool, token, SSM parameter, ECS service
2. ECS agent starts, registers with HCP Terraform
3. Switch workspace to agent execution mode (manually or via `tfe_workspace_settings`)
4. Subsequent applies run on the agent inside the VPC

### Consumer usage

```hcl
module "tfc_agent" {
  source  = "schubergphilis/mcaf-agent/tfe//modules/ecs"
  version = "~> 0.1.0"

  tfe_organization   = "my-org"
  pool_name          = "my-agent-pool"
  vpc_id             = data.aws_vpc.vpc.id
  private_subnet_ids = data.aws_subnets.private.ids
  kms_key_arn        = aws_kms_key.example.arn
  tags               = var.tags
}
```

## Conventions

- Follow `sbp-terraform` skill for all Terraform conventions
- MCAF modules preferred (e.g. `mcaf-role` for IAM roles)
- KMS encryption on SSM parameter and CloudWatch log group
