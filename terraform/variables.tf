variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "Name prefix / Project tag for all resources"
  type        = string
  default     = "mini-pacs"
}

variable "instance_type" {
  description = "EC2 instance type (OHIF is static; Orthanc needs ~1-2 GB RAM for small datasets)"
  type        = string
  default     = "t3.small"
}

variable "volume_size_gb" {
  description = "Root EBS volume size; DICOM files are stored here"
  type        = number
  default     = 30
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach HTTP (80). Set this to your own IP, e.g. [\"203.0.113.10/32\"]"
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0
    error_message = "Set at least one CIDR (your public IP /32)."
  }
}

variable "dicom_allowed_cidrs" {
  description = "CIDRs allowed to send DICOM (C-STORE) to port 4242. Empty = port closed."
  type        = list(string)
  default     = []
}

variable "basic_auth_user" {
  description = "Username for nginx basic auth"
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.basic_auth_user))
    error_message = "Use only letters, digits, '.', '_' or '-'."
  }
}

variable "basic_auth_password" {
  description = "Password for nginx basic auth"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.basic_auth_password) >= 12
    error_message = "Use a password of at least 12 characters."
  }
}

variable "compose_version" {
  description = "docker compose plugin version installed on the instance"
  type        = string
  default     = "v2.29.7"
}
