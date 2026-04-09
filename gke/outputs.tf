# Save IP addresses and SSH info to file
resource "local_file" "inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    servers      = google_compute_instance.os_servers
    ssh_key_path = local.private_key_path
    ssh_user     = var.ssh_user
  })
  filename   = "${path.module}/output/inventory.ini"
  depends_on = [null_resource.wait_for_ssh]
}

# Generate hosts info file
resource "local_file" "hosts_info" {
  content = templatefile("${path.module}/templates/hosts_info.tftpl", {
    servers      = google_compute_instance.os_servers
    ssh_key_path = local.private_key_path
    ssh_user     = var.ssh_user
  })
  filename   = "${path.module}/output/hosts_info.txt"
  depends_on = [null_resource.wait_for_ssh]
}

# Generate deployment summary (Markdown)
resource "local_file" "summary" {
  content = templatefile("${path.module}/templates/summary.tftpl", {
    servers      = google_compute_instance.os_servers
    ssh_key_path = local.private_key_path
    ssh_user     = var.ssh_user
    timestamp    = timestamp()
  })
  filename   = "${path.module}/output/summary.md"
  depends_on = [null_resource.wait_for_ssh]
}

# Console outputs
output "vm_ips" {
  description = "External IP addresses of created VMs"
  value = {
    for vm in google_compute_instance.os_servers :
    vm.name => vm.network_interface[0].access_config[0].nat_ip
  }
}

output "ssh_private_key_path" {
  description = "Path to SSH private key"
  value       = local.private_key_path
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to each VM"
  value = [
    for vm in google_compute_instance.os_servers :
    "ssh -i \"${local.private_key_path}\" ${var.ssh_user}@${vm.network_interface[0].access_config[0].nat_ip}"
  ]
}

output "ansible_command" {
  description = "Command to run Ansible playbook"
  value       = "ansible-playbook -i ${path.module}/output/inventory.ini ansible_install_ansible.yml"
}

output "inventory_file" {
  description = "Path to Ansible inventory file"
  value       = abspath("${path.module}/output/inventory.ini")
}

output "k3s_credentials" {
  description = "K3s cluster access credentials"
  value = {
    server_url = "https://${google_compute_instance.os_servers[0].network_interface[0].access_config[0].nat_ip}:6443"
    message    = "SSH to server and run: sudo cat /var/lib/rancher/k3s/server/node-token"
  }
  depends_on = [null_resource.wait_for_ssh]
}