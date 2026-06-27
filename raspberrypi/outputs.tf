# Write the Ansible inventory from var.pi_hosts only - no VM dependency.
resource "local_file" "inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    pi_hosts        = var.pi_hosts
    ssh_config_path = pathexpand(var.ssh_config_path)
  })
  filename = "${path.module}/output/inventory.ini"

  depends_on = [null_resource.check_ssh_reachable]
}

resource "local_file" "hosts_info" {
  content = templatefile("${path.module}/templates/hosts_info.tftpl", {
    pi_hosts        = var.pi_hosts
    ssh_config_path = pathexpand(var.ssh_config_path)
  })
  filename = "${path.module}/output/hosts_info.txt"

  depends_on = [null_resource.check_ssh_reachable]
}

output "pi_hosts" {
  description = "Existing hosts that will be managed by Ansible"
  value       = { for h in var.pi_hosts : h.name => h.ansible_host }
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to each host"
  value = [
    for h in var.pi_hosts :
    "ssh ${h.ansible_host}"
  ]
}

output "ansible_command" {
  description = "Command to run an Ansible playbook against these hosts"
  value       = "ansible-playbook -i ${path.module}/output/inventory.ini ansible_install_ansible.yml"
}

output "inventory_file" {
  description = "Path to the generated Ansible inventory file"
  value       = abspath("${path.module}/output/inventory.ini")
}