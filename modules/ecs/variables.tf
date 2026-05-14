variable "agent_image" {
  description = "Container image for the TFC agent"
  type        = string
  default     = "hashicorp/tfc-agent"
}

variable "agent_image_tag" {
  description = "Image tag for the TFC agent container"
  type        = string
  default     = "1.28"
}

variable "agent_log_level" {
  description = "Log level for the TFC agent"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["trace", "debug", "info", "warn", "error"], var.agent_log_level)
    error_message = "Must be one of: trace, debug, info, warn, error."
  }
}

variable "agent_name" {
  description = "Name used to identify the agent in the HCP Terraform UI"
  type        = string
  default     = "ecs-agent"
}

variable "cpu" {
  description = "Fargate CPU units for the agent task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of agent tasks to run"
  type        = number
  default     = 1
}

variable "ecs_cluster_arn" {
  description = "ARN of an existing ECS cluster; if null a new cluster is created"
  type        = string
  default     = null
}

variable "iam_path" {
  description = "Path for IAM roles created by this module"
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^(/|/.+/)$", var.iam_path))
    error_message = "Must be '/' or start and end with '/' (e.g. '/custom/')."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the SSM parameter and CloudWatch log group"
  type        = string
}

variable "memory" {
  description = "Fargate memory (MiB) for the agent task"
  type        = number
  default     = 2048
}

variable "name" {
  description = "Name used for resources created by this module"
  type        = string
  default     = "tfc-agent"
}

variable "permissions_boundary" {
  description = "ARN of the permissions boundary to set on IAM roles"
  type        = string
  default     = null
}

variable "pool_name" {
  description = "Name of the TFE agent pool"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the ECS service"
  type        = list(string)
}

variable "tags" {
  description = "Map of tags to assign to all taggable resources"
  type        = map(string)
}

variable "task_role_policy_arns" {
  description = "Set of IAM policy ARNs to attach to the ECS task role"
  type        = set(string)
  default     = []
}

variable "tfe_organization" {
  description = "HCP Terraform organization name"
  type        = string
}

variable "workspace_ids" {
  description = "Set of TFE workspace IDs to configure with agent execution mode"
  type        = set(string)
  default     = []
}

variable "vpc_id" {
  description = "ID of the VPC for the agent security group"
  type        = string
}
