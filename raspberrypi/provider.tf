terraform {
  required_version = ">= 1.14.0, < 1.15.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# No provider block needed - we are not creating any cloud / VM resource here.
# This config only turns var.pi_hosts into an Ansible inventory + does a
# connectivity check against hosts that already exist.
