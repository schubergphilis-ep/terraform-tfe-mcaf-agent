module "tfc_agent_kms" {
  source = "../../modules/ecs-kms-key"

  task_name = "tfc-agent"
  tags      = var.tags
}

module "tfc_agent" {
  source = "../../modules/ecs"

  tfe_organization   = "my-org"
  pool_name          = "my-agent-pool"
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  kms_key_arn        = module.tfc_agent_kms.arn
  tags               = var.tags
}
