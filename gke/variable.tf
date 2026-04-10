# variable "gke_service_account_b64" {
#   description = "Base64-encoded GCP service account JSON key"
#   type        = string
#   sensitive   = true
# }
variable "gke_service_account_b64" {
  description = <<-EOT
    OPTION 1 — Base64-encoded GCP service account JSON.
    Generate: base64 -w 0 < your-key.json
    Leave as "" if using gke_credentials_file instead.
  EOT
  type      = string
  sensitive = true
  default   = ""
}

variable "gke_credentials_file" {
  description = <<-EOT
    OPTION 2 — Absolute path to GCP service account JSON file on disk.
    Linux/WSL example : /home/ubuntu/.gcp/my-project-key.json
    Windows WSL example: /mnt/d/keys/my-project-key.json
    Leave as "" if using gke_service_account_b64 instead.
  EOT
  type    = string
  default = ""

  # Validation runs at plan time — no sensitive value referenced
  validation {
    condition = !(
      var.gke_credentials_file == "" && var.gke_service_account_b64 == ""
    )
    error_message = "GCP auth error: set gke_service_account_b64 (Option 1) OR gke_credentials_file (Option 2). Both are currently empty."
  }

  validation {
    condition = !(
      var.gke_credentials_file != "" && var.gke_service_account_b64 != ""
    )
    error_message = "GCP auth error: set only ONE of gke_service_account_b64 OR gke_credentials_file — not both at the same time."
  }
}

variable "gcp_project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-southeast1"  # Singapore
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "asia-southeast1-a"
}

variable "vm_os" {
  description = "OS image for the VM (GCP image family)"
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "vm_os_project" {
  description = "GCP project that owns the OS image"
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "machine_type" {
  description = "GCP machine type"
  type        = string
  default     = "e2-medium"  # 2 vCPU, 4GB RAM
}

variable "vm_count" {
  description = "Number of VM instances to create"
  type        = number
  default     = 1
}

variable "ssh_key_name" {
  description = "Name tag for the SSH key"
  type        = string
  default     = "terraform-ansible-key"
}

variable "ssh_path" {
  description = "Local directory path containing SSH keys"
  type        = string
  default     = "/home/ubuntu/.ssh"
}

variable "project_name" {
  description = "Project name prefix for all GCP resources"
  type        = string
  default     = "ansible-lab"
}

variable "ssh_user" {
  description = "SSH username on the VM (must match GCP metadata)"
  type        = string
  default     = "ubuntu"
}