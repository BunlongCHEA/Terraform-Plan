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
    print_success "Created:  templates/"
    
    mkdir -p ssh_keys
    print_success "Created: ssh_keys/"
    
    mkdir -p output
    print_success "Created: output/"
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
    echo "  1. Set environment variable:  export TF_VAR_do_token='your_token'"
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

# Fix SSH key permissions
fix_ssh_permissions() {
    print_header "Fixing SSH Key Permissions"
    
    SSH_KEY="$SCRIPT_DIR/ssh_keys/id_rsa_digitalocean"
    
    if [ -f "$SSH_KEY" ]; then
        chmod 600 "$SSH_KEY"
        print_success "SSH key permissions set to 600: $SSH_KEY"
        
        # Also fix public key
        if [ -f "${SSH_KEY}.pub" ]; then
            chmod 644 "${SSH_KEY}.pub"
            print_success "SSH public key permissions set to 644"
        fi
    else
        print_warning "SSH key not found yet:  $SSH_KEY"
        print_info "Run 'terraform apply' first to generate keys"
    fi
}

# Test Ansible connectivity
test_ansible() {
    print_header "Testing Ansible Connectivity"
    
    INVENTORY="$SCRIPT_DIR/output/inventory.ini"
    
    if [ -f "$INVENTORY" ]; then
        print_info "Testing connection to all hosts..."
        ansible -i "$INVENTORY" ubuntu_servers -m ping
        print_success "Ansible connectivity test completed"
    else
        print_error "Inventory file not found: $INVENTORY"
        print_info "Run 'terraform apply' first to generate inventory"
    fi
}

# Run Ansible playbook
run_ansible() {
    print_header "Running Ansible Playbook"
    
    INVENTORY="$SCRIPT_DIR/output/inventory.ini"
    PLAYBOOK="$SCRIPT_DIR/ansible_install_software.yml"
    
    if [ !  -f "$INVENTORY" ]; then
        print_error "Inventory file not found: $INVENTORY"
        print_info "Run 'terraform apply' first"
        return 1
    fi
    
    if [ ! -f "$PLAYBOOK" ]; then
        print_error "Playbook not found: $PLAYBOOK"
        return 1
    fi
    
    print_info "Running playbook:  $PLAYBOOK"
    ansible-playbook -i "$INVENTORY" "$PLAYBOOK"
    print_success "Ansible playbook completed"
}

# Display help
show_help() {
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  init        Initialize Terraform"
    echo "  validate    Validate Terraform configuration"
    echo "  plan        Preview Terraform changes"
    echo "  apply       Apply Terraform changes (create resources)"
    echo "  output      Show Terraform outputs"
    echo "  destroy     Destroy all Terraform resources"
    echo "  fix-ssh     Fix SSH key permissions"
    echo "  test        Test Ansible connectivity"
    echo "  ansible     Run Ansible playbook"
    echo "  all         Run full workflow (init -> apply -> fix-ssh -> ansible)"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 all          # Full workflow"
    echo "  $0 apply        # Only apply Terraform"
    echo "  $0 ansible      # Only run Ansible playbook"
    echo "  $0 destroy      # Destroy all resources"
    echo ""
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
    fix_ssh_permissions
    terraform_output
    
    echo ""
    read -p "Run Ansible playbook? (yes/no): " run_pb
    if [ "$run_pb" == "yes" ]; then
        # Wait a bit for droplets to be fully ready
        print_info "Waiting 30 seconds for droplets to be fully ready..."
        sleep 30
        test_ansible
        run_ansible
    fi
    
    print_header "Workflow Complete!"
    echo ""
    print_info "SSH to servers using commands from 'terraform output ssh_connection_commands'"
    echo ""
}

# ===========================================
# Main Script
# ===========================================

print_header "Terraform & Ansible Deployment Script"
print_info "Working directory: $SCRIPT_DIR"

case "${1:-}" in
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
        fix_ssh_permissions
        terraform_output
        ;;
    output)
        terraform_output
        ;;
    destroy)
        terraform_destroy
        ;;
    fix-ssh)
        fix_ssh_permissions
        ;;
    test)
        test_ansible
        ;;
    ansible)
        fix_ssh_permissions
        run_ansible
        ;;
    all)
        run_all
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        # Default:  show menu
        echo ""
        echo "Select an option:"
        echo "  1) Full workflow (init -> apply -> ansible)"
        echo "  2) Initialize Terraform"
        echo "  3) Plan changes"
        echo "  4) Apply changes"
        echo "  5) Run Ansible playbook"
        echo "  6) Test Ansible connectivity"
        echo "  7) Show outputs"
        echo "  8) Fix SSH permissions"
        echo "  9) Destroy all resources"
        echo "  0) Exit"
        echo ""
        read -p "Enter choice [0-9]: " choice
        
        case $choice in
            1) run_all ;;
            2) create_directories; set_do_token; terraform_init ;;
            3) terraform_plan ;;
            4) set_do_token; terraform_apply; fix_ssh_permissions; terraform_output ;;
            5) run_ansible ;;
            6) test_ansible ;;
            7) terraform_output ;;
            8) fix_ssh_permissions ;;
            9) terraform_destroy ;;
            0) echo "Exiting... "; exit 0 ;;
            *) print_error "Invalid option"; exit 1 ;;
        esac
        ;;
esac

echo ""
print_success "Done!"