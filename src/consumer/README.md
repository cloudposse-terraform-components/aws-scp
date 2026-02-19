# AWS SCP Consumer Component

## Purpose

The **consumer** component attaches existing Service Control Policies (SCPs) to organization targets OR creates custom one-off policies. It is designed to work alongside the **manager** component, which creates catalog policies in bulk.

## Key Features

- **Policy Attachment**: Attach existing policies (created by manager) to targets
- **Custom Policy Creation**: Create custom one-off policies with `policy_statements` or `policy_content`
- **Flexible Targeting**: Attach to organization root, OUs, or individual accounts
- **No Catalog Loading**: Simplified component without catalog logic
- **No Oscillation**: No data source lookups that could cause Terraform state issues

## When to Use This Component

Use the **consumer** component when you need to:
- Attach catalog policies (created by manager) to specific targets
- Create custom one-off policies specific to a single target
- Manage policy attachments independently from policy creation
- Attach the same policy to multiple targets (multiple consumer instances)

**Do NOT use** the consumer for:
- Creating multiple policies from catalogs (use **manager** instead)
- Bulk policy creation (use **manager** instead)

## Usage Patterns

### Pattern 1: Attach Catalog Policy to Target

The most common pattern - reference a policy created by the manager component:

```yaml
components:
  terraform:
    # Consumer attaches manager-created policy to organization root
    scp-attach/deny-leaving-org-root:
      metadata:
        component: aws-scp
        type: consumer  # Important: specifies the consumer subdirectory
      vars:
        enabled: true
        # Reference policy from manager output
        policy_id: !terraform.output scp-manager/all-policies policy_ids["DenyLeavingOrganization"]
        target_id: !terraform.output aws-organization organization_root_id
```

### Pattern 2: Attach Same Policy to Multiple Targets

Create multiple consumer instances to attach one policy to many targets:

```yaml
components:
  terraform:
    # Attach to root
    scp-attach/deny-leaving-org-root:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_id: !terraform.output scp-manager/all-policies policy_ids["DenyLeavingOrganization"]
        target_id: !terraform.output aws-organization organization_root_id

    # Attach same policy to core OU
    scp-attach/deny-leaving-org-core:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_id: !terraform.output scp-manager/all-policies policy_ids["DenyLeavingOrganization"]
        target_id: !terraform.output aws-organizational-unit/core organizational_unit_id

    # Attach same policy to platform OU
    scp-attach/deny-leaving-org-plat:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_id: !terraform.output scp-manager/all-policies policy_ids["DenyLeavingOrganization"]
        target_id: !terraform.output aws-organizational-unit/plat organizational_unit_id
```

### Pattern 3: Create Custom Policy with Statements

Create a one-off custom policy using `policy_statements`:

```yaml
components:
  terraform:
    scp-custom/deny-s3-delete-prod:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        enabled: true
        policy_name: "DenyS3DeleteProduction"
        policy_description: "Prevent S3 object deletion in production buckets"
        policy_statements:
          - sid: "DenyS3ObjectDeletion"
            effect: "Deny"
            actions:
              - "s3:DeleteObject"
              - "s3:DeleteObjectVersion"
              - "s3:DeleteBucket"
            resources:
              - "arn:aws:s3:::production-*/*"
              - "arn:aws:s3:::production-*"
            conditions:
              - test: "StringNotEquals"
                variable: "aws:PrincipalArn"
                values:
                  - "arn:aws:iam::123456789012:role/AdminRole"
        target_id: !terraform.output aws-organizational-unit/production organizational_unit_id
```

### Pattern 4: Create Custom Policy with Raw JSON

Create a custom policy using raw JSON policy document:

```yaml
components:
  terraform:
    scp-custom/deny-ec2-large-instances:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        enabled: true
        policy_name: "DenyLargeEC2Instances"
        policy_description: "Prevent launching large EC2 instances"
        policy_content: |
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Sid": "DenyLargeInstances",
                "Effect": "Deny",
                "Action": "ec2:RunInstances",
                "Resource": "arn:aws:ec2:*:*:instance/*",
                "Condition": {
                  "StringEquals": {
                    "ec2:InstanceType": [
                      "m5.8xlarge",
                      "m5.12xlarge",
                      "m5.16xlarge",
                      "m5.24xlarge"
                    ]
                  }
                }
              }
            ]
          }
        target_id: !terraform.output aws-organizational-unit/development organizational_unit_id
```

