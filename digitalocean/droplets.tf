# Create Droplets in DigitalOcean
resource "digitalocean_droplet" "os_family" {
  count    = var.droplet_count
  name     = "${var.project_name}-${var.droplet_os}-${count.index + 1}"
  region   = var.region
  size     = var.droplet_size
  image    = var.droplet_os
  ssh_keys = [local.ssh_key_id]

  tags = [
    "terraform",
    "ansible-managed",
    var.project_name
  ]

  # Wait for droplet to be ready
  lifecycle {
    create_before_destroy = true
  }
}

# Wait for SSH to be available on all droplets
resource "null_resource" "wait_for_ssh" {
  count = var.droplet_count

  depends_on = [digitalocean_droplet.os_family]

  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection successful!'",
      "echo 'Hostname: ' $(hostname)",
      "echo 'IP: ' $(hostname -I)",
      "cat /etc/os-release | grep PRETTY_NAME"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = local.private_key_pem
      host        = digitalocean_droplet.os_family[count.index].ipv4_address
      timeout     = "1m"
    }
  }

  triggers = {
    droplet_id = digitalocean_droplet.os_family[count.index].id
  }
}