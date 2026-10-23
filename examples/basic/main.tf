provider "aws" {
  region = "eu-central-1"
}

provider "tfe" {
  organization = "my-org"
}

module "tfc_agent" {
  source = "../.."

  allowed_project_ids = ["prj-AbCdEfGhIjKlMnOp"]
  subnet_ids          = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  kms_key_configuration = {
    iam_arns_administrator = ["arn:aws:iam::123456789012:role/terraform"]
  }
}