### Pattern 5: Create Policy Without Attachment

Create a policy but don't attach it to any target (useful for testing):

```yaml
components:
  terraform:
    scp-custom/test-policy:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        enabled: true
        attach_to_target: false  # Don't attach
        policy_name: "TestPolicy"
        policy_statements:
          - sid: "DenyExample"
            effect: "Deny"
            actions: ["ec2:RunInstances"]
            resources: ["*"]
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `region` | `string` | Yes | AWS Region |
| `policy_id` | `string` | Conditional | ID of existing policy to attach (from manager output). Required when NOT creating a custom policy. |
| `policy_name` | `string` | No | Name for custom policy. Defaults to `module.this.id`. |
| `policy_description` | `string` | No | Description for custom policy. Default: "Service Control Policy managed by Terraform" |
| `policy_statements` | `list(object)` | Conditional | List of policy statements. Required when creating custom policy (unless using `policy_content`). |
| `policy_content` | `string` | Conditional | Raw JSON policy document. Alternative to `policy_statements`. |
| `target_id` | `string` | Conditional | ID of organization root, OU, or account to attach to. Required when `attach_to_target = true`. |
| `attach_to_target` | `bool` | No | Whether to attach the policy to a target. Default: `true` |
| `skip_destroy` | `bool` | No | If true, policy is detached but not destroyed on removal. Default: `false` |

### Policy Statement Object Structure

```hcl
{
  sid        = optional(string)       # Statement ID
  effect     = string                 # "Allow" or "Deny"
  actions    = list(string)           # List of AWS actions
  resources  = list(string)           # List of resource ARNs
  conditions = optional(list(object({
    test     = string                 # Condition test (e.g., "StringEquals")
    variable = string                 # Condition variable
    values   = list(string)           # Condition values
  })))
}
```

## Outputs

| Name | Description |
|------|-------------|
| `policy_id` | The ID of the policy (created or referenced) |
| `policy_arn` | The ARN of the policy |
| `policy_name` | The name of the policy |
| `attachment_id` | The ID of the policy attachment (if attached) |

## Deprecated Variables

The following variables are **deprecated** and will cause errors if used:

| Variable | Status | Migration |
|----------|--------|-----------|
| `policy_sid` | ❌ Deprecated | Use `policy_id` with manager output instead |
| `service_control_policies_config_paths` | ❌ Deprecated | Use manager component for catalog loading |
| `policy_name_from_sid` | ❌ Deprecated | Not applicable in consumer |

### Migration from `policy_sid`

If you're currently using `policy_sid`:

**Before (Deprecated)**:
```yaml
scp/deny-leaving-org:
  vars:
    policy_sid: "DenyLeavingOrganization"
    service_control_policies_config_paths: [...]
    target_id: ou-xxxxx
```

**After (New Architecture)**:
```yaml
# 1. Create manager
scp-manager/all-policies:
  metadata:
    type: manager
  vars:
    service_control_policies_config_paths: [...]

# 2. Create consumer
scp-attach/deny-leaving-org:
  metadata:
    type: consumer
  vars:
    policy_id: !terraform.output scp-manager/all-policies policy_ids["DenyLeavingOrganization"]
    target_id: ou-xxxxx
