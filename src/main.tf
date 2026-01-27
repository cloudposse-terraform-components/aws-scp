# Load Service Control Policy catalogs
module "service_control_policy_catalog" {
  source  = "cloudposse/config/yaml"
  version = "1.0.2"

  count = length(var.service_control_policies_config_paths) > 0 ? 1 : 0

  list_config_local_base_path = path.module
  list_config_paths           = var.service_control_policies_config_paths

  context = module.this.context
}

# Look up existing SCPs to check if policy already exists
data "aws_organizations_policies" "service_control_policies" {
  count  = local.enabled ? 1 : 0
  filter = "SERVICE_CONTROL_POLICY"
}

# Look up details of each existing policy to find matching name
data "aws_organizations_policy" "existing" {
  for_each  = local.enabled && var.policy_id == null ? toset(try(data.aws_organizations_policies.service_control_policies[0].ids, [])) : toset([])
  policy_id = each.value
}

locals {
  enabled         = module.this.enabled
  catalog_enabled = length(var.service_control_policies_config_paths) > 0

  # Build catalog lookup map (SID => policy statements)
  all_catalog_policies = try(module.service_control_policy_catalog[0].list_configs, [])

  # Transform catalog format to component format
  # Catalog uses 'condition' (singular), component uses 'conditions' (plural)
  catalog_policies_map = {
    for policy in local.all_catalog_policies : policy.sid => merge(
      policy,
      {
        # Transform: condition -> conditions
        conditions = try(policy.condition, lookup(policy, "conditions", []))
      }
    )
  }

  # Policy name resolution: explicit > SID > module.this.id > default
  policy_name = coalesce(
    var.policy_name,
    var.policy_name_from_sid && var.policy_sid != null ? var.policy_sid : null,
    module.this.id,
    "default-policy"
  )

  # Find existing policy with matching name
  existing_policies_by_name = {
    for id, policy in data.aws_organizations_policy.existing : policy.name => policy.id
  }
  existing_policy_id = try(local.existing_policies_by_name[local.policy_name], null)

  # Determine if we're creating a policy or using an existing one
  # Priority: explicit policy_id > existing policy > create new
  create_policy       = local.enabled && var.policy_id == null && local.existing_policy_id == null
  use_existing_policy = local.enabled && (var.policy_id != null || local.existing_policy_id != null)
  final_policy_id     = var.policy_id != null ? var.policy_id : local.existing_policy_id

  # Resolve policy statements from SID or use explicit statements
  resolved_policy_statements = (
    var.policy_sid != null
    ? [local.catalog_policies_map[var.policy_sid]] # Wrap in list for single statement
    : var.policy_statements
  )

  # Generate JSON policy from statements (unchanged logic)
  generated_policy = length(local.resolved_policy_statements) > 0 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in local.resolved_policy_statements : merge(
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

resource "aws_organizations_policy" "this" {
  count = local.create_policy ? 1 : 0

  name        = local.policy_name
  description = var.policy_description
  content     = local.policy_content
  type        = "SERVICE_CONTROL_POLICY"
  tags        = module.this.tags

  lifecycle {
    # Ensure exactly one policy source is provided (when creating a policy)
    precondition {
      condition = (
        var.policy_id != null || (
          (var.policy_sid != null ? 1 : 0) +
          (length(var.policy_statements) > 0 ? 1 : 0) +
          (var.policy_content != null ? 1 : 0)
        ) == 1
      )
      error_message = "When policy_id is not set, exactly one of policy_sid, policy_statements, or policy_content must be provided."
    }

    # Ensure policy_id and policy sources are mutually exclusive
    precondition {
      condition = (
        var.policy_id == null ||
        (var.policy_sid == null && length(var.policy_statements) == 0 && var.policy_content == null)
      )
      error_message = "policy_id is mutually exclusive with policy_sid, policy_statements, and policy_content. Use policy_id to attach an existing policy, or use policy_sid/policy_statements/policy_content to create a new one."
    }

    # Ensure catalog is loaded when using policy_sid
    precondition {
      condition     = var.policy_sid == null || local.catalog_enabled
      error_message = "When using policy_sid, you must provide service_control_policies_config_paths to load the catalog."
    }

    # Ensure SID exists in catalog
    precondition {
      condition = (
        var.policy_sid == null ||
        contains(keys(local.catalog_policies_map), var.policy_sid)
      )
      error_message = "Policy SID '${coalesce(var.policy_sid, "null")}' not found in catalog. Available SIDs: ${join(", ", keys(local.catalog_policies_map))}"
    }
  }
}

resource "aws_organizations_policy_attachment" "this" {
  count = local.enabled && var.attach_to_target && var.target_id != null ? 1 : 0

  policy_id = local.use_existing_policy ? local.final_policy_id : aws_organizations_policy.this[0].id
  target_id = var.target_id
}
