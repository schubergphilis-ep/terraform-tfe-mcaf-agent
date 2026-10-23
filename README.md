# terraform-tfe-mcaf-agent

Terraform module to deploy HCP Terraform (or Terraform Enterprise) self-hosted agents as ECS Fargate tasks, so workspaces can run Terraform inside your own network and reach resources that are not publicly accessible.

The module creates:

- An HCP Terraform agent pool, optionally restricted to specific projects and/or workspaces, and an agent token, unless an existing token secret is provided.
- A Secrets Manager secret holding the agent token, unless an existing secret is provided.
- A KMS key encrypting the agent token secret and CloudWatch log group, unless an existing key is provided.
- An ECS cluster, service and task definition running the agents, using [mcaf-fargate](https://github.com/schubergphilis/terraform-aws-mcaf-fargate).
- Optionally, an ECR pull through cache for Docker Hub and the KMS encrypted ECR repository caching the agent image.

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

  kms_key_configuration = {
    iam_arns_administrator = ["arn:aws:iam::123456789012:role/terraform"]
  }
}
```

All AWS resource names are derived from `name`, so the module can be deployed multiple times in the same account and region by using a unique `name` per deployment. Point the agents at a Terraform Enterprise instance with `agent_tfc_address`.

### Bootstrapping

1. Apply the workspace that deploys this module using remote execution (HCP Terraform hosted runners).
2. Wait until the agents show as idle in the agent pool in HCP Terraform.
3. Switch the workspaces that need private network access to execution mode `agent` with this pool, using the `agent_pool_id` output.

Keep the workspace that deploys the agents on remote execution, otherwise a broken agent deployment can no longer be fixed by that workspace.

### Agent pool scope

By default the agent pool is not organization scoped: only the projects in `allowed_project_ids` and the workspaces in `allowed_workspace_ids` can use it, so at least one of them must be set. Setting `organization_scoped = true` allows every workspace in the organization to run on the agents, and therefore to use their network access and IAM role; both lists must then be empty.

### Network requirements

The agents run in the private subnets passed in `subnet_ids`, in the VPC those subnets belong to, and need outbound HTTPS access. When egress is filtered, for example by a firewall domain allow list, allow at least:

| Purpose | Destination |
|---------|-------------|
| HCP Terraform ([requirements](https://developer.hashicorp.com/terraform/cloud-docs/agents/requirements)) | `app.terraform.io`, `registry.terraform.io`, `releases.hashicorp.com`, `archivist.terraform.io` (443), `agents.terraform.io` (7146) |
| Container image from Docker Hub (without ECR pull through cache) | `registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com`, `production.cloudfront.docker.com` |
| Container image from ECR (with ECR pull through cache), unless VPC endpoints are used | `api.ecr.<region>.amazonaws.com`, `<account-id>.dkr.ecr.<region>.amazonaws.com`, `prod-<region>-starport-layer-bucket.s3.<region>.amazonaws.com` |
| Task startup, unless VPC endpoints are used | `secretsmanager.<region>.amazonaws.com`, `logs.<region>.amazonaws.com` |
| Terraform runs on the agents | All APIs used by the workspaces' providers, e.g. `sts.<region>.amazonaws.com` |

### ECR pull through cache for Docker Hub

Fargate does not cache images, and with `agent_single_execution` enabled a new task starts after every run, which can quickly hit Docker Hub pull rate limits. With `ecr_pull_through_cache` enabled, the module uses the [mcaf-ecr pull-through-cache](https://github.com/schubergphilis-ep/terraform-aws-mcaf-ecr/tree/main/modules/pull-through-cache) module to create an ECR pull through cache rule for Docker Hub, and the [mcaf-ecr](https://github.com/schubergphilis-ep/terraform-aws-mcaf-ecr) module to create the KMS encrypted cache repository `<ecr_repository_prefix>/<agent_image>`. The agents pull the image from that repository instead; on the first pull of a tag ECR fetches it from Docker Hub, and cached tags are refreshed at most once every 24 hours.

Docker Hub requires authentication for pull through caching. Create a Secrets Manager secret whose name starts with `ecr-pullthroughcache/`, containing a Docker Hub username and access token, and pass its ARN:

```json
{
  "username": "my-docker-hub-user",
  "accessToken": "dckr_pat_..."
}
```

```hcl
module "tfc_agent" {
  source  = "schubergphilis-ep/mcaf-agent/tfe"
  version = "~> 1.0"

