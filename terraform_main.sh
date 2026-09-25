#!/usr/bin/env bash
# Usage:
#   ./terraform_main.sh <target> <command>
#
#   target:  digitalocean | gke | raspberrypi
#   command: all | init | validate | plan | apply | output | destroy | test |
#            ansible | rancher | argocd | prometheus | kyverno |
#            install | uninstall | help
#
# Examples:
#   ./terraform_main.sh digitalocean all
#   ./terraform_main.sh gke rancher
#   ./terraform_main.sh raspberrypi uninstall
# ==========================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
print_header()  { echo -e "\n${CYAN}==========================================${NC}\n${CYAN}  $1${NC}\n${CYAN}==========================================${NC}\n"; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error()   { echo -e "${RED}✖ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$ROOT_DIR/ansible-common"

TARGET="${1:-}"
COMMAND="${2:-help}"

case "$TARGET" in
  digitalocean|gke|raspberrypi) ;;
  ""|help|-h|--help)
    cat <<EOF
Usage: $0 <target> <command>
  target:  digitalocean | gke | raspberrypi
  command: all | init | validate | plan | apply | output | destroy | test |
           ansible | rancher | argocd | prometheus | kyverno |
           install | uninstall | help
EOF
    exit 0
    ;;
  *)
    print_error "Unknown target: '$TARGET'"
    echo "Usage: $0 <digitalocean|gke|raspberrypi> <command>"
    exit 1
    ;;
esac

TARGET_DIR="$ROOT_DIR/$TARGET"
[ -d "$TARGET_DIR" ] || { print_error "Target directory not found: $TARGET_DIR"; exit 1; }

INVENTORY="$TARGET_DIR/output/inventory.ini"
SERVER="os_servers"

# Shared, provider-agnostic assets
P_INSTALL="$COMMON_DIR/playbooks/install"
P_UNINSTALL="$COMMON_DIR/playbooks/uninstall"
ARGOCD_DIR="$COMMON_DIR/argocd"
CERT_DIR="$COMMON_DIR/certificate"

# Check to run "all.yml" from each inside directory (Ex: ./digitalocean/group_vars) first, if not create, go back to common directory - ./ansible-common/group_vars
TARGET_GROUP_VARS="$TARGET_DIR/group_vars/all.yml"
COMMON_GROUP_VARS="$COMMON_DIR/group_vars/all.yml"

resolve_group_vars() {
  # Base extra-vars every playbook run needs. -e has the highest precedence in Ansible, so this cleanly overrides the "./argocd" / "./certificate"
  EXTRA_VARS=( -e "argocd_config_dir=$ARGOCD_DIR" -e "cert_templates_dir=$CERT_DIR" )

  if [ -f "$TARGET_GROUP_VARS" ]; then
    print_info "Using per-target values: $TARGET_GROUP_VARS"
    EXTRA_VARS+=( -e "@$TARGET_GROUP_VARS" )
  elif [ -f "$COMMON_GROUP_VARS" ]; then
    print_warning "$TARGET has no group_vars/all.yml — falling back to the shared ansible-common/group_vars/all.yml (same domain/email for every target)"
    EXTRA_VARS+=( -e "@$COMMON_GROUP_VARS" )
  else
    print_error "No group_vars found for $TARGET, and no shared ansible-common/group_vars/all.yml either."
    print_info "Either:"
    print_info "  cp ansible-common/group_vars/all.yml.example $TARGET_DIR/group_vars/all.yml   # per-target domain"
    print_info "  cp ansible-common/group_vars/all.yml.example ansible-common/group_vars/all.yml # one shared domain for all targets"
    print_info "...then fill in rancher_domain / admin_email before running this command."
    return 1
  fi
}

require_inventory() {
  if [ ! -f "$INVENTORY" ]; then
    print_error "Inventory not found: $INVENTORY"
    print_info "Run '$0 $TARGET apply' first"
    return 1
  fi
}

run_playbook() {
  local name="$1" file="$2"
  require_inventory || return 1
  resolve_group_vars || return 1
  if [ ! -f "$file" ]; then
    print_error "Playbook not found: $file"
    return 1
  fi
  print_info "Running $name: $file"
  ansible-playbook -i "$INVENTORY" "$file" "${EXTRA_VARS[@]}"
  print_success "$name completed"
}

