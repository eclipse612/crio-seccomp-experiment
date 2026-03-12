# CRI-O Seccomp Notifier Experiment

This repository demonstrates how to use CRI-O's seccomp notifier feature to log blocked syscalls in Kubernetes pods.

## Prerequisites

- Minikube with CRI-O runtime
- kubectl configured
- Basic understanding of seccomp and syscalls

## Setup Minikube with CRI-O

```bash
minikube start --container-runtime=cri-o
```

## Experiment Overview

This experiment:
1. Deploys a pod with the RuntimeDefault seccomp profile
2. Enables CRI-O's seccomp notifier annotation to log blocked syscalls
3. Runs a test program that attempts several syscalls blocked by the default profile
4. Demonstrates how to check for blocked syscalls

## Files

- `pod.yaml` - Pod manifest with seccomp configuration
- `seccomp-test.c` - C program that attempts blocked syscalls
- `node-shell.yaml` - Privileged pod for accessing node logs
- `Dockerfile` - (Optional) Build container image

## Running the Experiment

### Step 1: Deploy the Test Pod

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
kubectl exec seccomp-test -- cat /proc/1/fd/1
```

Expected output:
```
Testing blocked syscalls...

1. Attempting clone3()...
   Result: -1, errno: 38 (Function not implemented)

2. Attempting bpf()...
   Result: -1, errno: 1 (Operation not permitted)

3. Attempting perf_event_open()...
   Result: -1, errno: 1 (Operation not permitted)

4. Attempting userfaultfd()...
   Result: -1, errno: 1 (Operation not permitted)

Test complete. Check for EPERM (errno 1) indicating blocked syscalls.
```

**Note**: `errno 1` (EPERM) indicates the syscall was blocked by seccomp.

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

The `crio_containers_seccomp_notifier_count_total` metric tracks blocked syscalls. Access depends on CRI-O configuration:

```bash
# From within the node
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | grep seccomp"
```

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
