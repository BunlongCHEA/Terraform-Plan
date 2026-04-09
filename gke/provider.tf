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

provider "google" {
  # Authenticate using service account JSON (base64 decoded at runtime)
  # Set via GOOGLE_CREDENTIALS env var OR credentials file path
  credentials = base64decode(var.gke_service_account_b64)
  project     = var.gcp_project_id
  region      = var.region
  zone        = var.zone
}