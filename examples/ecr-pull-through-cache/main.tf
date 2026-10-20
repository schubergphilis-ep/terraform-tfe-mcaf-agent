provider "aws" {
  region = "eu-central-1"
}

provider "tfe" {
  organization = "my-org"
}

module "tfc_agent" {
  source = "../.."

  agent_image_tag     = "1.28.1"
  allowed_project_ids = ["prj-AbCdEfGhIjKlMnOp"]
  subnet_ids          = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  vpc_id              = "vpc-0123456789abcdef0"

  ecr_pull_through_cache = {
    enabled        = true
    credential_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:ecr-pullthroughcache/docker-hub-AbCdEf"
  }
}
