# Install Python3, pip, and Ansible on all droplets
resource "null_resource" "install_software" {
  count = var.droplet_count

  depends_on = [null_resource.wait_for_ssh]

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",

      "echo '=== Detecting Operating System ==='",
      
      # Detect OS type
      "if [ -f /etc/os-release ]; then",
      "  . /etc/os-release",
      "  OS_ID=$ID",
      "  OS_VERSION=$VERSION_ID",
      "  echo \"Detected OS: $OS_ID $OS_VERSION\"",
      "else",
      "  echo 'Cannot detect OS. /etc/os-release not found.'",
      "  exit 1",
      "fi",
      
      # Ubuntu / Debian installation
      "if [[ \"$OS_ID\" == \"ubuntu\" || \"$OS_ID\" == \"debian\" ]]; then",
      "  echo '=== Ubuntu/Debian detected - Using APT ==='",
      "  ",
      "  echo '--- Updating system packages ---'",
      "  apt-get update -y",
      "  apt-get upgrade -y",
      "  ",
      "  echo '--- Installing Python3 and pip ---'",
      "  apt-get install -y python3 python3-pip python3-venv python3-full",
      "  ",
      "  echo '--- Installing Ansible ---'",
      "  apt-get install -y software-properties-common",
      "  add-apt-repository --yes --update ppa:ansible/ansible || true",
      "  apt-get install -y ansible",
      "  ",
      
      # RHEL / CentOS / Rocky / AlmaLinux / Fedora installation
      "elif [[ \"$OS_ID\" == \"rhel\" || \"$OS_ID\" == \"centos\" || \"$OS_ID\" == \"rocky\" || \"$OS_ID\" == \"almalinux\" || \"$OS_ID\" == \"fedora\" ]]; then",
      "  echo '=== RHEL-based OS detected ==='",
      "  ",
      "  # Determine package manager (dnf for RHEL 8+, yum for older)",
      "  if command -v dnf &> /dev/null; then",
      "    PKG_MGR='dnf'",
      "    echo '--- Using DNF package manager ---'",
      "  else",
      "    PKG_MGR='yum'",
      "    echo '--- Using YUM package manager ---'",
      "  fi",
      "  ",
      "  echo '--- Updating system packages ---'",
      "  $PKG_MGR update -y",
      "  ",
      "  echo '--- Installing EPEL repository ---'",
      "  if [[ \"$OS_ID\" != \"fedora\" ]]; then",
      "    $PKG_MGR install -y epel-release || $PKG_MGR install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm || true",
      "  fi",
      "  ",
      "  echo '--- Installing Python3 and pip ---'",
      "  $PKG_MGR install -y python3 python3-pip python3-devel",
      "  ",
      "  echo '--- Installing Ansible ---'",
      "  # Try installing from package manager first",
      "  if [[ \"$OS_ID\" == \"fedora\" ]]; then",
      "    $PKG_MGR install -y ansible",
      "  else",
      "    # For RHEL/CentOS/Rocky/Alma, use pip if package not available",
      "    $PKG_MGR install -y ansible-core || python3 -m pip install --upgrade pip && python3 -m pip install ansible",
      "  fi",
      "fi",

      "echo ''",
      "echo '=== Verifying installations ==='",
      "echo '--- Python3 Version ---'",
      "python3 --version",
      "echo '--- Pip Version ---'",
      "pip3 --version || python3 -m pip --version",
      "echo '--- Ansible Version ---'",
      "ansible --version",
      "echo ''",
      "echo '=== Installation complete on ${digitalocean_droplet.os_family[count.index].name} ==='",
      "echo \"=== OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2) ===\""
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = digitalocean_droplet.os_family[count.index].ipv4_address
      timeout     = "10m"
    }
  }

# Trigger re-execution if droplet_id changes 
# (e.g., the original Droplet is destroyed and a new one with a different ID is created)
  triggers = {
    droplet_id = digitalocean_droplet.os_family[count.index].id
  }
}

# Generate summary after all installations complete
resource "local_file" "installation_summary" {
  content = templatefile("${path.module}/templates/summary.tftpl", {
    droplets     = digitalocean_droplet.os_family
    ssh_key_path = abspath(local_file.private_key.filename)
    timestamp    = timestamp()
  })
  filename = "${path.module}/output/installation_summary.md"

  depends_on = [null_resource.install_software]
}