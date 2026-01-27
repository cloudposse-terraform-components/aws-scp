output "policy_id" {
  value       = local.use_existing_policy ? local.final_policy_id : try(aws_organizations_policy.this[0].id, null)
  description = "The ID of the Service Control Policy"
}

output "policy_arn" {
  value       = try(aws_organizations_policy.this[0].arn, null)
  description = "The ARN of the Service Control Policy (only available when creating policy, not when using existing)"
}

output "policy_name" {
  value       = local.use_existing_policy ? null : try(aws_organizations_policy.this[0].name, null)
  description = "The name of the Service Control Policy (only available when creating policy, not when using existing)"
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