```

## Validation Rules

The consumer component enforces these validation rules:

1. **Mutually Exclusive Sources**: Cannot use `policy_id` together with `policy_statements` or `policy_content`
2. **Exactly One Source**: Must provide exactly one of:
   - `policy_id` (attach existing)
   - `policy_statements` (create custom)
   - `policy_content` (create custom)
3. **No policy_sid**: Using `policy_sid` will cause a precondition error with migration instructions
4. **Target Required**: When `attach_to_target = true`, `target_id` must be provided

## Deployment Requirements

- Must be deployed from the **management/root account**
- Requires AWS Organizations enabled
- IAM permissions needed:
  - When creating policies:
    - `organizations:CreatePolicy`
    - `organizations:UpdatePolicy`
    - `organizations:DeletePolicy`
  - When attaching policies:
    - `organizations:AttachPolicy`
    - `organizations:DetachPolicy`
    - `organizations:DescribePolicy`

## Examples

### Example 1: Attach Multiple Catalog Policies to Same Target

```yaml
components:
  terraform:
    scp-attach/deny-leaving-org-root:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_id: !terraform.output scp-manager/all-policies policy_ids["DenyLeavingOrganization"]
        target_id: !terraform.output aws-organization organization_root_id

    scp-attach/deny-root-access-root:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_id: !terraform.output scp-manager/all-policies policy_ids["DenyRootAccountAccess"]
        target_id: !terraform.output aws-organization organization_root_id

    scp-attach/require-mfa-root:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_id: !terraform.output scp-manager/all-policies policy_ids["RequireMFA"]
        target_id: !terraform.output aws-organization organization_root_id
```

### Example 2: Custom Policy with Complex Conditions

```yaml
components:
  terraform:
    scp-custom/restrict-regions:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_name: "RestrictToAllowedRegions"
        policy_description: "Restrict services to specific AWS regions"
        policy_statements:
          - sid: "DenyAllOutsideAllowedRegions"
            effect: "Deny"
            actions:
              - "ec2:*"
              - "rds:*"
              - "s3:*"
            resources:
              - "*"
            conditions:
              - test: "StringNotEquals"
                variable: "aws:RequestedRegion"
                values:
                  - "us-east-1"
                  - "us-west-2"
              - test: "ArnNotLike"
                variable: "aws:PrincipalArn"
                values:
                  - "arn:aws:iam::*:role/OrganizationAccountAccessRole"
        target_id: !terraform.output aws-organizational-unit/sandbox organizational_unit_id
```

### Example 3: Reference Policy from Another Consumer

```yaml
components:
  terraform:
    # First consumer creates the policy
    scp-custom/deny-root-user:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_name: "DenyRootUser"
        attach_to_target: false  # Don't attach yet
        policy_statements:
          - sid: "DenyRootUser"
            effect: "Deny"
            actions: ["*"]
            resources: ["*"]
            conditions:
              - test: "StringLike"
                variable: "aws:PrincipalArn"
                values: ["arn:aws:iam::*:root"]

    # Second consumer attaches the policy
    scp-attach/deny-root-user-core:
      metadata:
        component: aws-scp
        type: consumer
      vars:
        policy_id: !terraform.output scp-custom/deny-root-user policy_id
        target_id: !terraform.output aws-organizational-unit/core organizational_unit_id
```

## Best Practices

1. **Use Manager for Catalogs**: Always use manager component for catalog policies
2. **One Consumer Per Attachment**: Deploy one consumer instance per policy-target combination
3. **Descriptive Names**: Use clear component names (e.g., `scp-attach/policy-name-target-name`)
4. **Custom Policies for One-offs**: Use consumer for target-specific custom policies
5. **Test Without Attachment**: Use `attach_to_target: false` to test policies before attaching

## Troubleshooting

### Error: "policy_sid is not supported in consumer component"

This means you're trying to use the deprecated `policy_sid` variable. Migrate to the new architecture:

1. Deploy a manager component with `service_control_policies_config_paths`
2. Change consumer to use `policy_id` referencing manager output

### Error: "policy_id is mutually exclusive with policy_statements"

You cannot both create a policy and attach an existing one. Choose one:
- To attach: Use `policy_id` only
- To create: Use `policy_statements` or `policy_content` only

### Error: "exactly one of policy_statements or policy_content must be provided"

When creating a custom policy, provide either `policy_statements` OR `policy_content`, not both, and not neither.

### Policy Not Attaching

Check:
- `attach_to_target` is `true` (default)
- `target_id` is provided and valid
- Target exists (organization root, OU, or account)
- You have permission to attach policies to the target

## Related Components

- **aws-scp (manager)**: Use to create policies from catalogs in bulk
- **aws-organization**: Provides organization root ID
- **aws-organizational-unit**: Provides OU IDs
- **aws-organization-account**: Provides account IDs for individual account attachments
