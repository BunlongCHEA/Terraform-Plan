#!/bin/bash

# ===========================================
# argo_dockerapp/deploy.sh
# ===========================================
# Deploys ELK (Desktop-hosted) + Fluent Bit (any number of servers) +
# RabbitMQ, via kubectl apply + ArgoCD force-sync.
#
# All cluster targets, Elasticsearch location, and ArgoCD destinations
# are defined once in deploy.env -- see that file to add/change a server.
#
# Usage: ./deploy.sh [test|es-kibana|fluentbit-single|fluentbit-multi|rabbitmq|all]
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
FLUENT_BIT_DIR="$LOGGING_K8S_DIR/fluent-bit"
RABBITMQ_K8S_DIR="$SCRIPT_DIR/rabbitmq/k8s"
ARGOCD_DIR="$SCRIPT_DIR/argocd"

if [ -f "$SCRIPT_DIR/deploy.env" ]; then
    source "$SCRIPT_DIR/deploy.env"
else
    echo "deploy.env not found -- copy deploy.env.example and configure it first"
    exit 1
fi

print_header() { echo ""; echo -e "${CYAN}==========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}==========================================${NC}"; echo ""; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error()   { echo -e "${RED}✖ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }

# ===========================================
# Helper: resolve a server's ArgoCD destination.server value
# ===========================================
get_argocd_destination() {
    local name="$1"
    if [ "$name" = "$ARGOCD_HOST_SERVER_NAME" ]; then
        echo "https://kubernetes.default.svc"
    else
        local var="${name^^}_ARGOCD_DEST"
        echo "${!var}"
    fi
}

# ===========================================
# Connection verification -- ALL configured K3s servers
# ===========================================
verify_connection() {
    print_header "Verifying Kubernetes Cluster Connection(s)"

    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        # Running directly on a k3s node -- verify just this local cluster.
        print_info "Running on a K3s node -- using /etc/rancher/k3s/k3s.yaml"
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        kubectl cluster-info
        echo ""
        kubectl get nodes
        print_success "Local cluster connection verified"
        return 0
    fi

    # Not on a node -- verify EVERY server in deploy.env, opening an SSH
    # tunnel per server (on its own local port) if one isn't already up.
    local failures=0
    for name in "${K3S_SERVER_NAMES[@]}"; do
        echo ""
        print_info "--- Checking server: $name ---"

        local ssh_host="$(eval echo \$${name^^}_SSH_HOST)"
        local local_port="$(eval echo \$${name^^}_LOCAL_PORT)"
        local kubeconfig_path="$(eval echo \$${name^^}_KUBECONFIG)"

        if [ ! -f "$kubeconfig_path" ]; then
            print_error "$name: kubeconfig not found at $kubeconfig_path (see README setup steps)"
            failures=$((failures + 1))
            continue
        fi

        if ! nc -z 127.0.0.1 "$local_port" 2>/dev/null; then
            print_info "$name: opening SSH tunnel via $ssh_host -> local port $local_port"
            ssh -f -N -L "${local_port}:127.0.0.1:6443" "$ssh_host"
            sleep 2
        else
            print_info "$name: local port $local_port already forwarded -- reusing"
        fi

        if KUBECONFIG="$kubeconfig_path" kubectl cluster-info >/dev/null 2>&1; then
            print_success "$name: connected"
            KUBECONFIG="$kubeconfig_path" kubectl get nodes
        else
            print_error "$name: FAILED -- debug with: ssh -v -N -L ${local_port}:127.0.0.1:6443 $ssh_host"
            failures=$((failures + 1))
        fi
    done

    echo ""
    if [ "$failures" -gt 0 ]; then
        print_error "$failures server(s) failed connectivity check"
        exit 1
    fi
    print_success "All configured K3s servers verified"
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
        print_warning "$app_name ArgoCD application not found yet, skipping sync"
    fi
}

# ===========================================
# Deploy functions
# ===========================================
deploy_es_kibana() {
    print_header "Deploying Elasticsearch + Kibana (host: $ES_HOST_SERVER_NAME)"

    kubectl apply -f "$LOGGING_K8S_DIR/elasticsearch-kibana/00-namespace.yaml"
    kubectl apply -f "$LOGGING_K8S_DIR/elasticsearch-kibana/10-elasticsearch.yaml"
    kubectl apply -f "$LOGGING_K8S_DIR/elasticsearch-kibana/20-kibana.yaml"

    local dest="$(get_argocd_destination "$ES_HOST_SERVER_NAME")"
    local rendered="/tmp/kyc-es-kibana-application.yaml"
    DEST_SERVER="$dest" envsubst '${DEST_SERVER}' \
        < "$ARGOCD_DIR/es-kibana-application.yaml.tmpl" > "$rendered"
    apply_and_sync_argocd_app "$rendered" "kyc-es-kibana"
    rm -f "$rendered"

    print_success "ES + Kibana deploy triggered"
    print_info "Check: kubectl get pods -n logging"
}

deploy_fluent_bit_local() {
    print_header "Deploying Fluent Bit on this server -> ${ES_HOST}:${ES_PORT}"
    kubectl apply -f "$FLUENT_BIT_DIR/30-fluent-bit-rbac.yaml"
    ES_HOST="$ES_HOST" ES_PORT="$ES_PORT" \
        envsubst '${ES_HOST} ${ES_PORT}' < "$FLUENT_BIT_DIR/31-fluent-bit-configmap.yaml.tmpl" \
        | kubectl apply -f -
    kubectl apply -f "$FLUENT_BIT_DIR/32-fluent-bit-daemonset.yaml"
    print_success "Fluent Bit deployed, forwarding to ${ES_HOST}:${ES_PORT}"
}

deploy_fluent_bit_multi_argocd() {
    print_header "Rolling out Fluent Bit to ${#K3S_SERVER_NAMES[@]} server(s) via ArgoCD"
    for name in "${K3S_SERVER_NAMES[@]}"; do
        local app_name="kyc-fluentbit-${name}"
        local dest="$(get_argocd_destination "$name")"
        local rendered="/tmp/${app_name}-application.yaml"
        APP_NAME="$app_name" DEST_SERVER="$dest" \
            envsubst '${APP_NAME} ${DEST_SERVER}' < "$ARGOCD_DIR/fluent-bit-application.yaml.tmpl" > "$rendered"
        apply_and_sync_argocd_app "$rendered" "$app_name"
        rm -f "$rendered"
    done
}

deploy_rabbitmq() {
    print_header "Deploying RabbitMQ (single node)"
    kubectl apply -f "$RABBITMQ_K8S_DIR/00-namespace-and-secret.yaml"
    kubectl apply -f "$RABBITMQ_K8S_DIR/10-rabbitmq.yaml"
    apply_and_sync_argocd_app "$ARGOCD_DIR/rabbitmq-application.yaml" "kyc-rabbitmq"
    print_success "RabbitMQ deploy triggered"
}

# ===========================================
# Main
# ===========================================
run_option() {
    case "$1" in
        test)             verify_connection ;;
        es-kibana)        verify_connection; deploy_es_kibana ;;
        fluentbit-single) verify_connection; deploy_fluent_bit_local ;;
        fluentbit-multi)  verify_connection; deploy_fluent_bit_multi_argocd ;;
        rabbitmq)         verify_connection; deploy_rabbitmq ;;
        all)
            verify_connection
            deploy_es_kibana
            deploy_fluent_bit_multi_argocd
            deploy_rabbitmq
            ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
}

if [ -n "$1" ]; then
    run_option "$1"
else
    echo ""
    echo "Select an option:"
    echo "  1) Test connectivity to all configured K3s servers"
    echo "  2) Deploy Elasticsearch + Kibana (host: $ES_HOST_SERVER_NAME)"
    echo "  3) Deploy Fluent Bit"
    echo "  4) Deploy RabbitMQ"
    echo "  5) Deploy everything"
    echo "  0) Exit"
    echo ""
    read -p "Enter choice: " choice

    case $choice in
        1) run_option test ;;
        2) run_option es-kibana ;;
        3)
            echo ""
            echo "  1) This single server only"
            echo "  2) All servers in deploy.env, via ArgoCD"
            read -p "Enter choice: " fb_mode
            case $fb_mode in
                1) run_option fluentbit-single ;;
                2) run_option fluentbit-multi ;;
                *) print_error "Invalid option"; exit 1 ;;
            esac
            ;;
        4) run_option rabbitmq ;;
        5) run_option all ;;
        0) echo "Exited..."; exit 0 ;;
        *) print_error "Invalid option"; exit 1 ;;
    esac
fi

echo ""
print_success "Done!"