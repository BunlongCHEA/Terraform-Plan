#!/bin/bash

# ===========================================
# Terraform Run Script - Existing Host(s) (e.g. Raspberry Pi 5)
# ===========================================
# Unlike ../digitalocean/terraform_run.sh and ../gke/terraform_run.sh, this
# script never creates a VM. var.pi_hosts (variable.tf) already exist and are
# reachable through their ~/.ssh/config alias (e.g. a Cloudflare Tunnel).
#
# Terraform here only renders output/inventory.ini from variables, then the
# SAME Ansible playbooks used for DigitalOcean/GKE are run against it.
#
# Usage: ./terraform_run.sh [init|plan|apply|destroy|output|all]
# ===========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# SSH config file holding the existing host alias(es) - NOT a per-cloud private key
SSH_CONFIG_PATH="$HOME/.ssh/config"

# Inventory and playbook paths
INVENTORY="$SCRIPT_DIR/output/inventory.ini"
PLAYBOOK_ANSIBLE="$SCRIPT_DIR/ansible_install_ansible.yml"
PLAYBOOK_RANCHER="$SCRIPT_DIR/ansible_install_rancher.yml"
PLAYBOOK_RANCHER_MULTI="$SCRIPT_DIR/ansible_install_rancher_multi.yml"
PLAYBOOK_ARGOCD="$SCRIPT_DIR/ansible_install_argocd.yml"
PLAYBOOK_PROMETHEUS="$SCRIPT_DIR/ansible_install_prometheus_grafana.yml"
SERVER="os_servers"

# Uninstall playbook paths
UNINSTALL_PROMETHEUS="$SCRIPT_DIR/ansible_uninstall_prometheus_grafana.yml"
UNINSTALL_ARGOCD="$SCRIPT_DIR/ansible_uninstall_argocd.yml"
UNINSTALL_RANCHER="$SCRIPT_DIR/ansible_uninstall_rancher.yml"

# ===========================================
# Functions
# ===========================================

