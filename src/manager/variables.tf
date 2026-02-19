variable "region" {
  type        = string
  description = "AWS Region"
}

variable "service_control_policies_config_paths" {
  type        = list(string)
  description = <<-EOT
    List of paths to Service Control Policy catalog files.
    Can be local paths or remote URLs (e.g., GitHub raw URLs).
    The manager will create ALL policies defined in these catalogs.

    Example:
    service_control_policies_config_paths = [
      "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/organization-policies.yaml",
      "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/iam-policies.yaml"
    ]
    EOT
  default     = []
}

variable "custom_policies" {
  type = map(object({
    sid           = string
    name          = string
    description   = optional(string, "Managed by Terraform")
    effect        = string
    actions       = optional(list(string))
    not_actions   = optional(list(string))
    resources     = optional(list(string))
    not_resources = optional(list(string))
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  description = <<-EOT
    Map of custom policies to create alongside catalog policies.
    Key is the policy identifier (used in outputs), value is the policy definition.

    NOTE: Use either 'actions' OR 'not_actions' (mutually exclusive).
          Use either 'resources' OR 'not_resources' (mutually exclusive).

    Example:
    custom_policies = {
      CustomDenyEC2 = {
        sid         = "CustomDenyEC2Termination"
        name        = "CustomDenyEC2Termination"
        description = "Prevent EC2 instance termination"
        effect      = "Deny"
        actions     = ["ec2:TerminateInstances"]
        resources   = ["*"]
      }
      AllowAllExceptIAM = {
        sid          = "AllowAllExceptIAM"
        name         = "AllowAllExceptIAM"
        description  = "Allow all actions except IAM"
        effect       = "Allow"
        not_actions  = ["iam:*"]
        resources    = ["*"]
      }
    }
    EOT
  default     = {}
}
