locals {
  account_id  = data.aws_caller_identity.current.account_id
  agent_name  = coalesce(var.agent_name, var.name)
  create_kms  = var.kms_key_arn == null
  kms_key_arn = local.create_kms ? module.kms[0].arn : var.kms_key_arn
  pool_name   = coalesce(var.pool_name, var.name)
  region      = data.aws_region.current.region

  # Created by the mcaf-fargate module; needed upfront in the KMS key policy.
  log_group_name = "/ecs/${var.name}"

  ecr_pull_through_cache_enabled = var.ecr_pull_through_cache.enabled
  ecr_repository_prefix          = coalesce(var.ecr_pull_through_cache.ecr_repository_prefix, var.name)
  ecr_repository_name            = local.ecr_pull_through_cache_enabled ? "${aws_ecr_pull_through_cache_rule.default[0].ecr_repository_prefix}/${var.agent_image}" : null

  image = "${local.ecr_pull_through_cache_enabled ? module.ecr[0].repository_url[local.ecr_repository_name] : var.agent_image}:${var.agent_image_tag}"

  environment = merge(
    {
      TFC_AGENT_AUTO_UPDATE = "disabled"
      TFC_AGENT_LOG_LEVEL   = var.agent_log_level
      TFC_AGENT_NAME        = local.agent_name
      TFC_AGENT_SINGLE      = tostring(var.agent_single_execution)
    },
    var.tfc_address != null ? { TFC_ADDRESS = var.tfc_address } : {},
    var.environment,
  )
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {
  region = var.region
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
  agent_pool_id = tfe_agent_pool.default.id
  description   = "${local.agent_name} on ECS Fargate (${local.account_id}/${local.region})"
}

resource "aws_ssm_parameter" "default" {
  region = var.region
  name   = "/${var.name}/token"
  type   = "SecureString"
  value  = tfe_agent_token.default.token
  key_id = local.kms_key_arn
  tags   = var.tags
}

################################################################################
# KMS key (SSM parameter & CloudWatch log group)
################################################################################

data "aws_iam_session_context" "current" {
  count = local.create_kms && length(var.kms_key_administrator_arns) == 0 ? 1 : 0

  arn = data.aws_caller_identity.current.arn
}

data "aws_iam_policy_document" "kms_key_policy" {
  count = local.create_kms ? 1 : 0

  # The default mcaf-kms policy only allows the root principal itself; delegating to IAM lets
  # the agent role decrypt the token through its IAM policy without a cycle on the role ARN.
  statement {
    sid       = "AllowIamDelegation"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "AllowCloudWatchLogs"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
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
}

module "kms" {
  count = local.create_kms ? 1 : 0

  source  = "schubergphilis-ep/mcaf-kms/aws"
  version = "~> 3.0.0"

  name        = var.name
  description = "KMS key used by the ${var.name} HCP Terraform agent"
  region      = var.region
  tags        = var.tags

  default_policy = {
    iam_arns_administrator  = length(var.kms_key_administrator_arns) > 0 ? var.kms_key_administrator_arns : [data.aws_iam_session_context.current[0].issuer_arn]
    source_policy_documents = [data.aws_iam_policy_document.kms_key_policy[0].json]
  }
}

################################################################################
# ECR pull through cache for the agent image from Docker Hub
################################################################################

resource "aws_ecr_pull_through_cache_rule" "default" {
  count = local.ecr_pull_through_cache_enabled ? 1 : 0

  credential_arn        = var.ecr_pull_through_cache.credential_arn
  ecr_repository_prefix = local.ecr_repository_prefix
  upstream_registry_url = "registry-1.docker.io"

  lifecycle {
    precondition {
      condition     = var.region == null
      error_message = "The ECR pull through cache is created in the provider region, as mcaf-ecr does not support the region argument; unset region or use a provider for that region."
    }
  }
}

# Created upfront, rather than by ECR on first pull, so it is KMS encrypted and the agent
# role does not need ecr:CreateRepository.
module "ecr" {
  #checkov:skip=CKV_AWS_51:Pull through cache refreshes cached tags from Docker Hub, which requires mutable tags
  count = local.ecr_pull_through_cache_enabled ? 1 : 0

  source  = "schubergphilis-ep/mcaf-ecr/aws"
  version = "~> 2.0.0"

  force_delete         = true # cached images can be pulled again from Docker Hub
  image_tag_mutability = "MUTABLE"
  kms_key_arn          = local.kms_key_arn
  repository_names     = [local.ecr_repository_name]
  tags                 = var.tags

  custom_lifecycle_policy_rules = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last ${var.ecr_pull_through_cache.image_count} images"
        action       = { type = "expire" }

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_pull_through_cache.image_count
        }
      }
    ]
  })
}

################################################################################
# ECS Fargate cluster, service & agent task
################################################################################

data "aws_iam_policy_document" "role_policy" {
  source_policy_documents = var.role_policy_documents

  statement {
    sid       = "ReadAgentToken"
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.default.arn]
  }

  statement {
    sid       = "DecryptAgentToken"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arn]
  }

  dynamic "statement" {
    for_each = local.ecr_pull_through_cache_enabled ? [true] : []

    content {
      sid       = "ImportAgentImage"
      actions   = ["ecr:BatchImportUpstreamImage"]
      resources = module.ecr[0].arns
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
  environment          = local.environment
  image                = local.image
  kms_key_id           = local.kms_key_arn
  log_retention_days   = var.log_retention_days
  memory               = var.memory
  permissions_boundary = var.permissions_boundary
  region               = var.region
  role_policy          = data.aws_iam_policy_document.role_policy.json
  tags                 = var.tags
  vpc_id               = var.vpc_id

  # The agent writes Terraform binaries, providers and run data to its root filesystem and
  # mcaf-fargate cannot mount writable ephemeral volumes. See the README for policy impact.
  readonly_root_filesystem = false

  secrets = {
    TFC_AGENT_TOKEN = aws_ssm_parameter.default.arn
  }
}
