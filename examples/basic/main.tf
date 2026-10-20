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
  vpc_id              = "vpc-0123456789abcdef0"
}
