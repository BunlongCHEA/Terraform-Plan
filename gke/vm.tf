# Create GCE VM instances (equivalent to DigitalOcean Droplets)
resource "google_compute_instance" "os_servers" {
  count        = var.vm_count
  name         = "${var.project_name}-vm-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["terraform", "ansible-managed", var.project_name]

  # Boot disk — OS image
  boot_disk {
    initialize_params {
      image = "projects/${var.vm_os_project}/global/images/family/${var.vm_os}"
      size  = 20  # GB
      type  = "pd-standard"
    }
  }

  # Network — default VPC, external IP for SSH access
  network_interface {
    network = "default"
    access_config {
      # Ephemeral public IP — required for SSH + Ansible
    }
  }

  # SSH public key injected via GCP metadata
  # Format: "username:ssh-rsa AAAA..."
  metadata = {
    ssh-keys = "${var.ssh_user}:${local.public_key_openssh}"
  }

  # Allow SSH through firewall
  metadata_startup_script = "echo 'VM ready'"

  lifecycle {
    create_before_destroy = true
  }
}

# Firewall rule — allow SSH from anywhere (restrict in production)
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_name}-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["terraform"]
}

# Wait for SSH to be ready on all VMs — same pattern as digitalocean/droplets.tf
resource "null_resource" "wait_for_ssh" {
  count = var.vm_count

  depends_on = [google_compute_instance.os_servers]

  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection successful!'",
      "echo 'Hostname: ' $(hostname)",
      "echo 'IP: ' $(hostname -I)",
      "cat /etc/os-release | grep PRETTY_NAME"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = local.private_key_pem
      host        = google_compute_instance.os_servers[count.index].network_interface[0].access_config[0].nat_ip
      timeout     = "2m"
    }
  }

  triggers = {
    instance_id = google_compute_instance.os_servers[count.index].id
  }
}