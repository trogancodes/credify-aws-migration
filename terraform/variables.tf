variable "aws_account_id" {
  type        = string
  description = "Expected lab account; prevents using the wrong credential profile."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Enter your actual 12-digit AWS lab account ID."
  }
}
variable "owner" {
  type = string
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.owner))
    error_message = "Use your real student email address for Owner."
  }
}
variable "region" {
  type    = string
  default = "af-south-1"
  validation {
    condition     = var.region == "af-south-1"
    error_message = "This reviewed kit is scoped to Cape Town. Do not silently deploy elsewhere."
  }
}
variable "phase" {
  type    = string
  default = "foundation"
  validation {
    condition     = contains(["foundation", "baseline", "replica", "tuned"], var.phase)
    error_message = "Use foundation, baseline, replica or tuned."
  }
}
variable "lab_settings_confirmed" {
  type        = bool
  default     = false
  description = "Acknowledge the reviewed lab classes, single NAT and Single-AZ settings."
}
variable "baseline_recorded" {
  type    = bool
  default = false
}
variable "tuning_completed" {
  type    = bool
  default = false
}
variable "odoo_initialized" {
  type        = bool
  default     = false
  description = "After Odoo setup and locking its database role, hides database management screens."
}
variable "enable_waf" {
  type        = bool
  default     = false
  description = "Budget-dependent CloudFront WAF. No advanced paid rule subscriptions."
}
variable "image_tag" {
  type        = string
  default     = "lab1"
  description = "Build once and retain the same tag/digest through both tests."
}
variable "odoo_uid" {
  type        = number
  default     = 101
  description = "Before baseline: set to id -u odoo from the actual built ERP image."
  validation {
    condition     = var.odoo_uid > 0 && floor(var.odoo_uid) == var.odoo_uid
    error_message = "Use the non-root numeric UID observed in your Odoo image."
  }
}
variable "odoo_gid" {
  type        = number
  default     = 101
  description = "Before baseline: set to id -g odoo from the actual built ERP image."
  validation {
    condition     = var.odoo_gid > 0 && floor(var.odoo_gid) == var.odoo_gid
    error_message = "Use the non-root numeric GID observed in your Odoo image."
  }
}
variable "allow_lab_data_deletion" {
  type        = bool
  default     = false
  description = "Only for approved teardown: disables RDS protection and permits emptying this versioned lab bucket."
}