print_header() {
    echo ""
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✔ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✖ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Create necessary directories
create_directories() {
    print_header "Creating Directories"

    mkdir -p output
    print_success "Created: output/"

    mkdir -p rancher
    print_success "Created: rancher/"

    mkdir -p argocd
    print_success "Created: argocd/"
}

# Make sure terraform.tfvars exists (defines var.pi_hosts)
check_tfvars() {
    print_header "Checking pi_hosts Variable"

    if [ -f "terraform.tfvars" ]; then
        print_success "terraform.tfvars found"
        return 0
    fi

    print_warning "terraform.tfvars not found!"
    print_info "Copy terraform.tfvars.example => terraform.tfvars"
    print_info "Then set pi_hosts to your existing host(s), e.g. ansible_host = \"pi5-1-remote\""
}

# Initialize Terraform
terraform_init() {
    print_header "Initializing Terraform"
    terraform init -upgrade
    print_success "Terraform initialized successfully"
}

# Validate Terraform configuration
terraform_validate() {
    print_header "Validating Terraform Configuration"
    terraform validate
    print_success "Terraform configuration is valid"
}

# Plan Terraform changes
terraform_plan() {
    print_header "Planning Terraform Changes"
    terraform plan
    print_success "Terraform plan completed"
}

# Apply Terraform changes -- NOTE: this does NOT create a VM.
# It only (1) checks SSH reachability of var.pi_hosts and
# (2) renders output/inventory.ini + output/hosts_info.txt from variables.
terraform_apply() {
    print_header "Applying Terraform Changes (generates inventory only - no VM created)"
    terraform apply -auto-approve
    print_success "Inventory generated from pi_hosts variable"
}

# Show Terraform outputs
terraform_output() {
    print_header "Terraform Outputs"
    terraform output
}

# Destroy -- only removes the generated local files (inventory, hosts_info),
# it NEVER deletes your Raspberry Pi since Terraform never created it.
terraform_destroy() {
    print_header "Destroying Generated Files (your Raspberry Pi is NOT touched)"
    print_warning "This will remove the generated inventory.ini / hosts_info.txt only."
    read -p "Are you sure?  (yes/no): " confirm

    if [ "$confirm" == "yes" ]; then
        terraform destroy -auto-approve
        print_success "Generated files removed"
    else
        print_info "Destroy cancelled"
    fi
}

# Test Ansible connectivity
test_ansible() {
    print_header "Testing Ansible Connectivity"

    if [ -f "$INVENTORY" ]; then
        print_info "Testing connection to all hosts..."
        ansible -i "$INVENTORY" "$SERVER" -m ping
        print_success "Ansible connectivity test completed"
    else
        print_error "Inventory file not found: $INVENTORY"
        print_info "Run 'terraform apply' first to generate inventory"
    fi
}

# Run Ansible playbook for installing Ansible
run_ansible_ansible() {
    print_header "Running Ansible Playbook - Install Ansible"

    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory file not found: $INVENTORY"
        print_info "Run 'terraform apply' first"
        return 1
    fi

    if [ ! -f "$PLAYBOOK_ANSIBLE" ]; then
        print_error "Playbook not found: $PLAYBOOK_ANSIBLE"
        return 1
    fi

    print_info "Running playbook -- Installing Python3, pip, Ansible:  $PLAYBOOK_ANSIBLE"
    ansible-playbook -i "$INVENTORY" "$PLAYBOOK_ANSIBLE"
    print_success "Ansible playbook completed"
}

# Run Ansible playbook for installing Rancher
run_ansible_rancher() {
    print_header "Running Ansible Playbook - Install K3s + Rancher"

    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory not found: $INVENTORY"
        return 1
    fi

    if [ ! -f "$PLAYBOOK_RANCHER" ]; then
        print_error "Playbook not found: $PLAYBOOK_RANCHER"
        return 1
    fi

    print_info "This will install:"
    print_info "  - K3s (Lightweight Kubernetes)"
    print_info "  - Helm"
    print_info "  - cert-manager"
    print_info "  - Rancher Server"
    echo ""

    HOST_COUNT=$(grep -c "ansible_host=" "$INVENTORY" 2>/dev/null || echo "0")

    echo "Select installation mode:"
    echo "  1) Single node (first server only)"
    echo "  2) Multi-node cluster (all $HOST_COUNT servers)"
    read -p "Choice [1-2]: " install_mode

    echo ""
    print_warning "This may take 10-20 minutes..."
    echo ""

    read -p "Continue? (yes/no): " confirm
    [ "$confirm" != "yes" ] && return 0

    case $install_mode in
        1)
            print_info "Installing on first server only..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK_RANCHER" --limit "$SERVER[0]" -v
            ;;
        2)
            print_info "Installing multi-node cluster..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK_RANCHER_MULTI" -v
            ;;
        *)
            print_info "Installing on first server only (default)..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK_RANCHER" --limit "$SERVER[0]" -v
            ;;
    esac

    print_success "Rancher installation completed!"
    echo ""

    FIRST_HOST=$(grep -m1 "ansible_host=" "$INVENTORY" | grep -oP 'ansible_host=\K\S+')

    print_header "RANCHER ACCESS INFORMATION"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${GREEN}  SSH alias:  ${FIRST_HOST}${NC}"
    echo -e "${YELLOW}  Use your Cloudflare Tunnel hostname / nip.io trick to reach the UI${NC}"
    echo -e "${YELLOW}  Bootstrap Password: admin${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo ""
    print_info "Accept the self-signed certificate in your browser"
}

# Run Ansible playbook for installing ArgoCD
run_ansible_argocd() {
    print_header "Running Ansible Playbook - Install ArgoCD"

    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory file not found: $INVENTORY"
        print_info "Run 'terraform apply' first"
        return 1
    fi

    if [ ! -f "$PLAYBOOK_ARGOCD" ]; then
        print_error "Playbook not found: $PLAYBOOK_ARGOCD"
        return 1
    fi

    print_info "Running playbook -- Installing ArgoCD:  $PLAYBOOK_ARGOCD"
    ansible-playbook -i "$INVENTORY" "$PLAYBOOK_ARGOCD"
    print_success "Ansible playbook completed"
}

