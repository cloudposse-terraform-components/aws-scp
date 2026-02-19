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

variable "target_ids" {
  type        = list(string)
  description = "The IDs of the organization roots, OUs, or accounts to attach the SCP to"
  default     = []
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
