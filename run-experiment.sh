#!/bin/bash
set -e

echo "=== CRI-O Seccomp Notifier Experiment ==="
echo

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found"
    exit 1
fi

if ! kubectl get nodes &> /dev/null; then
    echo "Error: Kubernetes cluster not accessible"
    echo "See SETUP.md for cluster setup instructions"
    exit 1
fi

# Verify CRI-O runtime
RUNTIME=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}')
if [[ ! $RUNTIME =~ cri-o ]]; then
    echo "Warning: Container runtime is $RUNTIME, not CRI-O"
    echo "This experiment requires CRI-O. See SETUP.md for setup instructions."
    exit 1
fi

echo "✓ Prerequisites met"
echo

# Check CRI-O configuration
echo "Verifying CRI-O configuration..."
if ! kubectl get pod node-shell &> /dev/null; then
    echo "Deploying node-shell..."
    kubectl apply -f node-shell.yaml
    kubectl wait --for=condition=Ready pod/node-shell --timeout=60s
fi

# Check metrics endpoint
if ! kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics" &> /dev/null; then
    echo "Error: CRI-O metrics endpoint not accessible"
    echo "Please configure CRI-O first. See SETUP.md for instructions."
    exit 1
fi

# Check annotation is allowed
if ! kubectl exec node-shell -- sh -c "chroot /host crio config | grep 'io.kubernetes.cri-o.seccompNotifierAction'" &> /dev/null; then
    echo "Warning: seccompNotifierAction annotation may not be allowed"
    echo "Metrics may not appear. See SETUP.md for configuration."
fi

echo "✓ CRI-O configuration verified"
echo

# Deploy test pod
echo "Step 1: Deploying test pod..."
kubectl apply -f pod.yaml
echo

# Wait for pod
echo "Step 2: Waiting for pod to be ready (this may take a few minutes)..."
kubectl wait --for=condition=Ready pod/seccomp-test --timeout=300s || {
    echo "Pod failed to start. Checking status..."
    kubectl describe pod seccomp-test
    exit 1
}
echo "✓ Pod is ready"
echo

# Wait a bit for the test to run
echo "Step 3: Waiting for test to complete..."
sleep 5
echo

# Show results
echo "Step 4: Test Results"
echo "===================="
kubectl logs seccomp-test 2>/dev/null || {
    echo "Logs not available via kubectl logs, checking process output..."
    kubectl exec seccomp-test -- ps aux | grep test
}
echo
echo "===================="
echo

# Check metrics
echo "Step 5: Checking seccomp notifier metrics..."
echo "===================="
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | grep seccomp_notifier" || echo "No seccomp metrics found. See SETUP.md for configuration."
echo "===================="
echo

# Check CRI-O logs
echo "Step 6: Checking CRI-O logs for seccomp events..."
echo "===================="
kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '10 minutes ago' | grep -i 'seccomp notifier'" | head -5 || echo "No seccomp notifier log entries found"
echo "===================="
echo

echo "Experiment complete!"
echo
echo "For detailed results, see WORKING_SETUP.md"
echo "To clean up, run:"
echo "  kubectl delete pod seccomp-test node-shell"
