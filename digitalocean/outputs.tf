# Save IP addresses and SSH info to file
resource "local_file" "inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    droplets     = digitalocean_droplet.os_family
    ssh_key_path = local_file.private_key.filename
  })
  filename = "${path.module}/output/inventory.ini"

  depends_on = [null_resource.wait_for_ssh]
}

resource "local_file" "hosts_info" {
  content = templatefile("${path.module}/templates/hosts_info.tftpl", {
    droplets     = digitalocean_droplet.os_family
    ssh_key_path = abspath(local_file.private_key.filename)
  })
  filename = "${path.module}/output/hosts_info.txt"

  depends_on = [null_resource.wait_for_ssh]
}

# Output to console
output "droplet_ips" {
  description = "IP addresses of created droplets"
  value = {
    for droplet in digitalocean_droplet.os_family : 
    droplet.name => droplet.ipv4_address
  }
}

output "ssh_private_key_path" {
  description = "Path to SSH private key"
  value       = abspath(local_file.private_key.filename)
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to each droplet"
  value = [
    for droplet in digitalocean_droplet.os_family :
    "ssh -i ${abspath(local_file.private_key.filename)} root@${droplet.ipv4_address}"
  ]
}