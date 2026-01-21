output "policy_id" {
  value       = try(aws_organizations_policy.this[0].id, null)
  description = "The ID of the Service Control Policy"
}

output "policy_arn" {
  value       = try(aws_organizations_policy.this[0].arn, null)
  description = "The ARN of the Service Control Policy"
}

output "policy_name" {
  value       = try(aws_organizations_policy.this[0].name, null)
  description = "The name of the Service Control Policy"
}

output "target_id" {
  value       = var.target_id
  description = "The target ID the SCP is attached to"
}

output "attachment_id" {
  value       = try(aws_organizations_policy_attachment.this[0].id, null)
  description = "The ID of the policy attachment"
}

output "attached" {
  value       = local.enabled && var.attach_to_target && var.target_id != null
  description = "Whether the SCP was attached to a target"
}
