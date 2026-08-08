#!/bin/bash
# ===========================================
# connect_k3s.sh
# ===========================================
# Run this once whenever you start your local PC, before testing/using
# any k3s cluster. It reads server definitions from deploy.env (the
# SAME file argo_dockerapp/deploy.sh uses), so adding a new server is
# just adding 4 lines to deploy.env -- no script changes needed here.
#
# For each server in K3S_SERVER_NAMES, this:
#   1. Opens its SSH tunnel (skips if the local port is already bound).
#   2. Makes sure its kubeconfig's "server:" port matches its assigned
#      local tunnel port (auto-patches with sed if it doesn't).
#   3. Runs kubectl cluster-info + get nodes against it.
#
# Usage:
#   ./connect_k3s.sh [path/to/deploy.env]
#   (defaults to ./deploy.env if no path given)
# ===========================================

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header()  { echo ""; echo -e "${CYAN}==========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}==========================================${NC}"; echo ""; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error()   { echo -e "${RED}✖ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }

# ----------------------------------------------------------------
# Load server definitions from deploy.env
# ----------------------------------------------------------------
ENV_FILE="${1:-deploy.env}"

if [ ! -f "$ENV_FILE" ]; then
    print_error "deploy.env not found at: $ENV_FILE"
    print_info "Usage: $0 [path/to/deploy.env]"
    print_info "Or copy deploy.env.example to deploy.env first."
    exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${K3S_SERVER_NAMES:-}" ]; then
    print_error "K3S_SERVER_NAMES not defined in $ENV_FILE"
    exit 1
fi

print_info "Loaded ${#K3S_SERVER_NAMES[@]} server(s) from $ENV_FILE: ${K3S_SERVER_NAMES[*]}"

# ===========================================
# Step 1: open tunnels for every server (idempotent)
# ===========================================
open_tunnel() {
    local name="$1" ssh_host="$2" local_port="$3"

    if ss -tln 2>/dev/null | grep -q ":${local_port} "; then
        print_info "$name: port $local_port already bound -- reusing existing tunnel"
        return 0
    fi

    print_info "$name: opening tunnel -> $ssh_host (local $local_port -> remote 6443)"
    if ssh -f -N -L "${local_port}:127.0.0.1:6443" "$ssh_host"; then
        sleep 1
        if ss -tln 2>/dev/null | grep -q ":${local_port} "; then
            print_success "$name: tunnel is up on port $local_port"
        else
            print_error "$name: ssh exited 0 but port $local_port is not listening -- check manually"
            return 1
        fi
    else
        print_error "$name: ssh tunnel command failed"
        return 1
    fi
}

print_header "Step 1: Opening SSH tunnels for all servers"
for name in "${K3S_SERVER_NAMES[@]}"; do
    upper="${name^^}"
    ssh_host="$(eval echo \$"${upper}_SSH_HOST")"
    local_port="$(eval echo \$"${upper}_LOCAL_PORT")"

    if [ -z "$ssh_host" ] || [ -z "$local_port" ]; then
        print_error "$name: missing ${upper}_SSH_HOST or ${upper}_LOCAL_PORT in $ENV_FILE -- skipping"
        continue
    fi
    open_tunnel "$name" "$ssh_host" "$local_port"
done

echo ""
print_info "Listening ports:"
ss -tlnp 2>/dev/null | grep ssh

# ===========================================
# Step 2: make sure every kubeconfig's server port matches its
# assigned local tunnel port. Every kubeconfig is copied verbatim
# from k3s.yaml (server: 127.0.0.1:6443) regardless of which server
# it came from, so any server NOT using local port 6443 needs its
# kubeconfig patched -- otherwise it'll silently connect through
# whichever tunnel actually owns port 6443 and fail TLS verification.
# ===========================================
print_header "Step 2: Verifying kubeconfig server ports"
for name in "${K3S_SERVER_NAMES[@]}"; do
    upper="${name^^}"
    local_port="$(eval echo \$"${upper}_LOCAL_PORT")"
    kubeconfig="$(eval echo \$"${upper}_KUBECONFIG")"

    if [ -z "$kubeconfig" ]; then
        print_error "$name: ${upper}_KUBECONFIG not set in $ENV_FILE -- skipping"
        continue
    fi
    if [ ! -f "$kubeconfig" ]; then
        print_error "$name: kubeconfig not found at $kubeconfig -- skipping"
        continue
    fi

    current_server="$(grep -E '^\s*server:' "$kubeconfig" | awk '{print $2}')"
    expected_server="https://127.0.0.1:${local_port}"

    if [ "$current_server" = "$expected_server" ]; then
        print_success "$name: kubeconfig already points at $expected_server"
    else
        print_warning "$name: kubeconfig points at '$current_server', expected '$expected_server' -- patching"
        sed -i "s#server: https://127.0.0.1:[0-9]*#server: ${expected_server}#" "$kubeconfig"
        print_success "$name: patched -> $(grep -E '^\s*server:' "$kubeconfig")"
    fi
done

# ===========================================
# Step 3: test every cluster
# ===========================================
test_cluster() {
    local name="$1" kubeconfig="$2"

    echo ""
    print_info "--- Testing $name ($kubeconfig) ---"
    if [ ! -f "$kubeconfig" ]; then
        print_error "$name: kubeconfig not found at $kubeconfig"
        return 1
    fi

    if KUBECONFIG="$kubeconfig" kubectl cluster-info; then
        print_success "$name: connected"
        KUBECONFIG="$kubeconfig" kubectl get nodes
        return 0
    else
        print_error "$name: FAILED"
        return 1
    fi
}

print_header "Step 3: Testing cluster connections"
fail_count=0
for name in "${K3S_SERVER_NAMES[@]}"; do
    upper="${name^^}"
    kubeconfig="$(eval echo \$"${upper}_KUBECONFIG")"
    test_cluster "$name" "$kubeconfig" || fail_count=$((fail_count + 1))
done

echo ""
if [ "$fail_count" -eq 0 ]; then
    print_success "All ${#K3S_SERVER_NAMES[@]} cluster(s) reachable. Ready for argo_dockerapp/deploy.sh"
else
    print_error "$fail_count of ${#K3S_SERVER_NAMES[@]} cluster(s) failed -- see errors above"
    exit 1
fi