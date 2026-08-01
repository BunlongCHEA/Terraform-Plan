#!/bin/bash

# ===========================================
# argo_dockerapp/deploy.sh
# ===========================================
# Deploys the ELK(+Fluent Bit) logging stack and/or RabbitMQ to the K3s
# cluster, via kubectl apply + ArgoCD force-sync.
#
# Connection verification mirrors the before_script block already used in
# this repo's .gitlab-ci.yml files (decode kubeconfig if running in CI,
# otherwise use the local K3s kubeconfig on the Raspberry Pi, then
# `kubectl cluster-info` / `kubectl get nodes` to confirm success before
# doing anything else).
#
# Usage: ./deploy.sh [test|logging|logging-only|rabbitmq|all]
#   test           - only verify cluster connectivity, deploy nothing
#   logging        - deploy Elasticsearch + Kibana + Fluent Bit
#   logging-only   - deploy Elasticsearch + Kibana WITHOUT Fluent Bit
#   rabbitmq       - deploy RabbitMQ
#   all            - deploy everything (logging + Fluent Bit + rabbitmq)
# No argument shows an interactive menu.
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOGGING_K8S_DIR="$SCRIPT_DIR/elk-fluentbit/k8s"
RABBITMQ_K8S_DIR="$SCRIPT_DIR/rabbitmq/k8s"
ARGOCD_DIR="$SCRIPT_DIR/argocd"

# Files that make up Fluent Bit specifically, so "logging-only" can skip them
FLUENT_BIT_FILES=(
  "30-fluent-bit-rbac.yaml"
  "31-fluent-bit-configmap.yaml"
  "32-fluent-bit-daemonset.yaml"
)