# Run Ansible playbook for installing Prometheus Monitoring
run_ansible_prometheus() {
    print_header "Running Ansible Playbook - Install Prometheus"

    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory file not found: $INVENTORY"
        print_info "Run 'terraform apply' first"
        return 1
    fi

    if [ ! -f "$PLAYBOOK_PROMETHEUS" ]; then
        print_error "Playbook not found: $PLAYBOOK_PROMETHEUS"
        return 1
    fi

    print_info "Running playbook -- Installing Prometheus:  $PLAYBOOK_PROMETHEUS"
    ansible-playbook -i "$INVENTORY" "$PLAYBOOK_PROMETHEUS"
    print_success "Ansible playbook completed"
}

# ===========================================
# UNINSTALL FUNCTIONS
# ===========================================
uninstall_prometheus() {
    print_header "Uninstalling Prometheus & Grafana"

    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory not found: $INVENTORY"
        return 1
    fi

    print_warning "This will remove:"
    print_warning "  - Prometheus"
    print_warning "  - Node Exporter"
    print_warning "  - Grafana"
    print_warning "  - All metrics data"
    print_warning "  - All dashboards"
    echo ""

    read -p "Continue? (yes/no): " confirm
    [ "$confirm" != "yes" ] && return 0

    ansible-playbook -i "$INVENTORY" "$UNINSTALL_PROMETHEUS" -v
    print_success "Prometheus & Grafana uninstalled"
}

uninstall_argocd() {
    print_header "Uninstalling ArgoCD"

    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory not found: $INVENTORY"
        return 1
    fi

    print_warning "This will remove:"
    print_warning "  - ArgoCD server"
    print_warning "  - All ArgoCD applications"
    print_warning "  - ArgoCD CRDs"
    print_warning "  - ArgoCD namespace"
    echo ""

    read -p "Continue? (yes/no): " confirm
    [ "$confirm" != "yes" ] && return 0

    ansible-playbook -i "$INVENTORY" "$UNINSTALL_ARGOCD" -v
    print_success "ArgoCD uninstalled"
}

uninstall_rancher() {
    print_header "Uninstalling Rancher & K3s"

    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory not found: $INVENTORY"
        return 1
    fi

    print_warning "This will remove:"
    print_warning "  - Rancher server"
    print_warning "  - K3s (entire Kubernetes cluster)"
    print_warning "  - All deployed applications"
    print_warning "  - All Kubernetes data"
    print_warning "  - Helm"
    print_warning "  - kubectl"
    echo ""

    read -p "Are you ABSOLUTELY sure? (type 'yes' to confirm): " confirm
    [ "$confirm" != "yes" ] && return 0

    ansible-playbook -i "$INVENTORY" "$UNINSTALL_RANCHER" -v
    print_success "Rancher & K3s uninstalled"
}

uninstall_menu() {
    print_header "Uninstall Menu"

    echo "Select what to uninstall:"
    echo "  1) Prometheus & Grafana"
    echo "  2) ArgoCD"
    echo "  3) Rancher & K3s (WARNING: Removes entire cluster)"
    echo "  4) Everything (Prometheus + ArgoCD + Rancher)"
    echo "  5) Back to main menu"
    echo ""
    read -p "Enter Choice: " uninstall_choice

    case $uninstall_choice in
        1) uninstall_prometheus ;;
        2) uninstall_argocd ;;
        3) uninstall_rancher ;;
        4)
            print_warning "This will uninstall EVERYTHING!"
            read -p "Type 'yes' to confirm: " confirm
            if [ "$confirm" == "yes" ]; then
                uninstall_prometheus
                uninstall_argocd
                uninstall_rancher
            fi
            ;;
        5) return 0 ;;
        *) print_error "Invalid choice" ;;
    esac
}

# Full workflow -- no VM creation, just inventory generation + install choice
run_all() {
    print_header "Running Full Workflow (existing host(s) - no VM created)"

    create_directories
    check_tfvars
    terraform_init
    terraform_validate
    terraform_plan

    echo ""
    read -p "Proceed with apply (generate inventory)? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Apply cancelled"
        exit 0
    fi

    terraform_apply
    terraform_output

    test_ansible

    echo ""
    echo "Select installation option:"
    echo "  1) Install Ansible (Python3, pip, Ansible)"
    echo "  2) Install Rancher (cert-manager, Kubectl, K3s, Helm)"
    echo "  3) Install ArgoCD (ArgoCD, cert-manager)"
    echo "  4) Install Prometheus (Prometheus, Node Exporter)"
    echo "  5) All of the above"
    echo "  6) Skip"
    read -p "Enter Choice: " install_choice

    case $install_choice in
        1) run_ansible_ansible ;;
        2) run_ansible_rancher ;;
        3) run_ansible_argocd ;;
        4) run_ansible_prometheus ;;
        5) run_ansible_ansible; run_ansible_rancher; run_ansible_argocd; run_ansible_prometheus ;;
        6) print_info "Skipping software installation" ;;
    esac

    print_header "Workflow Complete!"
}

