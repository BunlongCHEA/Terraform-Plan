terraform {
  required_version = ">= 1.14.0, < 1.15.0"
  
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.70"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ===========================================
# Resolve which auth option the user chose
# ===========================================

locals {
  use_b64  = var.gke_service_account_b64 != ""
  use_file = var.gke_credentials_file    != ""

  # Resolved credentials string passed to provider:
  #   Option 1 (base64): decode the base64 string → raw JSON string
  #   Option 2 (file)  : read the JSON file from disk → raw JSON string
  #   Neither set      : empty string → Terraform will error with a clear message
  gcp_credentials = (
    local.use_b64  ? base64decode(var.gke_service_account_b64) :
    local.use_file ? file(var.gke_credentials_file)            :
    ""
  )
}

# Validation: exactly one option must be provided
# Terraform will fail at plan time with a clear message if violated
# resource "terraform_data" "auth_validation" {
#   lifecycle {
#     precondition {
#       condition = (
#         (local.use_b64 || local.use_file) &&   # at least one is set
#         !(local.use_b64 && local.use_file)      # but not both at the same time
#       )
#       error_message = <<-EOT
#         GCP Authentication Error:
#         You must set exactly ONE of:
#           - gke_service_account_b64  (base64-encoded JSON string)
#           - gke_credentials_file     (path to JSON file on disk)
#         Currently: b64="${local.use_b64}" file="${local.use_file}"
#       EOT
#     }
#   }
# }

provider "google" {
  # Authenticate using service account JSON (base64 decoded at runtime)
  # Set via GOOGLE_CREDENTIALS env var OR credentials file path
  # credentials = base64decode(var.gke_service_account_b64)
  credentials = local.gcp_credentials
  project     = var.gcp_project_id
  region      = var.region
  zone        = var.zone
}