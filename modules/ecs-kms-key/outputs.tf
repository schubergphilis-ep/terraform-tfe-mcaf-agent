output "arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.default.arn
}

output "policy_json" {
  description = "JSON-encoded key policy, useful for merging into an existing key policy"
  value       = data.aws_iam_policy_document.default.json
}
