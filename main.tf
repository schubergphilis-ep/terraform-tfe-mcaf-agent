locals {
  account_id  = data.aws_caller_identity.current.account_id
  agent_name  = "${var.name}-agent"
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : module.kms_key[0].arn
  pool_name   = "${var.name}-pool"
  region      = data.aws_region.current.region
  vpc_id      = data.aws_subnet.selected.vpc_id

  # Created by the mcaf-fargate module; needed upfront in the KMS key policy.
  log_group_name = "/ecs/${var.name}"

  ecr_repository_prefix = coalesce(var.ecr_pull_through_cache.ecr_repository_prefix, var.name)

  # The pull through cache stores the image in the repository named after the rule prefix and the
  # upstream image. The prefix is read from the rule so the repository, and so the agent tasks,
  # are only created once the cache rule exists.
  ecr_repository_name = var.ecr_pull_through_cache.enabled ? "${module.ecr_pull_through_cache[0].ecr_pull_through_cache_rules["docker_hub"].ecr_repository_prefix}/${var.agent_image}" : null
  ecr_repository_arn  = var.ecr_pull_through_cache.enabled ? one(module.ecr[0].arns) : null
  ecr_repository_url  = var.ecr_pull_through_cache.enabled ? module.ecr[0].repository_url[local.ecr_repository_name] : null

  image = "${var.ecr_pull_through_cache.enabled ? local.ecr_repository_url : var.agent_image}:${var.agent_image_tag}"

  # Every AWS resource is tagged with the HCP Terraform organization of the agent pool; when
  # tfe_organization is null the pool uses the tfe provider organization.
  tags = merge(var.tags, {
    tfe-organization = coalesce(var.tfe_organization, tfe_agent_pool.default.organization)
  })

  # A token is only generated and stored when no existing secret is supplied.
  create_agent_token     = var.agent_token_secret_arn == null
  agent_token_secret_arn = local.create_agent_token ? aws_secretsmanager_secret.default[0].arn : var.agent_token_secret_arn

  agent_env_variables = merge(
    {
      TFC_AGENT_AUTO_UPDATE = "disabled"
      TFC_AGENT_LOG_LEVEL   = var.agent_log_level
      TFC_AGENT_NAME        = local.agent_name
      TFC_AGENT_SINGLE      = tostring(var.agent_single_execution)
    },
    var.agent_tfc_address != null ? { TFC_ADDRESS = var.agent_tfc_address } : {},
    var.agent_env_variables,
  )
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {
  region = var.region
}

# The VPC is derived from the subnets rather than passed in separately; all subnets must be in it.
data "aws_subnet" "selected" {
  region = var.region
  id     = var.subnet_ids[0]
}

# Only read for its postcondition: Terraform reads data sources even when nothing references them.
# tflint-ignore: terraform_unused_declarations
data "aws_subnets" "vpc" {
  region = var.region

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  lifecycle {
    postcondition {
      condition     = length(setsubtract(var.subnet_ids, self.ids)) == 0
      error_message = "All subnet_ids must be in the same VPC."
    }
  }
}

################################################################################
# HCP Terraform agent pool & token
################################################################################

resource "tfe_agent_pool" "default" {
  name                = local.pool_name
  organization        = var.tfe_organization
  organization_scoped = var.organization_scoped
}

resource "tfe_agent_pool_allowed_projects" "default" {
  count = length(var.allowed_project_ids) > 0 ? 1 : 0

  agent_pool_id       = tfe_agent_pool.default.id
  allowed_project_ids = var.allowed_project_ids
}

resource "tfe_agent_pool_allowed_workspaces" "default" {
  count = length(var.allowed_workspace_ids) > 0 ? 1 : 0

  agent_pool_id         = tfe_agent_pool.default.id
  allowed_workspace_ids = var.allowed_workspace_ids
}

resource "tfe_agent_token" "default" {
  count = local.create_agent_token ? 1 : 0

  agent_pool_id = tfe_agent_pool.default.id
  description   = "${local.agent_name} on ECS Fargate (${local.account_id}/${local.region})"
}

resource "aws_secretsmanager_secret" "default" {
  #checkov:skip=CKV2_AWS_57:The agent token is issued by HCP Terraform and cannot be rotated by Secrets Manager
  count = local.create_agent_token ? 1 : 0

  region                  = var.region
  name                    = "${var.name}/agent-token"
  description             = "HCP Terraform agent token for the ${local.pool_name} agent pool"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "default" {
  count = local.create_agent_token ? 1 : 0

  region        = var.region
  secret_id     = aws_secretsmanager_secret.default[0].id
  secret_string = tfe_agent_token.default[0].token
}

################################################################################
# KMS key (agent token secret, CloudWatch log group & ECR cache repository)
################################################################################

# Principals in the account can only use the key through the services the module uses it with,
# and only when their IAM policies allow it, instead of the key delegating all of KMS to IAM.
data "aws_iam_policy_document" "kms_key_policy" {
  count = var.kms_key_arn == null ? 1 : 0

  statement {
    sid = "AllowCloudWatchLogs"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    effect    = "Allow"
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}"]
    }
  }

  # Terraform stores the agent token and the agent role reads it through Secrets Manager.
  statement {
    sid = "AllowViaSecretsManager"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    effect    = "Allow"
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }

  # Creating the encrypted cache repository lets ECR create a grant for the key.
  statement {
    sid = "AllowViaEcr"
    actions = [
      "kms:CreateGrant",
      "kms:RetireGrant",
    ]
    effect    = "Allow"
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ecr.${local.region}.amazonaws.com"]
    }
  }
}

