variable "region" {
  type        = string
  description = "AWS Region"
}

variable "policy_name" {
  type        = string
  description = "The name of the Service Control Policy. Defaults to module.this.id"
  default     = null
}

variable "policy_description" {
  type        = string
  description = "Description of the SCP"
  default     = "Service Control Policy managed by Terraform"
}

variable "policy_content" {
  type        = string
  description = "The JSON policy document for the SCP. If not provided, policy_statements will be used to generate the policy."
  default     = null
}

variable "policy_statements" {
  type = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  description = "List of policy statements to generate the SCP. Alternative to policy_content."
  default     = []
}

variable "target_id" {
  type        = string
  description = "The ID of the organization root, OU, or account to attach the SCP to"
  default     = null
}

variable "skip_destroy" {
  type        = bool
  description = "If true, the policy will be detached from the target but not destroyed when removed from Terraform"
  default     = false
}

variable "attach_to_target" {
  type        = bool
  description = "Whether to attach the SCP to a target. Set to false to create the policy without attaching it."
  default     = true
}

variable "service_control_policies_config_paths" {
  type        = list(string)
  description = <<-EOT
    List of paths to Service Control Policy catalog files.
    Can be local paths or remote URLs (e.g., GitHub raw URLs).
    Catalogs provide reusable SCP policy statements referenced by SID.

    Example:
    service_control_policies_config_paths = [
      "https://raw.githubusercontent.com/cloudposse/terraform-aws-service-control-policies/0.15.1/catalog/organization-policies.yaml"
    ]
    EOT
  default     = []
}

variable "policy_sid" {
  type        = string
  description = <<-EOT
    The SID (Statement ID) of a policy from the loaded catalog.
    When set, the policy statements will be looked up from the catalog
    loaded via service_control_policies_config_paths.

    Mutually exclusive with policy_statements and policy_content.

    Example: "DenyLeavingOrganization"
    EOT
  default     = null
}

variable "policy_name_from_sid" {
  type        = bool
  description = "When true and policy_sid is set, automatically use the SID as the policy_name if policy_name is not explicitly provided"
  default     = true
}

variable "policy_id" {
  type        = string
  description = <<-EOT
    The ID of an existing SCP to attach to the target (instead of creating a new policy).
    Use this to attach the same policy to multiple targets. Reference the policy_id output
    from the component instance that creates the policy.

    When set, the policy will NOT be created - only the attachment will be managed.
    Mutually exclusive with policy_sid, policy_statements, and policy_content.

    Example: !terraform.output aws-scp/deny-root-access policy_id
    EOT
  default     = null
}
