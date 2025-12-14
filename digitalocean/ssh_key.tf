locals {
  # Define SSH key file paths using variable
  private_key_path = "${var.ssh_path}/id_rsa_digitalocean"
  public_key_path  = "${var.ssh_path}/id_rsa_digitalocean.pub"
  
  # Check if keys already exist locally
  keys_exist = fileexists(local.private_key_path)
}

# Generate new SSH key only if local files don't exist
resource "tls_private_key" "ssh_key" {
  count     = local.keys_exist ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Read existing private key if it exists
data "local_file" "existing_private_key" {
  count    = local.keys_exist ? 1 : 0
  filename = local.private_key_path
}

# Read existing public key if it exists
data "local_file" "existing_public_key" {
  count    = local.keys_exist ? 1 : 0
  filename = local.public_key_path
}


# Determine which keys to use (existing or newly generated)
locals {
  private_key_pem    = local.keys_exist ? data.local_file.existing_private_key[0].content : tls_private_key.ssh_key[0].private_key_pem
  public_key_openssh = local.keys_exist ? data.local_file.existing_public_key[0].content : tls_private_key.ssh_key[0].public_key_openssh
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
  public_key = local.public_key_openssh
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
  count           = local.keys_exist ? 0 : 1
  content         = tls_private_key.ssh_key[0].private_key_pem
  filename        = local.private_key_path
  file_permission = "0600"
}

# Save public key to local file -- ${path.module}/ssh_keys/id_rsa_digitalocean.pub
resource "local_file" "public_key" {
  count           = local.keys_exist ? 0 : 1
  content         = tls_private_key.ssh_key[0].public_key_openssh
  filename        = local.public_key_path
  file_permission = "0644"
}