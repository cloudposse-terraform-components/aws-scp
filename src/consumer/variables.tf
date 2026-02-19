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
    DEPRECATED: Use the manager component (type: manager) for catalog-based policy creation.

    The consumer component does not support loading catalogs. To use catalog policies:
    1. Deploy a manager component instance to create policies from catalogs
    2. Reference the created policies via policy_id in consumer components

    Example:
      # Manager (creates catalog policies)
      component: aws-scp
      type: manager
      vars:
        service_control_policies_config_paths: [...]

      # Consumer (attaches catalog policies)
      component: aws-scp
      type: consumer
      vars:
        policy_id: !terraform.output scp-manager policy_ids["DenyLeavingOrganization"]
    EOT
  default     = []
}

variable "policy_sid" {
  type        = string
  description = <<-EOT
    DEPRECATED: Not supported in consumer component. Use manager component to create catalog policies.

    To use a catalog policy by SID:
    1. Deploy manager component with service_control_policies_config_paths
    2. Reference the created policy via policy_id in this consumer component

    Example:
      policy_id = !terraform.output scp-manager policy_ids["DenyLeavingOrganization"]

    Setting this variable will cause a precondition error with migration instructions.
    EOT
  default     = null
}

variable "policy_name_from_sid" {
  type        = bool
  description = "DEPRECATED: Not applicable in consumer component. This variable is ignored."
  default     = false
}

variable "policy_id" {
  type        = string
  description = <<-EOT
    The ID of an existing SCP to attach to the target (instead of creating a new policy).
    Use this to attach the same policy to multiple targets. Reference the policy_id output
    from the manager component or another policy-creating component.

    When set, the policy will NOT be created - only the attachment will be managed.
    Mutually exclusive with policy_statements and policy_content.

    Example (from manager):
      policy_id = !terraform.output scp-manager policy_ids["DenyLeavingOrganization"]

    Example (from another consumer):
      policy_id = !terraform.output scp-custom-policy policy_id
    EOT
  default     = null
}
