# AWS SCP Manager Component

## Purpose

The **manager** component creates Service Control Policies (SCPs) in bulk from catalog files or custom definitions. It is designed to be deployed once per organization to create all reusable SCP policies, which can then be attached to multiple targets using the **consumer** component.

## Key Features

- **Bulk Creation**: Creates ALL policies from catalog files using `for_each` (not one-at-a-time)
- **Catalog Support**: Loads policies from YAML catalog files (local or remote)
- **Custom Policies**: Supports custom policy definitions alongside catalog policies
- **Map Outputs**: Outputs map of policy IDs for easy reference by consumer components
- **No Oscillation**: No data source lookups that could cause Terraform state oscillation

## When to Use This Component

Use the **manager** component when you need to:
- Create multiple policies from a centralized catalog
- Manage a set of reusable policies for your organization
- Establish a single source of truth for all SCP policies
- Enable bulk policy creation and updates

**Do NOT use** the manager for:
- Attaching policies to targets (use **consumer** instead)
- Creating one-off custom policies (use **consumer** instead)

## Usage

### Basic Usage - Load Catalog Policies

```yaml
components:
  terraform:
    scp-manager/cloudposse-catalog:
      metadata:
        component: aws-scp
        type: manager  # Important: specifies the manager subdirectory
      vars:
        enabled: true
        service_control_policies_config_paths:
          - "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/organization-policies.yaml"
          - "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/iam-policies.yaml"
          - "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/s3-policies.yaml"
```

This will create **all** policies defined in the three catalog files.

### Advanced Usage - Mix Catalog and Custom Policies

```yaml
components:
  terraform:
    scp-manager/all-policies:
      metadata:
        component: aws-scp
        type: manager
      vars:
        enabled: true
        # Load catalog policies
        service_control_policies_config_paths:
          - "https://raw.githubusercontent.com/.../organization-policies.yaml"

        # Add custom policies
        custom_policies:
          CustomDenyEC2Termination:
            sid: "CustomDenyEC2Termination"
            name: "CustomDenyEC2Termination"
            description: "Prevent EC2 instance termination in production"
            effect: "Deny"
            actions:
              - "ec2:TerminateInstances"
            resources:
              - "*"
            conditions:
              - test: "StringEquals"
                variable: "aws:RequestedRegion"
                values:
                  - "us-east-1"

          CustomRequireMFA:
            sid: "RequireMFAForSensitiveActions"
            name: "RequireMFAForSensitiveActions"
            description: "Require MFA for sensitive actions"
            effect: "Deny"
            actions:
              - "iam:DeleteUser"
              - "iam:DeleteRole"
            resources:
              - "*"
            conditions:
              - test: "BoolIfExists"
                variable: "aws:MultiFactorAuthPresent"
                values:
                  - "false"
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `region` | `string` | Yes | AWS Region |
| `service_control_policies_config_paths` | `list(string)` | No | List of paths to catalog YAML files (local or remote URLs) |
| `custom_policies` | `map(object)` | No | Map of custom policies to create alongside catalog policies |

### Custom Policy Object Structure

```hcl
{
  sid         = string                # Statement ID
  name        = string                # Policy name
  description = optional(string)      # Policy description
  effect      = string                # "Allow" or "Deny"
  actions     = list(string)          # List of AWS actions
  resources   = list(string)          # List of resource ARNs
  conditions  = optional(list(object({
    test     = string                 # Condition test (e.g., "StringEquals")
    variable = string                 # Condition variable
    values   = list(string)           # Condition values
  })))
}
```

## Outputs

| Name | Description | Example |
|------|-------------|---------|
| `policies` | Map of created policies with full metadata | `{DenyLeavingOrganization = {id = "p-xxx", arn = "...", name = "...", description = "..."}}` |
| `policy_ids` | Map of policy IDs (key = SID, value = policy_id) | `{DenyLeavingOrganization = "p-xxxxx"}` |
| `policy_arns` | Map of policy ARNs | `{DenyLeavingOrganization = "arn:aws:organizations::..."}` |
| `policy_names` | Map of policy names | `{DenyLeavingOrganization = "DenyLeavingOrganization"}` |

### Using Outputs in Consumer Components

Reference the manager's outputs in consumer components to attach policies:

```yaml
# Consumer component
scp-attach/deny-leaving-org-root:
  metadata:
    component: aws-scp
    type: consumer
  vars:
    # Reference the policy ID from manager output
    policy_id: !terraform.output scp-manager/cloudposse-catalog policy_ids["DenyLeavingOrganization"]
    target_id: !terraform.output aws-organization organization_root_id
