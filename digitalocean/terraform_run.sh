#!/bin/bash

# ===========================================
# Terraform Run Script for WSL Ubuntu
# ===========================================
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

# SSH key path (always in ~/.ssh)
SSH_PRIVATE_KEY="$HOME/.ssh/id_rsa_digitalocean"

# Inventory and playbook paths
INVENTORY="$SCRIPT_DIR/output/inventory.ini"
PLAYBOOK_ANSIBLE="$SCRIPT_DIR/ansible_install_ansible.yml"
PLAYBOOK_RANCHER="$SCRIPT_DIR/ansible_install_rancher.yml"
PLAYBOOK_RANCHER_MULTI="$SCRIPT_DIR/ansible_install_rancher_multi.yml"
PLAYBOOK_ARGOCD="$SCRIPT_DIR/ansible_install_argocd.yml"
PLAYBOOK_PROMETHEUS="$SCRIPT_DIR/ansible_install_prometheus.yml"
SERVER="os_servers"

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
    
    mkdir -p templates
    print_success "Created: templates/"
    
    mkdir -p output
    print_success "Created: output/"

    mkdir -p rancher
    print_success "Created: rancher/"
}

# Set DigitalOcean token
set_do_token() {
    print_header "Setting DigitalOcean Token"
    
    # Check if token is already set via environment variable
    if [ -n "$TF_VAR_do_token" ]; then
        print_success "DigitalOcean token already set via environment variable"
        return 0
    fi
    
    # Check if terraform.tfvars exists and contains do_token
    if [ -f "terraform.tfvars" ]; then
        if grep -q "do_token" terraform. tfvars; then
            print_success "DigitalOcean token found in terraform.tfvars"
            return 0
        fi
    fi
    
    # Prompt for token if not found
    print_warning "DigitalOcean token not found!"
    echo ""
    echo "Options:"
    echo "  1. Set environment variable: export TF_VAR_do_token='your_token'"
    echo "  2. Add to terraform.tfvars: do_token = \"your_token\""
    echo ""
    read -p "Enter DigitalOcean API token (or press Enter to skip): " token
    
    if [ -n "$token" ]; then
        export TF_VAR_do_token="$token"
        print_success "Token set for this session"
    else
        print_warning "No token provided. Make sure terraform.tfvars contains do_token"
    fi
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

# Apply Terraform changes
terraform_apply() {
    print_header "Applying Terraform Changes"
    terraform apply -auto-approve
    print_success "Terraform apply completed"
}

# Show Terraform outputs
terraform_output() {
    print_header "Terraform Outputs"
    terraform output
}

# Destroy Terraform resources
terraform_destroy() {
    print_header "Destroying Terraform Resources"
    print_warning "This will destroy all resources!"
    read -p "Are you sure?  (yes/no): " confirm
    
    if [ "$confirm" == "yes" ]; then
        terraform destroy -auto-approve
        print_success "All resources destroyed"
    else
        print_info "Destroy cancelled"
    fi
}

# Test Ansible connectivity
test_ansible() {
    print_header "Testing Ansible Connectivity"
    
    # INVENTORY="$SCRIPT_DIR/output/inventory.ini"
    # SERVER="os_servers"
    
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
    
    # INVENTORY="$SCRIPT_DIR/output/inventory.ini"
    # PLAYBOOK="$SCRIPT_DIR/ansible_install_ansible.yml"
    
    if [ !  -f "$INVENTORY" ]; then
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
    
    if [ !  -f "$INVENTORY" ]; then
        print_error "Inventory not found: $INVENTORY"
        return 1
    fi
    
    if [ ! -f "$PLAYBOOK_RANCHER" ]; then
        print_error "Playbook not found: $PLAYBOOK_RANCHER"
        print_info "Create ansible_install_rancher.yml first"
        return 1
    fi
    
    print_info "This will install:"
    print_info "  - K3s (Lightweight Kubernetes)"
    print_info "  - Helm"
    print_info "  - cert-manager"
    print_info "  - Rancher Server"
    echo ""
    
    # Count hosts in inventory
    HOST_COUNT=$(grep -c "ansible_host=" "$INVENTORY" 2>/dev/null || echo "0")
    
    echo "Select installation mode:"
    echo "  1) Single node (first server only)"
    echo "  2) Multi-node cluster (all $HOST_COUNT servers)"
    read -p "Choice [1-2]: " install_mode
    
    echo ""
    print_warning "This may take 10-20 minutes..."
    # print_warning "Minimum requirements:  4GB RAM, 2 CPU cores per node"
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
    
    # Get the first droplet IP
    FIRST_IP=$(grep -m1 "ansible_host=" "$INVENTORY" | grep -oP 'ansible_host=\K[^\s]+')
    
    print_header "RANCHER ACCESS INFORMATION"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${GREEN}  URL: https://${FIRST_IP}.nip.io${NC}"
    echo -e "${GREEN}  Alternative:  https://${FIRST_IP}${NC}"
    echo -e "${YELLOW}  Bootstrap Password: admin${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo ""
    print_info "Accept the self-signed certificate in your browser"
}

# Run Ansible playbook for installing ArgoCD
run_ansible_argocd() {
    print_header "Running Ansible Playbook - Install ArogoCD"
    
    # INVENTORY="$SCRIPT_DIR/output/inventory.ini"
    # PLAYBOOK="$SCRIPT_DIR/ansible_install_ansible.yml"
    
    if [ !  -f "$INVENTORY" ]; then
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
    
    # INVENTORY="$SCRIPT_DIR/output/inventory.ini"
    # PLAYBOOK="$SCRIPT_DIR/ansible_install_ansible.yml"
    
    if [ !  -f "$INVENTORY" ]; then
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

# Full workflow
run_all() {
    print_header "Running Full Workflow"
    
    create_directories
    set_do_token
    terraform_init
    terraform_validate
    terraform_plan
    
    echo ""
    read -p "Proceed with apply? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Apply cancelled"
        exit 0
    fi
    
    terraform_apply
    terraform_output
    
    print_info "Waiting 30 seconds for droplets to be ready..."
    sleep 30
    
    test_ansible

    echo ""
    echo "Select installation option:"
    echo "  1) Install Ansible (Python3, pip, Ansible)"
    echo "  2) Install Rancher (Terraform, cert-manager, Kubectl, K3s, Helm)"
    echo "  3) Install ArgoCD (ArgoCD, cert-manager)"
    echo "  4) Install Prometheus (Prometheus, Node Exporter)"
    echo "  5) All of the above"
    echo "  6) Skip"
    read -p "Choice [1-4]: " install_choice
    
    case $install_choice in
        1) run_ansible_ansible ;;
        2) run_ansible_rancher ;;
        3) run_ansible_argocd ;;
        4) run_ansible_prometheus ;;
        5) run_ansible_ansible; run_ansible_rancher ; run_ansible_argocd ; run_ansible_prometheus ;;
        6) print_info "Skipping software installation" ;;
    esac
    
    print_header "Workflow Complete!"
}