print_header() { echo ""; echo -e "${CYAN}==========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}==========================================${NC}"; echo ""; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error()   { echo -e "${RED}✖ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }

# ===========================================
# Connection verification (same shape as .gitlab-ci.yml before_script)
# ===========================================
verify_connection() {
    print_header "Verifying Kubernetes Cluster Connection"

    SSH_TUNNEL_HOST="${SSH_TUNNEL_HOST:pi5-1-remote}"   # your ~/.ssh/config alias
    TUNNEL_PID=""

    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        # Case 1: running directly on the Pi/K3s node — no tunnel needed.
        print_info "Running on the K3s node — using /etc/rancher/k3s/k3s.yaml"
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    elif [ -n "$KUBE_CONFIG_BASE64" ]; then
        # Case 2: running remotely (laptop or CI) with the base64 kubeconfig
        # from /tmp/k3s-config-base64.txt exported as an env var/CI variable.
        print_info "KUBE_CONFIG_BASE64 detected — decoding kubeconfig..."
        mkdir -p ~/.kube
        echo "$KUBE_CONFIG_BASE64" | base64 -d > ~/.kube/config
        chmod 600 ~/.kube/config
        export KUBECONFIG=~/.kube/config

        # Kubeconfig still says https://127.0.0.1:6443 — that's only reachable
        # once tunneled through the Pi via SSH/Cloudflare Access, so open that
        # tunnel now unless it's already up.
        if ! nc -z 127.0.0.1 6443 2>/dev/null; then
            print_info "Opening SSH tunnel to $SSH_TUNNEL_HOST for the k3s API (port 6443)..."
            ssh -f -N -L 6443:127.0.0.1:6443 "$SSH_TUNNEL_HOST"
            TUNNEL_PID=$(pgrep -f "6443:127.0.0.1:6443.*$SSH_TUNNEL_HOST" | head -1)
            sleep 2
        else
            print_info "Port 6443 already forwarded locally — reusing existing tunnel"
        fi

    else
        print_info "Using default kubeconfig (\$KUBECONFIG or ~/.kube/config)"
    fi

    print_info "Testing connection to K3s cluster..."
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot reach the cluster."
        print_error "If running remotely, confirm: ssh $SSH_TUNNEL_HOST works on its own, and TUNNEL_SERVICE_TOKEN_ID/SECRET are set for non-interactive runs."
        [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null
        exit 1
    fi

    kubectl cluster-info
    echo ""
    kubectl get nodes
    print_success "Cluster connection verified"
}

# ===========================================
# ArgoCD helpers
# ===========================================
apply_and_sync_argocd_app() {
    local app_manifest="$1"
    local app_name="$2"

    print_info "Applying ArgoCD Application manifest: $app_manifest"
    kubectl apply -f "$app_manifest"

    sleep 5

    if kubectl get application "$app_name" -n argocd >/dev/null 2>&1; then
        print_info "Syncing $app_name via ArgoCD..."
        kubectl patch application "$app_name" -n argocd --type merge \
          -p '{"operation":{"sync":{"syncStrategy":{"apply":{"force":true}}}}}' || true
        print_success "$app_name sync triggered"
    else
        print_warning "$app_name ArgoCD application not found yet, skipping sync (ArgoCD will pick it up on its next reconcile)"
    fi
}

# ===========================================
# Deploy functions
# ===========================================
deploy_logging() {
    local with_fluentbit="$1"   # "yes" or "no"

    print_header "Deploying Elasticsearch + Kibana$( [ "$with_fluentbit" = "yes" ] && echo ' + Fluent Bit' )"

    kubectl apply -f "$LOGGING_K8S_DIR/00-namespace.yaml"
    kubectl apply -f "$LOGGING_K8S_DIR/10-elasticsearch.yaml"
    kubectl apply -f "$LOGGING_K8S_DIR/20-kibana.yaml"

    if [ "$with_fluentbit" = "yes" ]; then
        for f in "${FLUENT_BIT_FILES[@]}"; do
            kubectl apply -f "$LOGGING_K8S_DIR/$f"
        done
        print_success "Fluent Bit installed (cluster-wide, all namespaces)"
    else
        print_warning "Skipped Fluent Bit — no pod logs will ship to Elasticsearch yet."
        print_info "Run '$0 logging' later to add it without touching ES/Kibana."
    fi

    apply_and_sync_argocd_app "$ARGOCD_DIR/logging-application.yaml" "kyc-logging-stack"

    print_success "Logging stack deploy triggered"
    print_info "Check: kubectl get pods -n logging"
}

deploy_rabbitmq() {
    print_header "Deploying RabbitMQ (single node)"

    kubectl apply -f "$RABBITMQ_K8S_DIR/00-namespace-and-secret.yaml"
    kubectl apply -f "$RABBITMQ_K8S_DIR/10-rabbitmq.yaml"

    apply_and_sync_argocd_app "$ARGOCD_DIR/rabbitmq-application.yaml" "kyc-rabbitmq"

    print_success "RabbitMQ deploy triggered"
    print_info "Check: kubectl get pods -n rabbitmq"
}

# ===========================================
# Main
# ===========================================
run_option() {
    case "$1" in
        test)
            verify_connection
            ;;
        logging)
            verify_connection
            deploy_logging "yes"
            ;;
        logging-only)
            verify_connection
            deploy_logging "no"
            ;;
        rabbitmq)
            verify_connection
            deploy_rabbitmq
            ;;
        all)
            verify_connection
            deploy_logging "yes"
            deploy_rabbitmq
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
}

if [ -n "$1" ]; then
    run_option "$1"
else
    echo ""
    echo "Select an option:"
    echo "  1) Test cluster connectivity only"
    echo "  2) Deploy Elasticsearch + Kibana"
    echo "  3) Deploy RabbitMQ"
    echo "  4) Deploy everything"
    echo "  0) Exit"
    echo ""
    read -p "Enter choice: " choice

    case $choice in
        1)
            run_option test
            ;;
        2)
            echo ""
            echo "Also install Fluent Bit now (ships pod logs into Elasticsearch)?"
            echo "  1) Yes — full logging stack (ES + Kibana + Fluent Bit)"
            echo "  2) No  — ES + Kibana only, add Fluent Bit later"
            read -p "Enter choice: " fb_choice
            case $fb_choice in
                1) run_option logging ;;
                2) run_option logging-only ;;
                *) print_error "Invalid option"; exit 1 ;;
            esac
            ;;
        3)
            run_option rabbitmq
            ;;
        4)
            run_option all
            ;;
        0)
            echo "Exited..."; exit 0
            ;;
        *)
            print_error "Invalid option"; exit 1
            ;;
    esac
fi

echo ""
print_success "Done!"
