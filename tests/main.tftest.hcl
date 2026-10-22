# Mock providers, otherwise Terraform tries to connect to the service APIs.
# The account ID, region and session issuer are interpolated into ARNs and policies,
# so they need syntactically valid mocked values rather than generated ones.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/terraform/run"
    }
  }

  # Policy documents are passed between modules and validated as JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:role/terraform"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:tfc-agent/agent-token-AbCdEf"
    }
  }
}

mock_provider "tfe" {}

variables {
  subnet_ids       = ["subnet-0123456789abcdef0"]
  tfe_organization = "my-org"
  vpc_id           = "vpc-0123456789abcdef0"
}

# The default test checks the module logic using its default values.
run "default" {
  command = plan

  assert {
    condition     = tfe_agent_pool.default.name == "tfc-agent-pool" && tfe_agent_pool.default.organization_scoped == false
    error_message = "Agent pool should be named after the module name and not be organization scoped"
  }

  assert {
    condition     = length(tfe_agent_pool_allowed_projects.default) == 0 && length(tfe_agent_pool_allowed_workspaces.default) == 0
    error_message = "No allowed projects or workspaces should be configured by default"
  }

  assert {
    condition     = length(module.kms) == 1 && length(data.aws_iam_session_context.current) == 1
    error_message = "A KMS key administered by the Terraform role should be created by default"
  }

  assert {
    condition     = length(tfe_agent_token.default) == 1 && aws_secretsmanager_secret.default[0].name == "tfc-agent/agent-token" && length(aws_secretsmanager_secret_version.default) == 1
    error_message = "Agent token should be generated and stored in a Secrets Manager secret under the module name"
  }

  assert {
    condition = local.env_variables == {
      TFC_AGENT_AUTO_UPDATE = "disabled"
      TFC_AGENT_LOG_LEVEL   = "info"
      TFC_AGENT_NAME        = "tfc-agent-agent"
      TFC_AGENT_SINGLE      = "true"
    }
    error_message = "Unexpected default agent environment"
  }

  assert {
    condition     = length(module.ecr_pull_through_cache) == 0 && length(module.ecr) == 0 && local.ecr_repository_url == null
    error_message = "No ECR pull through cache should be created by default"
  }

  assert {
    condition     = local.tags == { tfe-organization = "my-org" }
    error_message = "AWS resources should be tagged with the HCP Terraform organization"
  }

  assert {
    condition     = local.image == "hashicorp/tfc-agent:latest"
    error_message = "Agent image should be pulled from Docker Hub by default"
  }
}

run "ecr_pull_through_cache" {
  command = plan

  # The repository ARN and URL are only known after apply.
  override_module {
    target = module.ecr
    outputs = {
      arns           = ["arn:aws:ecr:eu-central-1:123456789012:repository/tfc-agent/hashicorp/tfc-agent"]
      repository_url = { "tfc-agent/hashicorp/tfc-agent" = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/tfc-agent/hashicorp/tfc-agent" }
    }
  }

  variables {
    ecr_pull_through_cache = {
      enabled        = true
      credential_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:ecr-pullthroughcache/docker-hub-AbCdEf"
    }
  }

  assert {
    condition     = module.ecr_pull_through_cache[0].ecr_pull_through_cache_rules["docker_hub"].ecr_repository_prefix == "tfc-agent" && module.ecr_pull_through_cache[0].ecr_pull_through_cache_rules["docker_hub"].upstream_registry_url == "registry-1.docker.io"
    error_message = "Pull through cache rule for Docker Hub should use the module name as prefix"
  }

  assert {
    condition     = local.ecr_repository_name == "tfc-agent/hashicorp/tfc-agent" && length(module.ecr) == 1
    error_message = "The cache repository of the agent image should be created by Terraform"
  }

  assert {
    condition     = local.ecr_repository_arn == "arn:aws:ecr:eu-central-1:123456789012:repository/tfc-agent/hashicorp/tfc-agent"
    error_message = "Agent role permissions should be scoped to the cache repository of the agent image"
  }

  assert {
    condition     = local.image == "123456789012.dkr.ecr.eu-central-1.amazonaws.com/tfc-agent/hashicorp/tfc-agent:latest"
    error_message = "Agent image should be pulled from the ECR cache repository"
  }
}

run "ecr_pull_through_cache_custom_prefix" {
  command = plan

  variables {
    ecr_pull_through_cache = {
      enabled               = true
      credential_arn        = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:ecr-pullthroughcache/docker-hub-AbCdEf"
      ecr_repository_prefix = "docker-hub"
    }
  }

  assert {
    condition     = local.ecr_repository_name == "docker-hub/hashicorp/tfc-agent"
    error_message = "Cache repository should use the custom prefix"
  }
}

run "ecr_pull_through_cache_with_region" {
  command = plan

  variables {
    region = "eu-west-1"

    ecr_pull_through_cache = {
      enabled        = true
      credential_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:ecr-pullthroughcache/docker-hub-AbCdEf"
    }
  }

  expect_failures = [var.ecr_pull_through_cache]
}

run "ecr_pull_through_cache_without_credential" {
  command = plan

  variables {
    ecr_pull_through_cache = {
      enabled = true
    }
  }

  expect_failures = [var.ecr_pull_through_cache]
}

run "ecr_pull_through_cache_invalid_credential" {
  command = plan

  variables {
    ecr_pull_through_cache = {
      enabled        = true
      credential_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:docker-hub-AbCdEf"
    }
  }

  expect_failures = [var.ecr_pull_through_cache]
}

run "existing_kms_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(module.kms) == 0 && length(data.aws_iam_session_context.current) == 0
    error_message = "No KMS key should be created when kms_key_arn is set"
  }

  assert {
    condition     = aws_secretsmanager_secret.default[0].kms_key_id == var.kms_key_arn
    error_message = "Agent token secret should be encrypted with the provided KMS key"
  }
}

