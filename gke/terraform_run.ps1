# Create necessary directories
New-Item -ItemType Directory -Force -Path "templates"
New-Item -ItemType Directory -Force -Path "ssh_keys"
New-Item -ItemType Directory -Force -Path "output"

# Set DigitalOcean token (or use terraform.tfvars)
# $env:TF_VAR_do_token = "digitalocean_api_token"

# Initialize Terraform
terraform init -upgrade

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Apply changes (create infrastructure)
terraform apply -auto-approve

# View outputs
terraform output

# To destroy everything when done
# terraform destroy -auto-approve