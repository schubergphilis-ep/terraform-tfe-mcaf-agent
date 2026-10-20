output "agent_pool_id" {
  description = "ID of the HCP Terraform agent pool"
  value       = tfe_agent_pool.default.id
}

output "agent_pool_name" {
  description = "Name of the HCP Terraform agent pool"
  value       = tfe_agent_pool.default.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.fargate.cluster_arn
}

output "ecs_service_arn" {
  description = "ARN of the ECS service running the agents"
  value       = module.fargate.ecs_service_arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the agent token and logs"
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

output "ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the agent token"
  value       = aws_ssm_parameter.default.arn
}

output "task_definition_arn" {
  description = "ARN of the agent task definition"
  value       = module.fargate.task_definition_arn
}
