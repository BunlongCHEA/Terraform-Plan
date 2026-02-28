#!/bin/bash

echo "=========================================="
echo "  Testing Base64 Kubeconfig"
echo "=========================================="
echo ""

# Your base64 encoded kubeconfig (paste the output from Step 1 here)
KUBECONFIG_BASE64="$(cat kubeconfig-base64.txt)"

# Decode and save
echo "$KUBECONFIG_BASE64" | base64 -d > test-kubeconfig.yaml

echo "✓ Kubeconfig decoded and saved to test-kubeconfig.yaml"
echo ""

# Display the decoded kubeconfig
echo "=== Decoded Kubeconfig ==="
cat test-kubeconfig.yaml
echo ""

# Set kubeconfig
export KUBECONFIG=./test-kubeconfig.yaml

# Test connection
echo "=== Testing Connection ==="
echo ""

echo "1. Testing kubectl version..."
kubectl version --client
echo ""

echo "2. Testing cluster info..."
if kubectl cluster-info; then
    echo "✓ Successfully connected to cluster!"
else
    echo "✗ Failed to connect to cluster"
    exit 1
fi
echo ""

echo "3. Getting nodes..."
kubectl get nodes
echo ""

echo "4. Getting namespaces..."
kubectl get namespaces
echo ""

echo "5. Checking ArgoCD namespace..."
if kubectl get namespace argocd &>/dev/null; then
    echo "✓ ArgoCD namespace exists"
    kubectl get pods -n argocd
else
    echo "⚠ ArgoCD namespace not found"
fi
echo ""

echo "6. Checking kyc-blockchain namespace..."
if kubectl get namespace kyc-blockchain &>/dev/null; then
    echo "✓ kyc-blockchain namespace exists"
    kubectl get all -n kyc-blockchain
else
    echo "⚠ kyc-blockchain namespace not found"
fi
echo ""

echo "=========================================="
echo "  Test Complete!"
echo "=========================================="
echo ""
echo "If all tests passed, you can use this base64 string"
echo "in GitLab CI/CD variable: KUBE_CONFIG_BASE64"
echo ""