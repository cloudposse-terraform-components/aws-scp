# Migration Guide: Monolithic `account` to Single-Resource `aws-scp`

This document outlines the migration from the monolithic `account` component to the new single-resource `aws-scp` component.

## Overview

The previous `account` component created all AWS Organizations resources (organization, OUs, accounts, SCPs) in a single Terraform state. The new `aws-scp` component follows the single-resource pattern - it manages only a single Service Control Policy.

### Why Migrate?

| Aspect | Old `account` Component | New `aws-scp` Component |
|--------|-------------------------|-------------------------|
| **Scope** | All SCPs in one component | Single SCP per component |
| **State** | All resources in one state | Independent state per SCP |
| **Lifecycle** | Changes affect all SCPs | Changes isolated to one SCP |
| **Risk** | High blast radius | Minimal blast radius |
| **Flexibility** | Shared configuration | Per-SCP customization |

### New Component Suite

The monolithic `account` component is replaced by these single-resource components:

| Component | Purpose |
|-----------|---------|
| `aws-organization` | Creates/imports the AWS Organization |
| `aws-organizational-unit` | Creates/imports a single OU |
| `aws-account` | Creates/imports a single AWS Account |
| `aws-account-settings` | Configures account settings |
| `aws-scp` | Creates/imports Service Control Policies (this component) |

---

## Migration Steps

### Phase 1: Get Policy IDs

```bash
# List all SCPs
aws organizations list-policies \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[*].[Name,Id]' --output table

# Example output:
# |           Name                    |     Id      |
# |-----------------------------------|-------------|
# | DenyLeavingOrganization           | p-abc12345  |
# | DenyRootAccountAccess             | p-def67890  |
```

### Phase 2: Create Stack Configuration

Create a component instance for each SCP:

```yaml
# stacks/orgs/<namespace>/core/root/global-region.yaml
components:
  terraform:
    # Deny Leaving Organization SCP
    aws-scp/deny-leaving-org:
      metadata:
        component: aws-scp
      vars:
        policy_name: DenyLeavingOrganization
        policy_description: Prevents accounts from leaving the organization
        policy_statements:
          - sid: DenyLeaveOrganization
            effect: Deny
            actions:
              - organizations:LeaveOrganization
            resources:
              - "*"
        target_ids:
          - "r-xxxx"  # Attach to root
        import_policy_id: "p-abc12345"

    # Deny Root Account Access SCP
    aws-scp/deny-root-access:
      metadata:
        component: aws-scp
      vars:
        policy_name: DenyRootAccountAccess
        policy_description: Denies root account access in member accounts
        policy_statements:
          - sid: DenyRootAccess
            effect: Deny
            actions:
              - "*"
            resources:
              - "*"
            conditions:
              StringLike:
                "aws:PrincipalArn":
                  - "arn:aws:iam::*:root"
        target_ids:
          - "ou-xxxx-11111111"  # Attach to core OU
        import_policy_id: "p-def67890"
```

### Phase 3: Import SCPs

```bash
# Import each SCP
atmos terraform apply aws-scp/deny-leaving-org -s <namespace>-gbl-root
atmos terraform apply aws-scp/deny-root-access -s <namespace>-gbl-root
```

### Phase 4: Remove from Old Component State

> [!CAUTION]
> Use `terraform state rm` to remove resources from state without destroying them.

```bash
# List SCP resources in old state
atmos terraform state list account -s <namespace>-gbl-root | grep service_control

# Remove each SCP and its attachments from old state
atmos terraform state rm account -s <namespace>-gbl-root \
  'module.organization_service_control_policies.aws_organizations_policy.this["DenyLeavingOrganization"]'

atmos terraform state rm account -s <namespace>-gbl-root \
  'module.organization_service_control_policies.aws_organizations_policy_attachment.this["DenyLeavingOrganization"]'
```

### Phase 5: Clean Up

After successful import, remove `import_policy_id` from each configuration:

```yaml
components:
  terraform:
    aws-scp/deny-leaving-org:
      vars:
        policy_name: DenyLeavingOrganization
        # Remove after import:
        # import_policy_id: "p-abc12345"
```

---

## Policy Definition Formats

### Using policy_statements (Recommended)

Structured format that's easier to maintain:

```yaml
vars:
  policy_statements:
    - sid: DenyLeaveOrganization
      effect: Deny
      actions:
        - organizations:LeaveOrganization
      resources:
        - "*"
    - sid: DenyCloudTrailModification
      effect: Deny
      actions:
        - cloudtrail:DeleteTrail
        - cloudtrail:StopLogging
      resources:
        - "*"
```

### Using policy_content (Raw JSON)

For complex policies or when migrating existing JSON:

```yaml
vars:
  policy_content: |
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "DenyLeaveOrganization",
          "Effect": "Deny",
          "Action": "organizations:LeaveOrganization",
          "Resource": "*"
        }
      ]
    }
```

---

## Attaching SCPs to Different Targets

```yaml
# Attach to organization root (all accounts)
aws-scp/org-wide-policy:
  vars:
    target_ids:
      - "r-xxxx"

# Attach to specific OU
aws-scp/production-policy:
  vars:
    target_ids:
      - !terraform.output aws-organizational-unit/plat organizational_unit_id

# Attach to multiple targets
aws-scp/multi-target-policy:
  vars:
    target_ids:
      - !terraform.output aws-organizational-unit/plat organizational_unit_id
      - !terraform.output aws-organizational-unit/core organizational_unit_id

# Attach to specific account
aws-scp/account-specific-policy:
  vars:
    target_ids:
      - !terraform.output aws-account/core-security account_id

# Create policy without attachment
aws-scp/unattached-policy:
  vars:
    attach_to_target: false
```

---

## Troubleshooting

### Import Block Not Working

Ensure you're using OpenTofu >= 1.7.0 (required for `for_each` in `import` blocks).

If you excluded `imports.tf` when vendoring, use manual import:

```bash
atmos terraform import aws-scp/deny-leaving-org -s <namespace>-gbl-root \
  'aws_organizations_policy.this[0]' 'p-abc12345'
```

### Policy Already Managed Error

This means the SCP is being managed in both states. Complete Phase 4 first.

### Attachment Conflict

If the attachment exists, you may need to import it separately or detach/reattach after migration.

---

## References

- [OpenTofu Import Blocks](https://opentofu.org/docs/language/import/)
- [AWS Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [SCP Syntax](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_syntax.html)
