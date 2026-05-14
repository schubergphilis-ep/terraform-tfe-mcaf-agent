variable "task_name" {
  description = "ECS task name, used to derive the CloudWatch log group name (/ecs/<task_name>) in the KMS key policy"
  type        = string
}

variable "tags" {
  description = "Map of tags to assign to the KMS key"
  type        = map(string)
}
