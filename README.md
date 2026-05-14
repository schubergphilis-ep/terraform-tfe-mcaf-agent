# terraform-tfe-mcaf-agent

Terraform module to deploy an HCP Terraform (Terraform Cloud) self-hosted agent as an ECS Fargate task.

## Submodules

| Module | Description |
|--------|-------------|
| [modules/ecs](./modules/ecs/) | Agent pool, token, and ECS Fargate infrastructure |
| [modules/ecs-kms-key](./modules/ecs-kms-key/) | KMS key with policy for the ECS submodule |

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