```

## Catalog Format

Catalog files are YAML lists of policy definitions:

```yaml
# organization-policies.yaml
- sid: "DenyLeavingOrganization"
  description: "Prevents accounts from leaving the organization"
  effect: "Deny"
  actions:
    - "organizations:LeaveOrganization"
  resources:
    - "*"

- sid: "DenyRootAccountAccess"
  description: "Deny root user access"
  effect: "Deny"
  actions:
    - "*"
  resources:
    - "*"
  condition:  # Note: catalog uses 'condition' (singular)
    - test: "StringLike"
      variable: "aws:PrincipalArn"
      values:
        - "arn:aws:iam::*:root"
```

**Note**: The catalog format uses `condition` (singular) which is automatically transformed to `conditions` (plural) by the manager component.

## Available Catalogs

CloudPosse maintains an official catalog of SCP policies:
- Repository: https://github.com/cloudposse/terraform-aws-service-control-policies
- Catalog directory: `/catalog/`

Available catalog files:
- `organization-policies.yaml` - Organization management policies
- `iam-policies.yaml` - IAM-related policies
- `ec2-policies.yaml` - EC2 service policies
- `s3-policies.yaml` - S3 service policies
- `kms-policies.yaml` - KMS encryption policies
- `route53-policies.yaml` - DNS policies
- `cloudwatch-logs-policies.yaml` - CloudWatch Logs policies

> **Recommendation**: Pin catalog URLs to specific versions (e.g., `/0.15.1/`) for stability. Avoid using `/main/` branch URLs in production.

## Deployment Requirements

- Must be deployed from the **management/root account**
- Requires AWS Organizations enabled
- IAM permissions needed:
  - `organizations:CreatePolicy`
  - `organizations:UpdatePolicy`
  - `organizations:DeletePolicy`
  - `organizations:DescribePolicy`

## Examples

### Example 1: Single Manager for All Organization Policies

```yaml
components:
  terraform:
    scp-manager/all-policies:
      metadata:
        component: aws-scp
        type: manager
      vars:
        service_control_policies_config_paths:
          - "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/organization-policies.yaml"
          - "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/iam-policies.yaml"
          - "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/ec2-policies.yaml"
          - "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/s3-policies.yaml"
```

This creates all policies from the four catalogs in a single manager instance.

### Example 2: Multiple Managers for Different Policy Categories

```yaml
components:
  terraform:
    # Manager for organization-level policies
    scp-manager/organization:
      metadata:
        component: aws-scp
        type: manager
      vars:
        service_control_policies_config_paths:
          - "https://raw.githubusercontent.com/.../organization-policies.yaml"

    # Manager for security policies
    scp-manager/security:
      metadata:
        component: aws-scp
        type: manager
      vars:
        service_control_policies_config_paths:
          - "https://raw.githubusercontent.com/.../iam-policies.yaml"
          - "https://raw.githubusercontent.com/.../kms-policies.yaml"
```

## Best Practices

1. **One Manager Per Catalog Set**: Deploy one manager instance that creates all policies you need
2. **Pin Catalog Versions**: Use version-pinned URLs for catalogs (e.g., `/0.15.1/`)
3. **Namespace Custom Policies**: Use descriptive SIDs for custom policies to avoid conflicts
4. **Document Custom Policies**: Add clear descriptions to custom policies
5. **Use Consumer for Attachments**: Never attach policies in the manager - use consumer components

## Troubleshooting

### All Policies Are Created Even If I Only Need One

This is expected behavior. The manager creates **all** policies from the catalog. Use the consumer component to attach only the specific policies you need to specific targets.

### Policy Already Exists Error

If you get a "policy already exists" error, it means a policy with that name already exists in your organization. Either:
1. Import the existing policy into Terraform state
2. Delete the existing policy from AWS
3. Rename your policy to avoid conflicts

### Catalog Not Loading

Ensure:
- The catalog URL is accessible
- The YAML format is valid
- You have network connectivity to the URL
- The catalog files exist at the specified paths

## Related Components

- **aws-scp (consumer)**: Use to attach policies created by this manager to organization targets
- **aws-organization**: Provides the organization root ID for policy attachments
- **aws-organizational-unit**: Provides OU IDs for policy attachments
