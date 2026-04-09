locals {
  # Define SSH key file paths using variable
  private_key_path = "${var.ssh_path}/id_rsa_gke"
  public_key_path  = "${var.ssh_path}/id_rsa_gke.pub"
  
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

# Save private key to local file if newly generated
resource "local_file" "private_key" {
  count           = local.keys_exist ? 0 : 1
  content         = tls_private_key.ssh_key[0].private_key_pem
  filename        = local.private_key_path
  file_permission = "0600"
}

# Save public key to local file if newly generated
resource "local_file" "public_key" {
  count           = local.keys_exist ? 0 : 1
  content         = tls_private_key.ssh_key[0].public_key_openssh
  filename        = local.public_key_path
  file_permission = "0644"
}