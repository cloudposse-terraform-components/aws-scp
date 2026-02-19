output "policies" {
  value = {
    for key, policy in aws_organizations_policy.this : key => {
      id          = policy.id
      arn         = policy.arn
      name        = policy.name
      description = policy.description
    }
  }
  description = "Map of created policies with full metadata (key = SID or custom policy identifier)"
}

output "policy_ids" {
  value = {
    for key, policy in aws_organizations_policy.this : key => policy.id
  }
  description = <<-EOT
    Map of policy IDs for reference by consumer components.
    Key is the SID or custom policy identifier, value is the AWS policy ID.

    Example usage in consumer:
      policy_id = !terraform.output scp-manager policy_ids["DenyLeavingOrganization"]
    EOT
}

output "policy_arns" {
  value = {
    for key, policy in aws_organizations_policy.this : key => policy.arn
  }
  description = "Map of policy ARNs (key = SID or custom policy identifier)"
}

output "policy_names" {
  value = {
    for key, policy in aws_organizations_policy.this : key => policy.name
  }
  description = "Map of policy names (key = SID or custom policy identifier)"
}