# Display help
show_help() {
    echo "
Usage: $0 [command]

Commands:
  all            Full workflow (init → apply → choose installation)
  init           Initialize Terraform
  validate       Validate configuration
  plan           Preview changes
  apply          Apply changes
  output         Show outputs
  destroy        Destroy resources
  test           Test Ansible connectivity
  ansible        Run basic software Ansible playbook
  rancher        Run Rancher prerequisites Ansible playbook
  help           Show this help

SSH Key Location:  $SSH_PRIVATE_KEY

Examples:
  $0 all              # Full workflow with options
  $0 rancher-full     # Create droplets and install Rancher prereqs
  $0 rancher          # Only run Rancher Ansible playbook
  $0 clone-rancher    # Clone Rancher repo locally
"
}

# ===========================================
# Main Script
# ===========================================

print_header "Terraform & Ansible Deployment Script"
print_info "Directory:  $SCRIPT_DIR"
print_info "SSH Key:  $SSH_PRIVATE_KEY"

case "${1:-}" in
    all)
        run_all
        ;;
    init)
        create_directories
        set_do_token
        terraform_init
        ;;
    validate)
        terraform_validate
        ;;
    plan)
        terraform_plan
        ;;
    apply)
        set_do_token
        terraform_apply
        terraform_output
        ;;
    output)
        terraform_output
        ;;
    destroy)
        terraform_destroy
        ;;
    test)
        test_ansible
        ;;
    ansible)
        run_ansible_ansible
        ;;
    rancher)
        run_ansible_rancher
        ;;
    argocd)
        run_ansible_argocd
        ;;
    prometheus)
        run_ansible_prometheus
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        # Default:  show menu
        echo ""
        echo "Select an option:"
        echo "  1) Run Full workflow (With installation options at the end)"
        echo "  2) Initialize Terraform"
        echo "  3) Plan changes"
        echo "  4) Apply changes"
        echo "  5) Run Ansible playbook (Install Ansible)"
        echo "  6) Run Ansible playbook (Install Rancher)"
        echo "  7) Run Ansible playbook (Install ArgoCD)"
        echo "  8) Run Ansible playbook (Install Prometheus)"
        echo "  9) Test Ansible connectivity"
        echo "  10) Show outputs"
        echo "  11) Destroy all resources"
        echo "  0) Exit"
        echo ""
        read -p "Enter choice [0-9]: " choice
        
        case $choice in
            1) run_all ;;
            2) create_directories; set_do_token; terraform_init ;;
            3) terraform_plan ;;
            4) set_do_token; terraform_apply; terraform_output ;;
            5) run_ansible_ansible ;;
            6) run_ansible_rancher ;;
            7) run_ansible_argocd ;;
            8) run_ansible_prometheus ;;
            9) test_ansible ;;
            10) terraform_output ;;
            11) terraform_destroy ;;
            0) echo "Exited... "; exit 0 ;;
            *) print_error "Invalid option"; exit 1 ;;
        esac
        ;;
esac

echo ""
print_success "Done!"