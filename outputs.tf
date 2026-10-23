output "agent_pool_id" {
  description = "ID of the HCP Terraform agent pool"
  value       = tfe_agent_pool.default.id
}

output "agent_pool_name" {
  description = "Name of the HCP Terraform agent pool"
  value       = tfe_agent_pool.default.name
}

output "agent_token_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the agent token, either created or supplied through `agent_token_secret_arn`"
  value       = local.agent_token_secret_arn
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.fargate.cluster_arn
}

output "ecs_service_arn" {
  description = "ARN of the ECS service running the agents"
  value       = module.fargate.ecs_service_arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository caching the agent image, if the pull through cache is enabled"
  value       = local.ecr_repository_url
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the created agent token secret and logs"
  value       = local.kms_key_arn
}

output "role_arn" {
  description = "ARN of the IAM role used by the agent tasks and the Terraform runs on them"
  value       = module.fargate.task_execution_role_arn
}

output "security_group_id" {
  description = "ID of the agent security group"
  value       = module.fargate.security_group_id
}

output "task_definition_arn" {
  description = "ARN of the agent task definition"
  value       = module.fargate.task_definition_arn
}
