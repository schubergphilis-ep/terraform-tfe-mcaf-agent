provider "aws" {
  region = "eu-central-1"
}

provider "tfe" {
  organization = "my-org"
}

module "tfc_agent" {
  source = "../.."

  name                 = "tfc-agent-network"
  pool_name            = "network"
  desired_count        = 2
  kms_key_arn          = "arn:aws:kms:eu-central-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  permissions_boundary = "arn:aws:iam::123456789012:policy/workload-boundary"
  subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  vpc_id               = "vpc-0123456789abcdef0"

  allowed_workspace_ids = ["ws-AbCdEfGhIjKlMnOp"]

  tags = {
    Team = "platform"
  }
}
