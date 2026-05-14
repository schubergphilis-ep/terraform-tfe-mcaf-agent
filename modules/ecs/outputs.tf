output "agent_pool_id" {
  description = "ID of the TFE agent pool"
  value       = tfe_agent_pool.default.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = local.cluster_arn
}

output "execution_role_arn" {
  description = "ARN of the ECS execution IAM role"
  value       = module.execution_role.arn
}

output "security_group_id" {
  description = "ID of the agent security group"
  value       = aws_security_group.default.id
}

output "task_role_arn" {
  description = "ARN of the ECS task IAM role"
  value       = module.task_role.arn
}
