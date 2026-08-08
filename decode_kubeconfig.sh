#!/bin/bash

# ===========================================
# decode_kubeconfig.sh
# ===========================================
# Run this on your LOCAL machine (WSL/laptop). Decodes a base64 kubeconfig
# produced by get_kubeconfig.sh and saves it as ~/.kube/KUBECONFIG_<name>,
# where <name> is whatever you choose (e.g. pi, desktop, server1) -- this
# matches the <NAME>_KUBECONFIG variables expected in deploy.env.
#
# Usage:
#   ./decode_kubeconfig.sh <name>                    # paste base64 interactively
#   ./decode_kubeconfig.sh <name> /path/to/base64.txt # read from a file
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() { echo ""; echo -e "${CYAN}==========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}==========================================${NC}"; echo ""; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error()   { echo -e "${RED}✖ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }

NAME="$1"
SRC_FILE="$2"

if [ -z "$NAME" ]; then
    print_error "Usage: $0 <name> [path/to/base64.txt]"
    print_info "Example: $0 pi"
    print_info "Example: $0 desktop ~/k3s-desktop-base64.txt"
    exit 1
fi

KUBE_DIR="$HOME/.kube"
OUT_FILE="$KUBE_DIR/KUBECONFIG_${NAME}"
mkdir -p "$KUBE_DIR"

print_header "Decoding kubeconfig for: $NAME"

if [ -n "$SRC_FILE" ]; then
    if [ ! -f "$SRC_FILE" ]; then
        print_error "File not found: $SRC_FILE"
        exit 1
    fi
    print_info "Reading base64 from: $SRC_FILE"
    base64 -d "$SRC_FILE" > "$OUT_FILE"
else
    print_info "Paste the base64-encoded kubeconfig below, then press Ctrl+D:"
    echo ""
    cat > "/tmp/${NAME}-base64-input.txt"
    base64 -d "/tmp/${NAME}-base64-input.txt" > "$OUT_FILE"
    rm -f "/tmp/${NAME}-base64-input.txt"
fi

if [ ! -s "$OUT_FILE" ]; then
    print_error "Decoded file is empty -- check the base64 input was valid/complete"
    rm -f "$OUT_FILE"
    exit 1
fi

chmod 600 "$OUT_FILE"

print_header "Verifying decoded kubeconfig"
grep -E "^\s*server:" "$OUT_FILE" || print_warning "No 'server:' field found -- this may not be a valid kubeconfig"

print_success "Saved to: $OUT_FILE"
echo ""
print_info "Test it with:"
print_info "  KUBECONFIG=$OUT_FILE kubectl cluster-info"
echo ""
print_info "If server: shows https://127.0.0.1:6443, remember this only works"
print_info "once an SSH tunnel to that server is forwarding local port 6443"
print_info "(or whatever port you've assigned it in deploy.env)."