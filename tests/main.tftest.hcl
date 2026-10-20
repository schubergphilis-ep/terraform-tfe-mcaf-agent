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

  mock_resource "aws_ssm_parameter" {
    defaults = {
      arn = "arn:aws:ssm:eu-central-1:123456789012:parameter/tfc-agent/token"
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
    condition     = tfe_agent_pool.default.name == "tfc-agent" && tfe_agent_pool.default.organization_scoped == false
    error_message = "Agent pool should default to the module name and not be organization scoped"
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
    condition     = aws_ssm_parameter.default.name == "/tfc-agent/token" && aws_ssm_parameter.default.type == "SecureString"
    error_message = "Agent token should be stored as SecureString under the module name"
  }

  assert {
    condition = local.environment == {
      TFC_AGENT_AUTO_UPDATE = "disabled"
      TFC_AGENT_LOG_LEVEL   = "info"
      TFC_AGENT_NAME        = "tfc-agent"
      TFC_AGENT_SINGLE      = "true"
    }
    error_message = "Unexpected default agent environment"
  }
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
    condition     = aws_ssm_parameter.default.key_id == var.kms_key_arn
    error_message = "SSM parameter should be encrypted with the provided KMS key"
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
    name                   = "network-agent"
    agent_name             = "network"
    agent_single_execution = false
    pool_name              = "network-pool"
    tfc_address            = "https://tfe.example.com"

    environment = {
      TFC_AGENT_LOG_LEVEL = "debug"
      HTTPS_PROXY         = "http://proxy.example.com:3128"
    }
  }

  assert {
    condition     = tfe_agent_pool.default.name == "network-pool" && aws_ssm_parameter.default.name == "/network-agent/token"
    error_message = "Custom pool and resource names should be used"
  }

  assert {
    condition = local.environment == {
      HTTPS_PROXY           = "http://proxy.example.com:3128"
      TFC_ADDRESS           = "https://tfe.example.com"
      TFC_AGENT_AUTO_UPDATE = "disabled"
      TFC_AGENT_LOG_LEVEL   = "debug"
      TFC_AGENT_NAME        = "network"
      TFC_AGENT_SINGLE      = "false"
    }
    error_message = "Custom environment should be merged over the module defaults"
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
