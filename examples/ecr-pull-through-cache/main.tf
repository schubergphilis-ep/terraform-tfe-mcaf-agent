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

  kms_key_configuration = {
    iam_arns_administrator = ["arn:aws:iam::123456789012:role/terraform"]
  }

  ecr_pull_through_cache = {
    enabled        = true
    credential_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:ecr-pullthroughcache/docker-hub-AbCdEf"
  }
}