run_rancher() {
  require_inventory || return 1
  resolve_group_vars || return 1
 
  local rancher_single="$P_INSTALL/rancher.yml"
  local rancher_multi="$P_INSTALL/rancher_multi.yml"
  local host_count
  host_count=$(grep -c "ansible_host=" "$INVENTORY" 2>/dev/null || echo "0")
 
  echo "Select installation mode:"
  echo "  1) Single node (first server only)"
  echo "  2) Multi-node cluster (all $host_count servers)"
  read -p "Choice [1-2]: " install_mode
 
  case "$install_mode" in
    1)
      if [ ! -f "$rancher_single" ]; then print_error "Playbook not found: $rancher_single"; return 1; fi
      print_info "Installing Rancher on first server only: $rancher_single"
      ansible-playbook -i "$INVENTORY" "$rancher_single" --limit "${SERVER}[0]" "${EXTRA_VARS[@]}"
      ;;
    2)
      if [ ! -f "$rancher_multi" ]; then print_error "Playbook not found: $rancher_multi"; return 1; fi
      print_info "Installing Rancher multi-node cluster (all $host_count servers): $rancher_multi"
      ansible-playbook -i "$INVENTORY" "$rancher_multi" "${EXTRA_VARS[@]}"
      ;;
    *)
      print_warning "Invalid choice — defaulting to single node"
      if [ ! -f "$rancher_single" ]; then print_error "Playbook not found: $rancher_single"; return 1; fi
      ansible-playbook -i "$INVENTORY" "$rancher_single" --limit "${SERVER}[0]" "${EXTRA_VARS[@]}"
      ;;
  esac
  print_success "Rancher installation completed"
}

# ---- Terraform lifecycle: always executed from inside TARGET_DIR, so
#      variable.tf / terraform.tfvars / templates/*.tftpl resolve exactly
#      as they do. ----
tf() { ( cd "$TARGET_DIR" && terraform "$@" ); }

create_directories() {
  print_header "Creating Directories ($TARGET)"
  mkdir -p "$TARGET_DIR/output" "$TARGET_DIR/rancher"
  print_success "output/, rancher/ ready under $TARGET/"
}

terraform_init()     { print_header "terraform init ($TARGET)";     tf init -upgrade; print_success "Initialized"; }
terraform_validate() { print_header "terraform validate ($TARGET)"; tf validate;      print_success "Valid"; }
terraform_plan()     { print_header "terraform plan ($TARGET)";     tf plan;          print_success "Plan complete"; }
terraform_apply()    { print_header "terraform apply ($TARGET)";    tf apply -auto-approve; print_success "Apply complete"; }
terraform_output()   { print_header "terraform output ($TARGET)";   tf output; }
 
terraform_destroy() {
  print_header "terraform destroy ($TARGET)"
  print_warning "This will destroy all Terraform-managed resources for $TARGET!"
  if [ "$TARGET" = "raspberrypi" ]; then
    print_info "raspberrypi: only removes generated local files (inventory, output/) — your physical Pi is never touched."
  fi
  read -p "Are you sure? (yes/no): " confirm
  if [ "$confirm" = "yes" ]; then
    tf destroy -auto-approve
    print_success "Destroyed"
  else
    print_info "Cancelled"
  fi
}
 
test_ansible() {
  print_header "Ansible connectivity test ($TARGET)"
  require_inventory || return 1
  ansible -i "$INVENTORY" "$SERVER" -m ping
  print_success "Connectivity test completed"
}
 
install_menu() {
  echo "Select installation option:"
  echo "  1) Ansible (Python3, pip, Ansible)"
  echo "  2) Rancher (K3s, Helm, cert-manager, Rancher Server)"
  echo "  3) ArgoCD"
  echo "  4) Prometheus + Grafana"
  echo "  5) Kyverno (Policy Engine — Non-Production/Audit)"
  echo "  6) All of the above"
  echo "  7) Skip"
  read -p "Enter choice: " c
  case "$c" in
    1) run_playbook "Install Ansible"    "$P_INSTALL/ansible.yml" ;;
    2) run_rancher ;;
    3) run_playbook "Install ArgoCD"     "$P_INSTALL/argocd.yml" ;;
    4) run_playbook "Install Prometheus" "$P_INSTALL/prometheus_grafana.yml" ;;
    5) run_playbook "Install Kyverno"    "$P_INSTALL/kyverno.yml" ;;
    6) run_playbook "Install Ansible"    "$P_INSTALL/ansible.yml"
       run_rancher
       run_playbook "Install ArgoCD"     "$P_INSTALL/argocd.yml"
       run_playbook "Install Prometheus" "$P_INSTALL/prometheus_grafana.yml"
       run_playbook "Install Kyverno"    "$P_INSTALL/kyverno.yml" ;;
    7) print_info "Skipping software installation" ;;
    *) print_error "Invalid choice" ;;
  esac
}
 
