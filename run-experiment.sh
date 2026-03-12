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

if ! command -v minikube &> /dev/null; then
    echo "Error: minikube not found"
    exit 1
fi

# Check if minikube is running
if ! kubectl get nodes &> /dev/null; then
    echo "Error: Kubernetes cluster not accessible"
    echo "Start minikube with: minikube start --container-runtime=cri-o"
    exit 1
fi

# Verify CRI-O runtime
RUNTIME=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}')
if [[ ! $RUNTIME =~ cri-o ]]; then
    echo "Warning: Container runtime is $RUNTIME, not CRI-O"
    echo "This experiment is designed for CRI-O"
fi

echo "✓ Prerequisites met"
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
kubectl exec seccomp-test -- cat /proc/1/fd/1 2>/dev/null || {
    echo "Could not read output directly, trying logs..."
    kubectl logs seccomp-test
}
echo
echo "===================="
echo

# Deploy node shell for log access
echo "Step 5: Deploying node shell for log access..."
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s
echo "✓ Node shell ready"
echo

# Check CRI-O logs
echo "Step 6: Checking CRI-O logs for seccomp events..."
echo "===================="
kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '10 minutes ago' | grep -i seccomp" | head -20 || echo "No seccomp-specific log entries found"
echo "===================="
echo

echo "Experiment complete!"
echo
echo "To clean up, run:"
echo "  kubectl delete pod seccomp-test node-shell"
