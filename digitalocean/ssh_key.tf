# Generate SSH key pair locally (only if not exists)
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Check if SSH key already exists in DigitalOcean
data "digitalocean_ssh_keys" "existing" {}

locals {
  existing_key_names = [for key in data.digitalocean_ssh_keys.existing.ssh_keys : key.name]
  key_exists         = contains(local.existing_key_names, var.ssh_key_name)
}

# Create SSH key in DigitalOcean only if it doesn't exist
resource "digitalocean_ssh_key" "default" {
  count      = local.key_exists ? 0 : 1
  name       = var.ssh_key_name
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Get existing key if it exists
data "digitalocean_ssh_key" "existing" {
  count = local.key_exists ? 1 : 0
  name  = var.ssh_key_name
}

# Determine SSH key ID to use for other use case
locals {
  ssh_key_id = local.key_exists ? data.digitalocean_ssh_key.existing[0].id : digitalocean_ssh_key.default[0].id
}

# Save private key to local file
resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/ssh_keys/id_rsa_digitalocean"
  file_permission = "0600"
}

# Save public key to local file
resource "local_file" "public_key" {
  content         = tls_private_key.ssh_key.public_key_openssh
  filename        = "${path.module}/ssh_keys/id_rsa_digitalocean.pub"
  file_permission = "0644"
}

# Fix Windows permissions for private key
resource "null_resource" "fix_windows_permissions" {
  depends_on = [local_file.private_key]

  provisioner "local-exec" {
    command     = <<-EOT
      icacls "${replace(abspath(local_file.private_key.filename), "/", "\\")}" /inheritance:r /grant:r "%USERNAME%: F"
    EOT
    interpreter = ["cmd", "/c"]
  }

  triggers = {
    key_id = tls_private_key.ssh_key.id
  }
}

# Create a helper batch script for SSH
resource "local_file" "ssh_helper" {
  content  = <<-EOT
@echo off
REM SSH Connection Helper Script
REM Usage: ssh_connect.bat [1|2|3] or ssh_connect.bat <IP_ADDRESS>

set KEY_PATH=${replace(abspath(local_file.private_key.filename), "/", "\\")}

if "%1"=="" (
    echo Usage: ssh_connect.bat [droplet_number] or ssh_connect.bat [IP_ADDRESS]
    echo.
    echo Available droplets:
    type "${replace(path.module, "/", "\\")}\\output\\hosts_info.txt"
    exit /b 1
)

echo Connecting with key: %KEY_PATH%
ssh -i "%KEY_PATH%" -o StrictHostKeyChecking=no root@%1
EOT
  filename = "${path.module}/ssh_connect.bat"
}