uninstall_menu() {
  print_header "Uninstall Menu ($TARGET)"
  echo "  1) Prometheus & Grafana"
  echo "  2) ArgoCD"
  echo "  3) Rancher & K3s (WARNING: removes entire cluster)"
  echo "  4) Everything (Prometheus + ArgoCD + Rancher)"
  echo "  5) Back"
  read -p "Enter choice: " c
  case "$c" in
    1) run_playbook "Uninstall Prometheus" "$P_UNINSTALL/prometheus_grafana.yml" ;;
    2) run_playbook "Uninstall ArgoCD"     "$P_UNINSTALL/argocd.yml" ;;
    3) print_warning "This removes the entire K3s cluster."
       read -p "Type 'yes' to confirm: " confirm
       [ "$confirm" = "yes" ] && run_playbook "Uninstall Rancher" "$P_UNINSTALL/rancher.yml" ;;
    4) print_warning "This will uninstall EVERYTHING!"
       read -p "Type 'yes' to confirm: " confirm
       if [ "$confirm" = "yes" ]; then
         run_playbook "Uninstall Prometheus" "$P_UNINSTALL/prometheus_grafana.yml"
         run_playbook "Uninstall ArgoCD"     "$P_UNINSTALL/argocd.yml"
         run_playbook "Uninstall Rancher"    "$P_UNINSTALL/rancher.yml"
       fi ;;
    5) return 0 ;;
    *) print_error "Invalid choice" ;;
  esac
}
 
run_all() {
  create_directories
  terraform_init
  terraform_validate
  terraform_plan
  read -p "Proceed with apply? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    print_info "Apply cancelled"
    exit 0
  fi
  terraform_apply
  terraform_output
  print_info "Waiting 30 seconds for the host to be ready..."
  sleep 30
  test_ansible
  install_menu
  print_header "Workflow Complete! ($TARGET)"
}
 
show_help() {
  cat <<EOF
Usage: $0 <target> <command>
 
  target:  digitalocean | gke | raspberrypi
  command:
    all            Full workflow: init -> apply -> choose installation
    init           terraform init
    validate       terraform validate
    plan           terraform plan
    apply          terraform apply + output
    output         Show Terraform outputs
    destroy        Destroy target's resources
    test           Ansible connectivity check
    ansible        Install Python3/pip/Ansible on the host
    rancher        Install K3s + Rancher (prompts: single node vs multi-node)
    argocd         Install ArgoCD
    prometheus     Install Prometheus + Grafana
    kyverno        Install Kyverno
    install        Show install menu
    uninstall      Show uninstall menu
    help           Show this help
 
Shared assets (used for every target):
  Playbooks:    ansible-common/playbooks/{install,uninstall}/
  ArgoCD:       ansible-common/argocd/
  Certificates: ansible-common/certificate/
 
Target-local assets (kept separate per target):
  variable.tf(.example), terraform.tfvars(.example), templates/*.tftpl,
  group_vars/all.yml (real rancher_domain / admin_email for this cluster)
 
Examples:
  $0 digitalocean all
  $0 gke rancher
  $0 raspberrypi uninstall
EOF
}
 
print_header "Terraform-Plan — $TARGET"
print_info "Target dir: $TARGET_DIR"
print_info "Shared playbooks: $P_INSTALL"
 
case "$COMMAND" in
  all)        run_all ;;
  init)       create_directories; terraform_init ;;
  validate)   terraform_validate ;;
  plan)       terraform_plan ;;
  apply)      create_directories; terraform_apply; terraform_output ;;
  output)     terraform_output ;;
  destroy)    terraform_destroy ;;
  test)       test_ansible ;;
  ansible)    run_playbook "Install Ansible"    "$P_INSTALL/ansible.yml" ;;
  rancher)    run_rancher ;;
  argocd)     run_playbook "Install ArgoCD"     "$P_INSTALL/argocd.yml" ;;
  prometheus) run_playbook "Install Prometheus" "$P_INSTALL/prometheus_grafana.yml" ;;
  kyverno)    run_playbook "Install Kyverno"    "$P_INSTALL/kyverno.yml" ;;
  install)    install_menu ;;
  uninstall)  uninstall_menu ;;
  help|*)     show_help ;;
esac