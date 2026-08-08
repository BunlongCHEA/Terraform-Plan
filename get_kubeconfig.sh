#!/bin/bash

# ===========================================
# get_kubeconfig.sh
# ===========================================
# Run this ON the remote k3s server (Pi, Desktop, or any future server).
# Extracts /etc/rancher/k3s/k3s.yaml, displays it, base64-encodes it
# (single line, no wrapping), and prints the encoded output ready to
# copy-paste into decode_kubeconfig.sh on your local machine.
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() { echo ""; echo -e "${CYAN}==========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}==========================================${NC}"; echo ""; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_error()   { echo -e "${RED}✖ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }

K3S_CONFIG_SRC="/etc/rancher/k3s/k3s.yaml"
TMP_CONFIG="/tmp/k3s-config.yaml"
TMP_BASE64="/tmp/k3s-config-base64.txt"

print_header "Extracting kubeconfig from this k3s server"

if [ ! -f "$K3S_CONFIG_SRC" ]; then
    print_error "$K3S_CONFIG_SRC not found -- is k3s installed on this host?"
    exit 1
fi

print_info "Copying $K3S_CONFIG_SRC -> $TMP_CONFIG"
sudo cat "$K3S_CONFIG_SRC" > "$TMP_CONFIG"

if [ ! -s "$TMP_CONFIG" ]; then
    print_error "$TMP_CONFIG is empty -- sudo read likely failed"
    exit 1
fi

print_header "Kubeconfig contents (verify before continuing)"
cat "$TMP_CONFIG"

print_info "Encoding to base64 (single line)..."
cat "$TMP_CONFIG" | base64 -w 0 > "$TMP_BASE64"

print_header "Base64-encoded kubeconfig"
cat "$TMP_BASE64"
echo ""

print_success "Saved to: $TMP_BASE64"
print_info "Copy the base64 output above (or scp/cat this file) to your local"
print_info "machine, then run decode_kubeconfig.sh there to save it."
print_info ""
print_info "Example, from your local machine:"
print_info "  scp $(hostname):$TMP_BASE64 ~/k3s-base64-\$(hostname).txt"