run "kms_key_administrators" {
  command = plan

  variables {
    kms_key_administrator_arns = ["arn:aws:iam::123456789012:role/admin"]
  }

  assert {
    condition     = length(module.kms) == 1 && length(data.aws_iam_session_context.current) == 0
    error_message = "Session context should not be looked up when administrators are provided"
  }
}

run "existing_agent_token_secret" {
  command = plan

  variables {
    agent_token_secret_arn         = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:tfc-agent/existing-token-AbCdEf"
    agent_token_secret_kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = length(tfe_agent_token.default) == 0 && length(aws_secretsmanager_secret.default) == 0 && length(aws_secretsmanager_secret_version.default) == 0
    error_message = "No agent token or secret should be created when agent_token_secret_arn is set"
  }

  assert {
    condition     = local.agent_token_secret_arn == var.agent_token_secret_arn
    error_message = "Agent should read the token from the supplied secret"
  }
}

run "invalid_agent_token_secret_arn" {
  command = plan

  variables {
    agent_token_secret_arn = "arn:aws:ssm:eu-central-1:123456789012:parameter/tfc-agent/token" #checkov:skip=CKV_SECRET_6:arn incorrectly detected as a secret
  }

  expect_failures = [var.agent_token_secret_arn]
}

run "allowed_projects_and_workspaces" {
  command = plan

  variables {
    allowed_project_ids   = ["prj-AbCdEfGhIjKlMnOp"]
    allowed_workspace_ids = ["ws-AbCdEfGhIjKlMnOp"]
  }

  assert {
    condition     = length(tfe_agent_pool_allowed_projects.default) == 1 && length(tfe_agent_pool_allowed_workspaces.default) == 1
    error_message = "Allowed projects and workspaces should be configured"
  }
}

run "custom_names_and_environment" {
  command = plan

  variables {
    name                   = "network"
    agent_single_execution = false
    tfc_address            = "https://tfe.example.com"

    env_variables = {
      TFC_AGENT_LOG_LEVEL = "debug"
      HTTPS_PROXY         = "http://proxy.example.com:3128"
    }
  }

  assert {
    condition     = tfe_agent_pool.default.name == "network-pool" && aws_secretsmanager_secret.default[0].name == "network/agent-token"
    error_message = "Pool and resource names should be derived from the module name"
  }

  assert {
    condition = local.env_variables == {
      HTTPS_PROXY           = "http://proxy.example.com:3128"
      TFC_ADDRESS           = "https://tfe.example.com"
      TFC_AGENT_AUTO_UPDATE = "disabled"
      TFC_AGENT_LOG_LEVEL   = "debug"
      TFC_AGENT_NAME        = "network-agent"
      TFC_AGENT_SINGLE      = "false"
    }
    error_message = "Custom environment should be merged over the module defaults"
  }
}

run "tags" {
  command = plan

  variables {
    tags = {
      Team             = "platform"
      tfe-organization = "overridden"
    }
  }

  assert {
    condition     = local.tags == { Team = "platform", tfe-organization = "my-org" }
    error_message = "The tfe-organization tag should be merged with, and take precedence over, the supplied tags"
  }
}

run "invalid_log_level" {
  command = plan

  variables {
    agent_log_level = "verbose"
  }

  expect_failures = [var.agent_log_level]
}

run "invalid_desired_count" {
  command = plan

  variables {
    desired_count = 0
  }

  expect_failures = [var.desired_count]
}
