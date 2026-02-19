# Load Service Control Policy catalogs
module "service_control_policy_catalog" {
  source  = "cloudposse/config/yaml"
  version = "1.0.2"

  count = length(var.service_control_policies_config_paths) > 0 ? 1 : 0

  list_config_local_base_path = path.module
  list_config_paths           = var.service_control_policies_config_paths

  context = module.this.context
}

locals {
  enabled = module.this.enabled

  # Load and transform catalog policies
  catalog_policies = try(module.service_control_policy_catalog[0].list_configs, [])

  # Build map: SID => policy object
  # Catalog uses 'condition' (singular), component uses 'conditions' (plural)
  # Catalog may use 'actions' or 'not_actions', 'resources' or 'not_resources'
  catalog_policies_map = {
    for policy in local.catalog_policies : policy.sid => merge(
      policy,
      {
        # Use SID as policy name by default
        name = policy.sid
        # Transform: condition -> conditions
        conditions = try(policy.condition, lookup(policy, "conditions", []))
      }
    )
  }

  # Merge catalog and custom policies
  all_policies = merge(
    local.catalog_policies_map,
    var.custom_policies
  )

  # Generate policy JSON for each policy
  policies_with_content = {
    for key, policy in local.all_policies : key => {
      name        = policy.name
      description = try(policy.description, "Policy ${policy.sid} managed by Terraform")
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [
          merge(
            {
              Effect = policy.effect
            },
            # Handle both actions and not_actions (mutually exclusive)
            try(policy.actions, null) != null ? { Action = policy.actions } : {},
            try(policy.not_actions, null) != null ? { NotAction = policy.not_actions } : {},
            # Handle both resources and not_resources (mutually exclusive)
            try(policy.resources, null) != null ? { Resource = policy.resources } : {},
            try(policy.not_resources, null) != null ? { NotResource = policy.not_resources } : {},
            # Add SID if present
            policy.sid != null ? { Sid = policy.sid } : {},
            # Add Condition block if conditions exist
            length(coalesce(policy.conditions, [])) > 0 ? {
              Condition = {
                for test_key in distinct([for c in coalesce(policy.conditions, []) : c.test]) : test_key => merge([
                  for cond in [for c in coalesce(policy.conditions, []) : c if c.test == test_key] : {
                    (cond.variable) = cond.values
                  }
                ]...)
              }
            } : {}
          )
        ]
      })
    }
  }
}

# Create all policies in bulk
# NO data source lookups to avoid oscillation
resource "aws_organizations_policy" "this" {
  for_each = local.enabled ? local.policies_with_content : {}

  name        = each.value.name
  description = each.value.description
  content     = each.value.policy_json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = module.this.tags
}
