variable "import_policy_id" {
  type        = string
  description = "The ID of an existing SCP to import"
  default     = null
}

import {
  for_each = var.import_policy_id != null && local.enabled ? toset([var.import_policy_id]) : toset([])
  to       = aws_organizations_policy.this[0]
  id       = each.value
}
