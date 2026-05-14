# terraform-tfe-mcaf-agent//modules/ecs-kms-key

Creates a KMS key with the key policy required by the `modules/ecs` submodule (CloudWatch Logs encryption, account root administration).

> [!TIP]
> If you already have a KMS key, use the `policy_json` output to inspect the required policy statements and merge them into your existing key policy.

## Usage

```hcl
module "tfc_agent_kms" {
  source  = "schubergphilis/mcaf-agent/tfe//modules/ecs-kms-key"
  version = "~> 0.1.0"

  task_name = "tfc-agent"
  tags      = var.tags
}

module "tfc_agent" {
  source  = "schubergphilis/mcaf-agent/tfe//modules/ecs"
  version = "~> 0.1.0"

  tfe_organization   = "my-org"
  pool_name          = "my-agent-pool"
  vpc_id             = data.aws_vpc.vpc.id
  private_subnet_ids = data.aws_subnets.private.ids
  kms_key_arn        = module.tfc_agent_kms.arn
  tags               = var.tags
}
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