  subnet_ids = data.aws_subnets.private.ids

  kms_key_configuration = {
    iam_arns_administrator = ["arn:aws:iam::123456789012:role/terraform"]
  }

  ecr_pull_through_cache = {
    enabled        = true
    credential_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:ecr-pullthroughcache/docker-hub-AbCdEf"
  }
}
```

Considerations:

- **Repository lifecycle:** the repository is managed by Terraform rather than created by ECR on the first pull, so it is replaced when the KMS key changes and removed, including its cached images, when the module is destroyed. Untagged images expire after one day. The pull-through-cache module always creates a repository creation template as well; it is unused, so it has no KMS key, tags or IAM role.
- **Agent permissions:** the agent role is granted `ecr:BatchImportUpstreamImage` on the agent image repository, so pulling a tag that is not cached yet imports it from Docker Hub.
- **First pull:** when ECR is reached through interface VPC endpoints, AWS notes that the first pull of an image may require a route to the internet.
- **Region:** the pull-through-cache module does not support the `region` argument, so the pull through cache cannot be combined with `region`; use a provider configured for the target region instead.
- **Naming:** pull through cache rules are unique per account and region on `ecr_repository_prefix`, which defaults to `name`.
- **Tags:** cached tags are refreshed from Docker Hub, so the repository uses mutable tags; pin `agent_image_tag` to a specific version to control which image runs.

### Security considerations

- **IAM role:** mcaf-fargate uses a single IAM role as task execution role and task role. Terraform runs on the agents can therefore use its permissions, including reading the agent token. Keep `role_policy_documents` minimal and let workspaces use [dynamic provider credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials) instead.
- **Read-only root filesystem:** the agent container runs with a writable root filesystem, because the agent downloads Terraform, providers and run data to disk and mcaf-fargate cannot mount writable ephemeral volumes. Policies requiring `readonlyRootFilesystem` (such as Sentinel or Security Hub controls) need an exception for this task definition. With `agent_single_execution` enabled (the default), the risk is reduced: every job runs in a new container started from the image and the container is discarded afterwards, so anything a job writes to the root filesystem, including any tampering with the agent or its binaries, cannot affect later jobs. Disabling `agent_single_execution` removes this mitigation, as one container then handles job after job.
- **Agent token:** a token generated by the module is stored in the Terraform state of the deploying workspace. Supply `agent_token_secret_arn` to keep it out of the state.

### Using an existing agent token secret

By default the module generates an agent token and stores it in a new Secrets Manager secret `<name>/agent-token`. To manage the token yourself, create an agent token for the pool, store it as plain text in a Secrets Manager secret and pass the secret ARN. The module then creates neither the token nor the secret, and only grants the agent role `secretsmanager:GetSecretValue` on it. If the secret is encrypted with a customer managed KMS key, also pass that key in `agent_token_secret_kms_key_arn`; its key policy must allow the agent role to use it.

```hcl
module "tfc_agent" {
  # ...
  agent_token_secret_arn         = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:tfc-agent/agent-token-AbCdEf"
  agent_token_secret_kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}
