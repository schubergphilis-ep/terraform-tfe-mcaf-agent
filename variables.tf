variable "agent_image" {
  type        = string
  default     = "hashicorp/tfc-agent"
  description = "Container image of the HCP Terraform agent, without tag."
}

variable "agent_image_tag" {
  type        = string
  default     = "1.28"
  description = "Tag of the HCP Terraform agent container image."
}

variable "agent_log_level" {
  type        = string
  default     = "info"
  description = "Log level of the HCP Terraform agent."

  validation {
    condition     = contains(["trace", "debug", "info", "warn", "error"], var.agent_log_level)
    error_message = "Allowed values are \"trace\", \"debug\", \"info\", \"warn\" or \"error\"."
  }
}

variable "agent_name" {
  type        = string
  default     = null
  description = "Name of the agents as shown in HCP Terraform; defaults to `name`."
}

variable "agent_single_execution" {
  type        = bool
  default     = true
  description = "Stop the agent after each run so every run starts in a fresh container; ECS replaces the stopped task."
}

variable "allowed_project_ids" {
  type        = set(string)
  default     = []
  description = "IDs of the HCP Terraform projects whose workspaces may use the agent pool. Only used when `organization_scoped` is false."
}

variable "allowed_workspace_ids" {
  type        = set(string)
  default     = []
  description = "IDs of the HCP Terraform workspaces that may use the agent pool. Only used when `organization_scoped` is false."
}

variable "architecture" {
  type        = string
  default     = "x86_64"
  description = "Instruction set architecture of the Fargate task."

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "Allowed values are \"arm64\" or \"x86_64\"."
  }
}

variable "cpu" {
  type        = number
  default     = 1024
  description = "Fargate CPU units per agent task (1 vCPU = 1024 CPU units)."
}

variable "desired_count" {
  type        = number
  default     = 1
  description = "Number of agent tasks to run; each agent handles one run at a time."

  validation {
    condition     = var.desired_count >= 1
    error_message = "At least one agent task must run."
  }
}

variable "environment" {
  type        = map(string)
  default     = {}
  description = "Additional environment variables for the agent container, e.g. `TFC_AGENT_*` settings. Overrides the module defaults."
}

variable "kms_key_administrator_arns" {
  type        = list(string)
  default     = []
  description = "IAM ARNs allowed to administer the created KMS key; defaults to the role running Terraform. Only used when `kms_key_arn` is not set."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of an existing KMS key to encrypt the SSM parameter and CloudWatch log group; if null a key is created."
}

variable "log_retention_days" {
  type        = number
  default     = 365
  description = "Retention in days of the agent CloudWatch log group."
}

variable "memory" {
  type        = number
  default     = 2048
  description = "Fargate memory (in MiB) per agent task."
}

variable "name" {
  type        = string
  default     = "tfc-agent"
  description = "Name used for the AWS resources; must be unique per AWS account and region."
}

variable "organization_scoped" {
  type        = bool
  default     = false
  description = "Allow all workspaces in the organization to use the agent pool instead of only the allowed projects and workspaces."
}

variable "permissions_boundary" {
  type        = string
  default     = null
  description = "ARN of the permissions boundary to set on the agent IAM role."
}

variable "pool_name" {
  type        = string
  default     = null
  description = "Name of the HCP Terraform agent pool; defaults to `name`."
}

variable "region" {
  type        = string
  default     = null
  description = "The AWS region where resources will be created; if omitted the default provider region is used."
}

variable "role_policy_documents" {
  type        = list(string)
  default     = []
  description = "Additional IAM policy documents (JSON) merged into the agent role policy. This role is also used by Terraform runs on the agent."
}

variable "subnet_ids" {
  type        = list(string)
  description = "IDs of the private subnets to run the agent tasks in."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A mapping of tags to assign to the AWS resources."
}

variable "tfc_address" {
  type        = string
  default     = null
  description = "Address of the HCP Terraform or Terraform Enterprise instance; if null the agent default (https://app.terraform.io) is used."
}

variable "tfe_organization" {
  type        = string
  default     = null
  description = "Name of the HCP Terraform organization; if null the tfe provider organization is used."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC to run the agent tasks in."
}