# Display help
show_help() {
    echo "
Usage: $0 [command]

Commands:
  all            Full workflow (init -> apply [inventory only] -> choose installation)
  init           Initialize Terraform
  validate       Validate configuration
  plan           Preview changes
  apply          Apply changes (renders inventory.ini from pi_hosts - no VM created)
  output         Show outputs
  destroy        Remove generated inventory files (does NOT touch your Raspberry Pi)
  test           Test Ansible connectivity
  ansible        Run basic software Ansible playbook
  rancher        Run Rancher/K3s installation playbook
  argocd         Run ArgoCD installation playbook
  prometheus     Run Prometheus & Grafana installation playbook
  uninstall      Show uninstall menu
  help           Show this help

SSH Config (Host aliases, e.g. pi5-1-remote): $SSH_CONFIG_PATH

Examples:
  $0 all              # Full workflow with options
  $0 rancher          # Install Rancher
  $0 uninstall        # Uninstall components
  $0 destroy          # Remove generated inventory (Pi is untouched)
"
}

# ===========================================
# Main Script
# ===========================================

print_header "Terraform & Ansible Deployment Script - Existing Host(s)"
print_info "Directory:  $SCRIPT_DIR"
print_info "SSH Config:  $SSH_CONFIG_PATH"
print_info "NOTE: No VM is created here - var.pi_hosts must already exist & be reachable"

case "${1:-}" in
    all) run_all ;;
    init) create_directories; check_tfvars; terraform_init ;;
    validate) terraform_validate ;;
    plan) terraform_plan ;;
    apply) check_tfvars; terraform_apply; terraform_output ;;
    output) terraform_output ;;
    destroy) terraform_destroy ;;
    test) test_ansible ;;
    ansible) run_ansible_ansible ;;
    rancher) run_ansible_rancher ;;
    argocd) run_ansible_argocd ;;
    prometheus) run_ansible_prometheus ;;
    uninstall) uninstall_menu ;;
    help|--help|-h) show_help ;;
    *)
        # Default: show menu (same numbering as digitalocean/gke -
        # installs still start at choice 5, just without any VM-creation step)
        echo ""
        echo "Select an option:"
        echo "  1) Run Full workflow (With installation options at the end)"
        echo "  2) Initialize Terraform"
        echo "  3) Plan changes"
        echo "  4) Apply changes (generate inventory.ini from pi_hosts - no VM created)"
        echo "  5) Run Ansible playbook (Install Ansible)"
        echo "  6) Run Ansible playbook (Install Rancher)"
        echo "  7) Run Ansible playbook (Install ArgoCD)"
        echo "  8) Run Ansible playbook (Install Prometheus + Grafana + Node Exporter)"
        echo "  9) Test Ansible connectivity"
        echo "  10) Show outputs"
        echo "  11) Uninstall components"
        echo "  12) Destroy generated files (Pi is NOT touched)"
        echo "  0) Exit"
        echo ""
        read -p "Enter choice: " choice

        case $choice in
            1) run_all ;;
            2) create_directories; check_tfvars; terraform_init ;;
            3) terraform_plan ;;
            4) check_tfvars; terraform_apply; terraform_output ;;
            5) run_ansible_ansible ;;
            6) run_ansible_rancher ;;
            7) run_ansible_argocd ;;
            8) run_ansible_prometheus ;;
            9) test_ansible ;;
            10) terraform_output ;;
            11) uninstall_menu ;;
            12) terraform_destroy ;;
            0) echo "Exited... "; exit 0 ;;
            *) print_error "Invalid option"; exit 1 ;;
        esac
        ;;
esac

echo ""
print_success "Done!"
