# NOTE! This repository was created by Kiro-CLI and hasn't been reviewed yet!!!


# CRI-O Seccomp Notifier Experiment

This repository demonstrates how to use CRI-O's seccomp notifier feature to log blocked syscalls in Kubernetes pods.

## Quick Links

- **[SETUP.md](SETUP.md)** - Complete setup from scratch (minikube + CRI-O configuration)
- **[WORKING_SETUP.md](WORKING_SETUP.md)** - Verified configuration and results
- **[METRICS.md](METRICS.md)** - Detailed metrics configuration
- **[QUICKREF.md](QUICKREF.md)** - Quick reference commands

## Prerequisites

- Kubernetes cluster with CRI-O runtime (see [SETUP.md](SETUP.md) for installation)
- CRI-O 1.24+ with seccomp notifier configured
- kubectl configured
- Basic understanding of seccomp and syscalls

## Quick Start

### 1. Setup Cluster (if needed)

If you don't have a cluster with CRI-O configured:

```bash
# Install and start minikube with CRI-O
minikube start --container-runtime=cri-o
```

See [SETUP.md](SETUP.md) for complete installation instructions.

### 2. Configure CRI-O

**Required**: Enable metrics and allow the seccomp notifier annotation.

```bash
# Deploy node-shell for configuration access
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s

# Configure CRI-O (see SETUP.md for detailed steps)
# 1. Enable metrics
# 2. Allow io.kubernetes.cri-o.seccompNotifierAction annotation
# 3. Restart CRI-O
```

See [SETUP.md](SETUP.md) for step-by-step configuration commands.

### 3. Run Experiment

## Experiment Overview

This experiment:
1. Deploys a pod with the RuntimeDefault seccomp profile
2. Enables CRI-O's seccomp notifier annotation to log blocked syscalls
3. Runs a test program that attempts several syscalls blocked by the default profile
4. Demonstrates how to check for blocked syscalls

## Files

- **[SETUP.md](SETUP.md)** - Complete setup guide from scratch
- **[WORKING_SETUP.md](WORKING_SETUP.md)** - Verified configuration and results  
- **[METRICS.md](METRICS.md)** - Detailed metrics configuration
- **[QUICKREF.md](QUICKREF.md)** - Quick reference commands
- **[DEEP_DIVE.md](DEEP_DIVE.md)** - Technical deep dive
- **[GITHUB.md](GITHUB.md)** - Publishing instructions
- `pod.yaml` - Pod manifest with seccomp configuration
- `seccomp-test.c` - C program that attempts blocked syscalls
- `node-shell.yaml` - Privileged pod for accessing node
- `Dockerfile` - (Optional) Build container image
- `run-experiment.sh` - Automated experiment script

## Running the Experiment

**Important**: CRI-O must be configured before running the experiment. See [SETUP.md](SETUP.md).

### Step 1: Verify CRI-O Configuration

```bash
# Check metrics endpoint is accessible
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | head -5"

# Verify annotation is allowed
kubectl exec node-shell -- sh -c "chroot /host crio config | grep -A 5 'allowed_annotations'"
```

If these fail, see [SETUP.md](SETUP.md) for configuration steps.

### Step 2: Deploy the Test Pod

```bash
kubectl apply -f pod.yaml
```

The pod uses the `gcc:12-bookworm` image and compiles/runs the test program inline.

### Step 2: Wait for Pod to Start

```bash
kubectl wait --for=condition=Ready pod/seccomp-test --timeout=300s
```

### Step 3: Check Test Results

View the syscall test output:

```bash
kubectl exec seccomp-test -- cat /tmp/output.txt
```

Expected output:
```
Testing blocked syscalls...

1. Attempting clone3()...
   Result: -1, errno: 38 (Function not implemented)

2. Attempting bpf()...
   Result: -1, errno: 38 (Function not implemented)

3. Attempting perf_event_open()...
   Result: -1, errno: 38 (Function not implemented)

4. Attempting userfaultfd()...
   Result: -1, errno: 38 (Function not implemented)

Test complete. Check for EPERM (errno 1) indicating blocked syscalls.
```

**Note**: All syscalls return errno 38 (ENOSYS - "Function not implemented"). See [RESULTS.md](RESULTS.md) for detailed analysis of why only `clone3` appears in metrics.

### Step 4: Check CRI-O Logs for Seccomp Events

Deploy a privileged pod to access node logs:

```bash
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s
```

Check CRI-O logs:

```bash
kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '10 minutes ago' | grep -i seccomp"
```

### Step 5: Check for Seccomp Metrics (if available)

The `crio_containers_seccomp_notifier_count_total` metric tracks blocked syscalls:

```bash
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | grep seccomp_notifier"
```

Expected output:
```
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="clone3"} 1
```

**Important**: Only `clone3` appears in the metrics, even though all 4 syscalls were attempted. See [RESULTS.md](RESULTS.md) for a detailed comparison and analysis.

**Note**: Requires CRI-O configuration. See `WORKING_SETUP.md` for complete setup.

## Understanding the Results

### Syscalls Tested

1. **clone3()** (syscall 435) - Modern process creation, blocked by default profile
2. **bpf()** (syscall 321) - BPF system calls, security-sensitive
3. **perf_event_open()** (syscall 298) - Performance monitoring, can leak information
4. **userfaultfd()** (syscall 323) - User-space page fault handling, security risk

### Seccomp Profile

The `RuntimeDefault` seccomp profile is defined by the container runtime (CRI-O) and blocks potentially dangerous syscalls while allowing common operations.

### Seccomp Notifier Annotation

The annotation `io.kubernetes.cri-o.seccompNotifierAction: "log"` tells CRI-O to log blocked syscalls. This is a CRI-O specific feature.

## Troubleshooting

### Pod Stuck in ContainerCreating

Check events:
```bash
kubectl describe pod seccomp-test
```

### No Logs Visible

The test program writes to stdout. Check with:
```bash
kubectl logs seccomp-test
# or
kubectl exec seccomp-test -- ps aux
```

### Metrics Not Available

CRI-O metrics may require additional configuration. Check:
```bash
kubectl exec node-shell -- cat /host/etc/crio/crio.conf.d/*.conf
```

## Cleanup

```bash
kubectl delete pod seccomp-test node-shell
```

## References

- [Kubernetes Seccomp Documentation](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [CRI-O Seccomp Notifier](https://github.com/cri-o/cri-o/blob/main/docs/crio.conf.5.md)
- [Linux Seccomp](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)

## Notes

- The seccomp notifier feature availability depends on CRI-O version and configuration
- Some syscalls may return ENOSYS (Function not implemented) instead of EPERM if not supported by the kernel
- The RuntimeDefault profile varies between container runtimes and versions
