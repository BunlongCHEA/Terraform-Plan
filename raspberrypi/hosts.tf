# ---------------------------------------------------------------------------
# IMPORTANT: There is no compute resource block here on purpose.
# Unlike ../digitalocean/droplets.tf or ../gke/vm.tf, this folder never
# provisions a VM - var.pi_hosts already exist (your Raspberry Pi 5, reachable
# through its Cloudflare Tunnel / SSH config alias).
# ---------------------------------------------------------------------------

# Optional sanity check: confirm each host is reachable over SSH before we
# bother generating the inventory / running Ansible against it.
resource "null_resource" "check_ssh_reachable" {
  for_each = var.skip_ssh_check ? {} : { for h in var.pi_hosts : h.name => h }

  provisioner "local-exec" {
    command = "ssh -F ${pathexpand(var.ssh_config_path)} -o BatchMode=yes -o ConnectTimeout=30 ${each.value.ansible_host} 'echo reachable: $(hostname)'"
  }

  triggers = {
    ansible_host = each.value.ansible_host
  }
}