module "kms_key" {
  count = var.kms_key_arn == null ? 1 : 0

  source  = "schubergphilis-ep/mcaf-kms/aws"
  version = "~> 3.0.0"

  region      = var.region
  name        = coalesce(var.kms_key_configuration.name, var.name)
  description = "KMS key used by the ${var.name} HCP Terraform agent"
  tags        = local.tags

  default_policy = {
    iam_arns_administrator  = var.kms_key_configuration.iam_arns_administrator
    source_policy_documents = [data.aws_iam_policy_document.kms_key_policy[0].json]
  }
}

################################################################################
# ECR pull through cache for the agent image from Docker Hub
################################################################################

# Creates the pull through cache rule. The submodule always creates a repository creation
# template too, but it is unused: the cache repository below is managed by Terraform rather
# than created by ECR on first pull, so the template needs no KMS key, tags or IAM role.
module "ecr_pull_through_cache" {
  count = var.ecr_pull_through_cache.enabled ? 1 : 0

  source  = "schubergphilis-ep/mcaf-ecr/aws//modules/pull-through-cache"
  version = "~> 2.0.0"

  create_ecr_repository_creation_role = false
  image_tag_mutability                = "MUTABLE" # cached tags are refreshed from Docker Hub
  readonly_principals                 = [local.account_id]

  pull_through_cache_rules = {
    docker_hub = {
      credential_arn        = var.ecr_pull_through_cache.credential_arn
      description           = "Docker Hub cache for the ${var.name} HCP Terraform agent image"
      ecr_repository_prefix = local.ecr_repository_prefix
      upstream_registry_url = "registry-1.docker.io"
    }
  }
}

# The cache repository is created upfront so it is held in state: changing the KMS key replaces
# it, a destroy removes it, and the agent role does not need ecr:CreateRepository.
module "ecr" {
  #checkov:skip=CKV_AWS_51:Pull through cache refreshes cached tags from Docker Hub, which requires mutable tags
  count = var.ecr_pull_through_cache.enabled ? 1 : 0

  source  = "schubergphilis-ep/mcaf-ecr/aws"
  version = "~> 2.0.0"

  force_delete         = true # cached images can be pulled again from Docker Hub
  image_tag_mutability = "MUTABLE"
  kms_key_arn          = local.kms_key_arn
  repository_names     = [local.ecr_repository_name]
  tags                 = local.tags
}

################################################################################
# ECS Fargate cluster, service & agent task
################################################################################

data "aws_iam_policy_document" "role_policy" {
  source_policy_documents = var.role_policy_documents

  statement {
    sid       = "ReadAgentToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.agent_token_secret_arn]
  }

  statement {
    sid       = "DecryptAgentToken"
    actions   = ["kms:Decrypt"]
    resources = compact([local.kms_key_arn, var.agent_token_secret_kms_key_arn])
  }

  dynamic "statement" {
    for_each = var.ecr_pull_through_cache.enabled ? [true] : []

    # Pulling a tag that is not cached yet imports it from Docker Hub into the cache repository.
    content {
      sid       = "ImportAgentImage"
      actions   = ["ecr:BatchImportUpstreamImage"]
      resources = [local.ecr_repository_arn]
    }
  }
}

module "fargate" {
  #checkov:skip=CKV_AWS_336:The agent needs a writable root filesystem, see readonly_root_filesystem below
  source  = "schubergphilis/mcaf-fargate/aws"
  version = "~> 3.2.0"

  name                 = var.name
  architecture         = var.architecture
  cpu                  = var.cpu
  desired_count        = var.desired_count
  ecs_subnet_ids       = var.subnet_ids
  environment          = local.agent_env_variables
  image                = local.image
  kms_key_id           = local.kms_key_arn
  log_retention_days   = var.log_retention_days
  memory               = var.memory
  permissions_boundary = var.permissions_boundary
  region               = var.region
  role_policy          = data.aws_iam_policy_document.role_policy.json
  tags                 = local.tags
  vpc_id               = local.vpc_id

  # The agent writes Terraform binaries, providers and run data to its root filesystem and
  # mcaf-fargate cannot mount writable ephemeral volumes. See the README for policy impact.
  readonly_root_filesystem = false

  secrets = {
    TFC_AGENT_TOKEN = local.agent_token_secret_arn
  }
}
