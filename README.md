# NOTE! This repository was created by Kiro-CLI and hasn't been reviewed yet!!!


# CRI-O Seccomp Notifier Experiment

Demonstrates CRI-O's seccomp notifier feature on Kubernetes: deploys a pod that
attempts blocked syscalls, then compares the test output against CRI-O's
`crio_containers_seccomp_notifier_count_total` Prometheus metric.

**Key finding**: CRI-O's notifier tracks only the **first** blocked syscall per
container. See [RESULTS.md](RESULTS.md) for the full analysis.

## Quick Links

- **[SETUP.md](SETUP.md)** - Complete setup from scratch (minikube + CRI-O)
- **[RESULTS.md](RESULTS.md)** - Experiment results and root cause analysis
- **[DEEP_DIVE.md](DEEP_DIVE.md)** - Technical deep dive
- **[QUICKREF.md](QUICKREF.md)** - Quick reference commands

## Prerequisites

- Kubernetes cluster with CRI-O runtime (see [SETUP.md](SETUP.md))
- CRI-O 1.24+ with seccomp notifier and metrics enabled
- kubectl

## Quick Start

### 1. Setup Cluster

```bash
minikube start --container-runtime=cri-o
```

See [SETUP.md](SETUP.md) for complete instructions including CRI-O configuration.

### 2. Configure CRI-O

Deploy a node-shell pod and configure CRI-O to enable metrics and the notifier
annotation:

```bash
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s
```

See [SETUP.md](SETUP.md) for the configuration commands.

### 3. Run the Experiment

```bash
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/seccomp-test --timeout=300s
```

### 4. Check Results

```bash
# Test program output
kubectl exec seccomp-test -- cat /tmp/output.txt

# CRI-O seccomp notifier metrics
kubectl exec node-shell -- sh -c \
  "chroot /host curl -s http://127.0.0.1:9090/metrics | grep seccomp_notifier"
```

## What the Test Does

The test program calls 7 syscalls from 3 categories:

| Category | Syscalls | Profile Rule |
|----------|----------|-------------|
| Explicit allowlist | clone3 | SCMP_ACT_ALLOW |
| Unconditional deny | swapon, swapoff, kexec_load | SCMP_ACT_ERRNO/EPERM |
| Conditional deny | bpf, perf_event_open, userfaultfd | SCMP_ACT_ERRNO (caps-based) |

CRI-O rewrites all explicit rules to `SCMP_ACT_NOTIFY`, but the notifier
handler only processes the first notification and then exits. Result:

- All 7 syscalls return errno 38 (ENOSYS)
- Only the first syscall (`clone3`) appears in the metric
- Reordering the syscalls changes which one is tracked

See [RESULTS.md](RESULTS.md) for the complete analysis with CRI-O source code
references.

## Files

| File | Description |
|------|-------------|
| `pod.yaml` | Test pod with seccomp notifier annotation |
| `node-shell.yaml` | Privileged pod for node access |
| `seccomp-test.c` | Standalone C source (also inlined in pod.yaml) |
| `Dockerfile` | Optional: build the test as a container image |
| `run-experiment.sh` | Automated experiment script |
| `SETUP.md` | Setup guide |
| `RESULTS.md` | Results and analysis |
| `DEEP_DIVE.md` | Technical deep dive |
| `METRICS.md` | Metrics configuration |
| `WORKING_SETUP.md` | Verified working configuration |
| `QUICKREF.md` | Quick reference |
| `GITHUB.md` | Publishing instructions |

## Cleanup

```bash
kubectl delete pod seccomp-test node-shell
```

## References

- [Kubernetes Seccomp Documentation](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [CRI-O Seccomp Notifier Blog Post](https://kubernetes.io/blog/2022/12/02/seccomp-notifier/)
- [CRI-O Notifier Source](https://github.com/cri-o/cri-o/blob/main/internal/config/seccomp/notifier.go)
- [Linux Seccomp](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)
