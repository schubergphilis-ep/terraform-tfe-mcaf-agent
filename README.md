# terraform-tfe-mcaf-agent

Terraform module to deploy HCP Terraform (or Terraform Enterprise) self-hosted agents as ECS Fargate tasks, so workspaces can run Terraform inside your own network and reach resources that are not publicly accessible.

The module creates:

- An HCP Terraform agent pool, optionally restricted to specific projects and/or workspaces, and an agent token.
- An SSM `SecureString` parameter holding the agent token.
- A KMS key encrypting the SSM parameter and CloudWatch log group, unless an existing key is provided.
- An ECS cluster, service and task definition running the agents, using [mcaf-fargate](https://github.com/schubergphilis/terraform-aws-mcaf-fargate).

## Usage

The module needs both an `aws` and a `tfe` provider. The `tfe` provider token must be allowed to manage agent pools in the organization.

```hcl
provider "tfe" {
  organization = "my-org"
}

module "tfc_agent" {
  source  = "schubergphilis-ep/mcaf-agent/tfe"
  version = "~> 1.0"

  allowed_project_ids = ["prj-AbCdEfGhIjKlMnOp"]
  subnet_ids          = data.aws_subnets.private.ids
  vpc_id              = data.aws_vpc.default.id
}
```

All AWS resource names are derived from `name`, so the module can be deployed multiple times in the same account and region by using a unique `name` per deployment. Point the agents at a Terraform Enterprise instance with `tfc_address`.

### Bootstrapping

1. Apply the workspace that deploys this module using remote execution (HCP Terraform hosted runners).
2. Wait until the agents show as idle in the agent pool in HCP Terraform.
3. Switch the workspaces that need private network access to execution mode `agent` with this pool, using the `agent_pool_id` output.

Keep the workspace that deploys the agents on remote execution, otherwise a broken agent deployment can no longer be fixed by that workspace.

### Agent pool scope

By default the agent pool is not organization scoped: only the projects in `allowed_project_ids` and the workspaces in `allowed_workspace_ids` can use it. Setting `organization_scoped = true` allows every workspace in the organization to run on the agents, and therefore to use their network access and IAM role.

### Network requirements

The agents run in the private subnets passed in `subnet_ids` and need outbound HTTPS access. When egress is filtered, for example by a firewall domain allow list, allow at least:

| Purpose | Destination |
|---------|-------------|
| HCP Terraform ([requirements](https://developer.hashicorp.com/terraform/cloud-docs/agents/requirements)) | `app.terraform.io`, `registry.terraform.io`, `releases.hashicorp.com`, `archivist.terraform.io` (443), `agents.terraform.io` (7146) |
| Container image from Docker Hub | `registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com`, `production.cloudfront.docker.com` |
| Task startup, unless VPC endpoints are used | `ssm.<region>.amazonaws.com`, `logs.<region>.amazonaws.com` |
| Terraform runs on the agents | All APIs used by the workspaces' providers, e.g. `sts.<region>.amazonaws.com` |

Fargate does not cache images, and with `agent_single_execution` enabled a new task starts after every run. To avoid Docker Hub pull rate limits, consider mirroring the image to ECR and setting `agent_image`.

### Security considerations

- **IAM role:** mcaf-fargate uses a single IAM role as task execution role and task role. Terraform runs on the agents can therefore use its permissions, including reading the agent token. Keep `role_policy_documents` minimal and let workspaces use [dynamic provider credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials) instead.
- **Read-only root filesystem:** the agent container runs with a writable root filesystem, because the agent downloads Terraform, providers and run data to disk and mcaf-fargate cannot mount writable ephemeral volumes. Policies requiring `readonlyRootFilesystem` (such as Sentinel or Security Hub controls) need an exception for this task definition.
- **Agent token:** the agent token is stored in the Terraform state of the deploying workspace.

### Using an existing KMS key

When `kms_key_arn` is set, the key policy must allow the CloudWatch Logs service to use the key for the `/ecs/<name>` log group, and must allow IAM policies in the account to grant `kms:Decrypt` to the agent role.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |
| <a name="requirement_tfe"></a> [tfe](#requirement\_tfe) | >= 0.70 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |
| <a name="provider_tfe"></a> [tfe](#provider\_tfe) | >= 0.70 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_fargate"></a> [fargate](#module\_fargate) | schubergphilis/mcaf-fargate/aws | ~> 3.2.0 |
| <a name="module_kms"></a> [kms](#module\_kms) | schubergphilis-ep/mcaf-kms/aws | ~> 3.0.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ssm_parameter.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [tfe_agent_pool.default](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/agent_pool) | resource |
| [tfe_agent_pool_allowed_projects.default](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/agent_pool_allowed_projects) | resource |
| [tfe_agent_pool_allowed_workspaces.default](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/agent_pool_allowed_workspaces) | resource |
| [tfe_agent_token.default](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/agent_token) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.kms_key_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_session_context.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_session_context) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_agent_image"></a> [agent\_image](#input\_agent\_image) | Container image of the HCP Terraform agent, without tag. | `string` | `"hashicorp/tfc-agent"` | no |
| <a name="input_agent_image_tag"></a> [agent\_image\_tag](#input\_agent\_image\_tag) | Tag of the HCP Terraform agent container image. | `string` | `"1.28"` | no |
| <a name="input_agent_log_level"></a> [agent\_log\_level](#input\_agent\_log\_level) | Log level of the HCP Terraform agent. | `string` | `"info"` | no |
| <a name="input_agent_name"></a> [agent\_name](#input\_agent\_name) | Name of the agents as shown in HCP Terraform; defaults to `name`. | `string` | `null` | no |
| <a name="input_agent_single_execution"></a> [agent\_single\_execution](#input\_agent\_single\_execution) | Stop the agent after each run so every run starts in a fresh container; ECS replaces the stopped task. | `bool` | `true` | no |
| <a name="input_allowed_project_ids"></a> [allowed\_project\_ids](#input\_allowed\_project\_ids) | IDs of the HCP Terraform projects whose workspaces may use the agent pool. Only used when `organization_scoped` is false. | `set(string)` | `[]` | no |
| <a name="input_allowed_workspace_ids"></a> [allowed\_workspace\_ids](#input\_allowed\_workspace\_ids) | IDs of the HCP Terraform workspaces that may use the agent pool. Only used when `organization_scoped` is false. | `set(string)` | `[]` | no |
| <a name="input_architecture"></a> [architecture](#input\_architecture) | Instruction set architecture of the Fargate task. | `string` | `"x86_64"` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Fargate CPU units per agent task (1 vCPU = 1024 CPU units). | `number` | `1024` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Number of agent tasks to run; each agent handles one run at a time. | `number` | `1` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Additional environment variables for the agent container, e.g. `TFC_AGENT_*` settings. Overrides the module defaults. | `map(string)` | `{}` | no |
| <a name="input_kms_key_administrator_arns"></a> [kms\_key\_administrator\_arns](#input\_kms\_key\_administrator\_arns) | IAM ARNs allowed to administer the created KMS key; defaults to the role running Terraform. Only used when `kms_key_arn` is not set. | `list(string)` | `[]` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of an existing KMS key to encrypt the SSM parameter and CloudWatch log group; if null a key is created. | `string` | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention in days of the agent CloudWatch log group. | `number` | `365` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Fargate memory (in MiB) per agent task. | `number` | `2048` | no |
| <a name="input_name"></a> [name](#input\_name) | Name used for the AWS resources; must be unique per AWS account and region. | `string` | `"tfc-agent"` | no |
| <a name="input_organization_scoped"></a> [organization\_scoped](#input\_organization\_scoped) | Allow all workspaces in the organization to use the agent pool instead of only the allowed projects and workspaces. | `bool` | `false` | no |
| <a name="input_permissions_boundary"></a> [permissions\_boundary](#input\_permissions\_boundary) | ARN of the permissions boundary to set on the agent IAM role. | `string` | `null` | no |
| <a name="input_pool_name"></a> [pool\_name](#input\_pool\_name) | Name of the HCP Terraform agent pool; defaults to `name`. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | The AWS region where resources will be created; if omitted the default provider region is used. | `string` | `null` | no |
| <a name="input_role_policy_documents"></a> [role\_policy\_documents](#input\_role\_policy\_documents) | Additional IAM policy documents (JSON) merged into the agent role policy. This role is also used by Terraform runs on the agent. | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | IDs of the private subnets to run the agent tasks in. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the AWS resources. | `map(string)` | `{}` | no |
| <a name="input_tfc_address"></a> [tfc\_address](#input\_tfc\_address) | Address of the HCP Terraform or Terraform Enterprise instance; if null the agent default (https://app.terraform.io) is used. | `string` | `null` | no |
| <a name="input_tfe_organization"></a> [tfe\_organization](#input\_tfe\_organization) | Name of the HCP Terraform organization; if null the tfe provider organization is used. | `string` | `null` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC to run the agent tasks in. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_agent_pool_id"></a> [agent\_pool\_id](#output\_agent\_pool\_id) | ID of the HCP Terraform agent pool |
| <a name="output_agent_pool_name"></a> [agent\_pool\_name](#output\_agent\_pool\_name) | Name of the HCP Terraform agent pool |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the ECS cluster |
| <a name="output_ecs_service_arn"></a> [ecs\_service\_arn](#output\_ecs\_service\_arn) | ARN of the ECS service running the agents |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key encrypting the agent token and logs |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IAM role used by the agent tasks and the Terraform runs on them |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the agent security group |
| <a name="output_ssm_parameter_arn"></a> [ssm\_parameter\_arn](#output\_ssm\_parameter\_arn) | ARN of the SSM parameter holding the agent token |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the agent task definition |
<!-- END_TF_DOCS -->

## License

**Copyright:** Schuberg Philis

```text
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
