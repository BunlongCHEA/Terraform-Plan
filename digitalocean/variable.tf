variable "do_token" {
  description = "DigitalOcean API Token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sgp1"  # Singapore, change as needed
}

variable "droplet_os" {
  description = "Operating system for the droplets"
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "droplet_size" {
  description = "Droplet size"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "droplet_count" {
  description = "Number of droplets to create"
  type        = number
  default     = 3
}

variable "ssh_key_name" {
  description = "Name for the SSH key in DigitalOcean"
  type        = string
  default     = "terraform-ansible-key"
}

variable "ssh_path" {
  description = "Name for the SSH key in DigitalOcean"
  type        = string
  default     = "/home/admin-ubuntu/.ssh"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "ansible-lab"
}