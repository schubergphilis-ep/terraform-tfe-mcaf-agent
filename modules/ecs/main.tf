################################################################################
# TFE Agent Pool & Token
################################################################################

resource "tfe_agent_pool" "default" {
  name                = var.pool_name
  organization        = var.tfe_organization
  organization_scoped = false
}

resource "tfe_agent_token" "default" {
  agent_pool_id = tfe_agent_pool.default.id
  description   = "${var.pool_name} agent token"
}

resource "tfe_workspace_settings" "default" {
  for_each = var.workspace_ids

  workspace_id   = each.value
  execution_mode = "agent"
  agent_pool_id  = tfe_agent_pool.default.id
}

################################################################################
# SSM Parameter (agent token)
################################################################################

resource "aws_ssm_parameter" "default" {
  name   = "/${var.name}/tfc-agent-token"
  type   = "SecureString"
  value  = tfe_agent_token.default.token
  key_id = var.kms_key_arn
  tags   = var.tags
}

################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "default" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

################################################################################
# ECS Cluster
################################################################################

locals {
  create_cluster = var.ecs_cluster_arn == null
  cluster_arn    = local.create_cluster ? aws_ecs_cluster.default[0].arn : var.ecs_cluster_arn
}

resource "aws_ecs_cluster" "default" {
  count = local.create_cluster ? 1 : 0

  name = var.name
  tags = var.tags

  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.default.name
      }
    }
  }
}

################################################################################
# IAM — Execution Role
################################################################################

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPull"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "SSMRead"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]

    resources = [aws_ssm_parameter.default.arn]
  }

  statement {
    sid       = "KMSDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.default.arn}:*"]
  }
}

module "execution_role" {
  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.5.3"

  name                  = "${var.name}-execution"
  path                  = var.iam_path
  permissions_boundary  = var.permissions_boundary
  postfix               = false
  principal_type        = "Service"
  principal_identifiers = ["ecs-tasks.amazonaws.com"]
  create_policy         = true
  role_policy           = data.aws_iam_policy_document.execution.json
  tags                  = var.tags
}

################################################################################
# IAM — Task Role
################################################################################

module "task_role" {
  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.5.3"

  name                  = "${var.name}-task"
  path                  = var.iam_path
  permissions_boundary  = var.permissions_boundary
  postfix               = false
  principal_type        = "Service"
  principal_identifiers = ["ecs-tasks.amazonaws.com"]
  policy_arns           = var.task_role_policy_arns
  create_policy         = false
  tags                  = var.tags
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "default" {
  name_prefix = "${var.name}-"
  vpc_id      = var.vpc_id
  description = "TFC agent egress-only security group"
  tags        = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.default.id
  description       = "HTTPS outbound"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
  tags              = var.tags
}

resource "aws_vpc_security_group_egress_rule" "tfe_agents" {
  security_group_id = aws_security_group.default.id
  description       = "HCP Terraform agent communication"
  ip_protocol       = "tcp"
  from_port         = 7146
  to_port           = 7146
  cidr_ipv4         = "0.0.0.0/0"
  tags              = var.tags
}

################################################################################
# ECS Task Definition & Service
################################################################################

data "aws_region" "current" {}

resource "aws_ecs_task_definition" "default" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = module.execution_role.arn
  task_role_arn            = module.task_role.arn
  tags                     = var.tags

  container_definitions = jsonencode([
    {
      name      = "tfc-agent"
      image     = "${var.agent_image}:${var.agent_image_tag}"
      essential = true

      environment = [
        { name = "TFC_AGENT_SINGLE", value = "true" },
        { name = "TFC_AGENT_NAME", value = var.agent_name },
        { name = "TFC_AGENT_AUTO_UPDATE", value = "disabled" },
        { name = "TFC_AGENT_LOG_LEVEL", value = var.agent_log_level },
      ]

      secrets = [
        {
          name      = "TFC_AGENT_TOKEN"
          valueFrom = aws_ssm_parameter.default.arn
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.default.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "tfc-agent"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "default" {
  name            = var.name
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.default.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  tags            = var.tags

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.default.id]
  }
}
