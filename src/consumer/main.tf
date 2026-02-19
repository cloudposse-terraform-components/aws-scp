locals {
  enabled = module.this.enabled

  # Policy name resolution: explicit > module.this.id > default
  policy_name = coalesce(
    var.policy_name,
    module.this.id,
    "default-policy"
  )

  # Determine if we're creating a policy or using an existing one
  # Simplified: no data source lookup to avoid oscillation
  create_policy       = local.enabled && var.policy_id == null
  use_existing_policy = local.enabled && var.policy_id != null

  # Generate JSON policy from statements
  generated_policy = length(var.policy_statements) > 0 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in var.policy_statements : merge(
        {
          Effect   = stmt.effect
          Action   = stmt.actions
          Resource = stmt.resources
        },
        stmt.sid != null ? { Sid = stmt.sid } : {},
        length(coalesce(stmt.conditions, [])) > 0 ? {
          Condition = {
            for test_key in distinct([for c in coalesce(stmt.conditions, []) : c.test]) : test_key => merge([
              for cond in [for c in coalesce(stmt.conditions, []) : c if c.test == test_key] : {
                (cond.variable) = cond.values
              }
            ]...)
          }
        } : {}
      )
    ]
  }) : null

  policy_content = coalesce(var.policy_content, local.generated_policy, jsonencode({
    Version   = "2012-10-17"
    Statement = []
  }))
}

# Module-level validation
resource "terraform_data" "validation" {
  count = local.enabled ? 1 : 0

  lifecycle {
    # Reject policy_sid usage - direct users to manager component
    precondition {
      condition     = var.policy_sid == null
      error_message = <<-EOT
        policy_sid is not supported in the consumer component.

        To use catalog policies:
        1. Create policies with the manager component (type: manager)
        2. Reference the created policy via policy_id

        Example:
          policy_id = !terraform.output scp-manager policy_ids["DenyLeavingOrganization"]
      EOT
    }

    # Ensure policy_id and policy sources are mutually exclusive
    precondition {
      condition = (
        var.policy_id == null ||
        (length(var.policy_statements) == 0 && var.policy_content == null)
      )
      error_message = "policy_id is mutually exclusive with policy_statements and policy_content. Use policy_id to attach an existing policy, or use policy_statements/policy_content to create a custom policy."
    }

    # Ensure exactly one policy source when creating
    precondition {
      condition = (
        var.policy_id != null || (
          (length(var.policy_statements) > 0 ? 1 : 0) +
          (var.policy_content != null ? 1 : 0)
        ) == 1
      )
      error_message = "When creating a custom policy, exactly one of policy_statements or policy_content must be provided. To attach an existing policy, use policy_id."
    }
  }
}

# Create custom policy (only when policy_id is not set)
resource "aws_organizations_policy" "this" {
  count = local.create_policy ? 1 : 0

  name        = local.policy_name
  description = var.policy_description
  content     = local.policy_content
  type        = "SERVICE_CONTROL_POLICY"
  tags        = module.this.tags
}

# Attach policy to target
resource "aws_organizations_policy_attachment" "this" {
  count = local.enabled && var.attach_to_target && var.target_id != null ? 1 : 0

  policy_id = local.use_existing_policy ? var.policy_id : aws_organizations_policy.this[0].id
  target_id = var.target_id
}