```

As the agent pool is created by this module, the token can only be created after a first apply; until the secret holds a valid token the agent tasks fail to register.

### KMS key

Either set `kms_key_configuration` to have the module create a KMS key, or `kms_key_arn` to use an existing one; exactly one of them is required.

The created key is administered by the principals in `kms_key_configuration.iam_arns_administrator`, which should include the role running Terraform. Its key policy does not delegate the key to IAM in general: principals in the account can only use it, when their IAM policies allow it, through Secrets Manager (for the agent token) and ECR (to create the encrypted cache repository), and the CloudWatch Logs service can use it for the `/ecs/<name>` log group.

When `kms_key_arn` is set, the key policy must allow the CloudWatch Logs service to use the key for the `/ecs/<name>` log group, and must allow IAM policies in the account to grant `kms:Decrypt` to the agent role. With the ECR pull through cache enabled, the role running Terraform must also be allowed to use the key for the encrypted repository (`kms:CreateGrant`, `kms:DescribeKey`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.10 |
| <a name="requirement_tfe"></a> [tfe](#requirement\_tfe) | >= 0.70 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.10 |
| <a name="provider_tfe"></a> [tfe](#provider\_tfe) | >= 0.70 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ecr"></a> [ecr](#module\_ecr) | schubergphilis-ep/mcaf-ecr/aws | ~> 2.1.0 |
| <a name="module_ecr_pull_through_cache"></a> [ecr\_pull\_through\_cache](#module\_ecr\_pull\_through\_cache) | schubergphilis-ep/mcaf-ecr/aws//modules/pull-through-cache | ~> 2.1.0 |
| <a name="module_fargate"></a> [fargate](#module\_fargate) | schubergphilis/mcaf-fargate/aws | ~> 3.2.0 |
| <a name="module_kms_key"></a> [kms\_key](#module\_kms\_key) | schubergphilis-ep/mcaf-kms/aws | ~> 3.0.0 |

## Resources

| Name | Type |
|------|------|
| [aws_secretsmanager_secret.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [tfe_agent_pool.default](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/agent_pool) | resource |
| [tfe_agent_pool_allowed_projects.default](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/agent_pool_allowed_projects) | resource |
| [tfe_agent_pool_allowed_workspaces.default](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/agent_pool_allowed_workspaces) | resource |
| [tfe_agent_token.default](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/agent_token) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.kms_key_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnets.vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | IDs of the private subnets to run the agent tasks in; they must all be in the same VPC, which is used for the agent tasks. | `list(string)` | n/a | yes |
| <a name="input_agent_env_variables"></a> [agent\_env\_variables](#input\_agent\_env\_variables) | Additional environment variables for the agent container, e.g. `TFC_AGENT_*` settings. Overrides the module defaults. | `map(string)` | `{}` | no |
| <a name="input_agent_image"></a> [agent\_image](#input\_agent\_image) | Container image of the HCP Terraform agent, without tag. When `ecr_pull_through_cache` is enabled, this is the Docker Hub repository to cache. | `string` | `"hashicorp/tfc-agent"` | no |
| <a name="input_agent_image_tag"></a> [agent\_image\_tag](#input\_agent\_image\_tag) | Tag of the HCP Terraform agent container image. | `string` | `"latest"` | no |
| <a name="input_agent_log_level"></a> [agent\_log\_level](#input\_agent\_log\_level) | Log level of the HCP Terraform agent. | `string` | `"info"` | no |
| <a name="input_agent_single_execution"></a> [agent\_single\_execution](#input\_agent\_single\_execution) | Stop the agent after each run so every run starts in a fresh container; ECS replaces the stopped task. | `bool` | `true` | no |
| <a name="input_agent_tfc_address"></a> [agent\_tfc\_address](#input\_agent\_tfc\_address) | Address of the HCP Terraform or Terraform Enterprise instance; if null the agent default (https://app.terraform.io) is used. | `string` | `null` | no |
| <a name="input_agent_token_secret_arn"></a> [agent\_token\_secret\_arn](#input\_agent\_token\_secret\_arn) | ARN of an existing Secrets Manager secret holding the agent token as plain text; if null a token is generated and stored in a new secret. | `string` | `null` | no |
| <a name="input_agent_token_secret_kms_key_arn"></a> [agent\_token\_secret\_kms\_key\_arn](#input\_agent\_token\_secret\_kms\_key\_arn) | ARN of the customer managed KMS key encrypting the secret in `agent_token_secret_arn`, so the agent role can decrypt it. Not needed when the secret uses the AWS managed key. | `string` | `null` | no |
| <a name="input_allowed_project_ids"></a> [allowed\_project\_ids](#input\_allowed\_project\_ids) | IDs of the HCP Terraform projects whose workspaces may use the agent pool. When `organization_scoped` is false at least one project or workspace is required; when it is true this must be empty. | `set(string)` | `[]` | no |
| <a name="input_allowed_workspace_ids"></a> [allowed\_workspace\_ids](#input\_allowed\_workspace\_ids) | IDs of the HCP Terraform workspaces that may use the agent pool. When `organization_scoped` is false at least one project or workspace is required; when it is true this must be empty. | `set(string)` | `[]` | no |
| <a name="input_architecture"></a> [architecture](#input\_architecture) | Instruction set architecture of the Fargate task. | `string` | `"x86_64"` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Fargate CPU units per agent task (1 vCPU = 1024 CPU units). | `number` | `1024` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Number of agent tasks to run; each agent handles one run at a time. | `number` | `1` | no |
| <a name="input_ecr_pull_through_cache"></a> [ecr\_pull\_through\_cache](#input\_ecr\_pull\_through\_cache) | Pull the agent image through an ECR pull through cache for Docker Hub instead of directly from Docker Hub. `credential_arn` is the ARN of a Secrets Manager secret, prefixed with `ecr-pullthroughcache/`, holding Docker Hub credentials. `ecr_repository_prefix` defaults to `name`. | <pre>object({<br/>    enabled               = optional(bool, false)<br/>    credential_arn        = optional(string)<br/>    ecr_repository_prefix = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of an existing KMS key to encrypt the agent token secret, CloudWatch log group and ECR cache repository if enabled; if null a key is created using `kms_key_configuration`. | `string` | `null` | no |
| <a name="input_kms_key_configuration"></a> [kms\_key\_configuration](#input\_kms\_key\_configuration) | Configuration of the KMS key created by this module. Only applicable when `kms_key_arn` is null. `iam_arns_administrator` grants permissions to manage the key (no cryptographic use) and should include the role running Terraform. `name` sets the alias/name of the created key and defaults to `name`. | <pre>object({<br/>    iam_arns_administrator = list(string)<br/>    name                   = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention in days of the agent CloudWatch log group. | `number` | `365` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Fargate memory (in MiB) per agent task. | `number` | `2048` | no |
| <a name="input_name"></a> [name](#input\_name) | Name used for the AWS resources; must be unique per AWS account and region. | `string` | `"tfc-agent"` | no |
| <a name="input_organization_scoped"></a> [organization\_scoped](#input\_organization\_scoped) | Allow all workspaces in the organization to use the agent pool instead of only the allowed projects and workspaces. | `bool` | `false` | no |
| <a name="input_permissions_boundary"></a> [permissions\_boundary](#input\_permissions\_boundary) | ARN of the permissions boundary to set on the agent IAM role. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | The AWS region where resources will be created; if omitted the default provider region is used. | `string` | `null` | no |
| <a name="input_role_policy_documents"></a> [role\_policy\_documents](#input\_role\_policy\_documents) | Additional IAM policy documents (JSON) merged into the agent role policy. This role is also used by Terraform runs on the agent. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the AWS resources. A `tfe-organization` tag with the HCP Terraform organization is always added. | `map(string)` | `{}` | no |
| <a name="input_tfe_organization"></a> [tfe\_organization](#input\_tfe\_organization) | Name of the HCP Terraform organization | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_agent_pool_id"></a> [agent\_pool\_id](#output\_agent\_pool\_id) | ID of the HCP Terraform agent pool |
| <a name="output_agent_pool_name"></a> [agent\_pool\_name](#output\_agent\_pool\_name) | Name of the HCP Terraform agent pool |
| <a name="output_agent_token_secret_arn"></a> [agent\_token\_secret\_arn](#output\_agent\_token\_secret\_arn) | ARN of the Secrets Manager secret holding the agent token, either created or supplied through `agent_token_secret_arn` |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the ECS cluster |
| <a name="output_ecr_repository_url"></a> [ecr\_repository\_url](#output\_ecr\_repository\_url) | URL of the ECR repository caching the agent image, if the pull through cache is enabled |
| <a name="output_ecs_service_arn"></a> [ecs\_service\_arn](#output\_ecs\_service\_arn) | ARN of the ECS service running the agents |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key encrypting the created agent token secret and logs |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IAM role used by the agent tasks and the Terraform runs on them |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the agent security group |
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
