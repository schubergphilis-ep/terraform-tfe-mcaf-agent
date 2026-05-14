# terraform-tfe-mcaf-agent//modules/ecs

Deploys an HCP Terraform self-hosted agent as an ECS Fargate task, including the TFE agent pool, token, and all required AWS infrastructure.

> [!IMPORTANT]
> The first apply must run with **remote execution** (HCP Terraform hosted runners) to create the agent pool, token, and ECS service. Once the agent registers, switch the workspace to agent execution mode.

> [!NOTE]
> When `ecs_cluster_arn` is not set, the module creates a new ECS cluster. Pass an existing cluster ARN to share infrastructure.

## Usage

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

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
