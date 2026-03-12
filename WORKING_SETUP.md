# Complete Working Setup - CRI-O Seccomp Notifier

This document describes the complete, tested configuration for enabling CRI-O's seccomp notifier feature and metrics.

## Environment

- **Minikube**: v1.35.1
- **CRI-O**: 1.35.0
- **Kernel**: 6.6.87.2-microsoft-standard-WSL2
- **Runtime**: crun 1.25.1

## Required Configuration

### 1. Enable CRI-O Metrics

File: `/etc/crio/crio.conf.d/99-metrics.conf`

```toml
[crio.metrics]
enable_metrics = true
metrics_port = 9090
```

### 2. Allow Seccomp Notifier Annotation

File: `/etc/crio/crio.conf.d/10-crio.conf`

```toml
[crio.image]
signature_policy = "/etc/crio/policy.json"

[crio.runtime]
default_runtime = "crun"

[crio.runtime.runtimes.crun]
runtime_path = "/usr/libexec/crio/crun"
runtime_root = "/run/crun"
monitor_path = "/usr/libexec/crio/conmon"
allowed_annotations = [
    "io.containers.trace-syscall",
    "io.kubernetes.cri-o.seccompNotifierAction",
]

[crio.runtime.runtimes.runc]
runtime_path = "/usr/libexec/crio/runc"
runtime_root = "/run/runc"
monitor_path = "/usr/libexec/crio/conmon"
allowed_annotations = [
    "io.kubernetes.cri-o.seccompNotifierAction",
]
```

**Critical**: The annotation must be in the `allowed_annotations` list for your active runtime (crun or runc).

### 3. Pod Configuration

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-test
  annotations:
    io.kubernetes.cri-o.seccompNotifierAction: "log"
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: test
    image: gcc:12-bookworm
    # ... container spec
```

## Setup Commands

```bash
# 1. Deploy node-shell for configuration access
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s

# 2. Configure metrics
kubectl exec node-shell -- sh -c "cat > /host/etc/crio/crio.conf.d/99-metrics.conf << 'EOF'
[crio.metrics]
enable_metrics = true
metrics_port = 9090
EOF
"

# 3. Configure allowed annotations
kubectl exec node-shell -- sh -c "cat > /host/etc/crio/crio.conf.d/10-crio.conf << 'EOF'
[crio.image]
signature_policy = \"/etc/crio/policy.json\"

[crio.runtime]
default_runtime = \"crun\"

[crio.runtime.runtimes.crun]
runtime_path = \"/usr/libexec/crio/crun\"
runtime_root = \"/run/crun\"
monitor_path = \"/usr/libexec/crio/conmon\"
allowed_annotations = [
    \"io.containers.trace-syscall\",
    \"io.kubernetes.cri-o.seccompNotifierAction\",
]

[crio.runtime.runtimes.runc]
runtime_path = \"/usr/libexec/crio/runc\"
runtime_root = \"/run/runc\"
monitor_path = \"/usr/libexec/crio/conmon\"
allowed_annotations = [
    \"io.kubernetes.cri-o.seccompNotifierAction\",
]
EOF
"

# 4. Restart CRI-O
kubectl exec node-shell -- sh -c "chroot /host systemctl restart crio"
sleep 15
kubectl get nodes

# 5. Recreate node-shell after restart
kubectl delete pod node-shell
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s

# 6. Deploy test pod
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/seccomp-test --timeout=300s
sleep 5

# 7. Check metrics
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | grep seccomp_notifier"
```

## Verified Results

### Metrics Output

```
# HELP container_runtime_crio_containers_seccomp_notifier_count_total Number of forbidden syscalls by syscall and container name
# TYPE container_runtime_crio_containers_seccomp_notifier_count_total counter
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="bpf"} 1
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="clone3"} 1
```

### CRI-O Logs

```bash
kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '5 minutes ago' | grep 'seccomp notifier'"
```

Expected output:
```
Starting seccomp notifier watcher
```

### Test Program Output

The test program attempts these syscalls:
- `clone3()` (syscall 435) - Returns ENOSYS or EPERM
- `bpf()` (syscall 321) - Returns EPERM
- `perf_event_open()` (syscall 298) - Returns EPERM
- `userfaultfd()` (syscall 323) - Returns EPERM

## Key Findings

### What Works

✅ Metrics endpoint accessible at `http://127.0.0.1:9090/metrics` on the node  
✅ Seccomp notifier watcher starts successfully  
✅ Blocked syscalls are detected and counted  
✅ Metrics use syscall names (not numbers) as labels  
✅ Each container instance gets separate metric entries  

### Limitations Discovered

⚠️ **Not all blocked syscalls appear in metrics** - Only some syscalls trigger the notifier:
- `bpf` - ✅ Tracked
- `clone3` - ✅ Tracked  
- `perf_event_open` - ❌ Not appearing in metrics
- `userfaultfd` - ❌ Not appearing in metrics

This may be due to:
- How the seccomp filter is configured
- Timing of when syscalls are called
- Specific seccomp notify implementation details
- Some syscalls may be blocked at a different layer

⚠️ **Annotation must be explicitly allowed** - The default CRI-O configuration only allows `io.containers.trace-syscall` for crun. The seccomp notifier annotation must be added manually.

⚠️ **Requires CRI-O restart** - Configuration changes require a full CRI-O restart, which disrupts all running pods.

## Troubleshooting Checklist

- [ ] Metrics enabled in `/etc/crio/crio.conf.d/99-metrics.conf`
- [ ] Annotation in allowed list for active runtime (crun or runc)
- [ ] CRI-O restarted after configuration changes
- [ ] Pod has annotation: `io.kubernetes.cri-o.seccompNotifierAction: "log"`
- [ ] Pod has seccomp profile: `type: RuntimeDefault`
- [ ] CRI-O listening on port 9090: `ss -tlnp | grep :9090`
- [ ] Seccomp notifier watcher started (check journalctl)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Pod: seccomp-test                                   │
│ Annotation: io.kubernetes.cri-o.seccompNotifierAction: "log" │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │ Container: test                               │ │
│  │ SecurityContext:                              │ │
│  │   seccompProfile: RuntimeDefault              │ │
│  │                                               │ │
│  │  ┌─────────────────────────────────────────┐ │ │
│  │  │ Test Program                            │ │ │
│  │  │ - syscall(321) → bpf                    │ │ │
│  │  │ - syscall(298) → perf_event_open        │ │ │
│  │  │ - syscall(323) → userfaultfd            │ │ │
│  │  │ - syscall(435) → clone3                 │ │ │
│  │  └─────────────────────────────────────────┘ │ │
│  │                    ↓                          │ │
│  │  ┌─────────────────────────────────────────┐ │ │
│  │  │ Seccomp Filter (RuntimeDefault)         │ │ │
│  │  │ - Blocks dangerous syscalls             │ │ │
│  │  │ - Returns EPERM                         │ │ │
│  │  │ - Triggers seccomp notify               │ │ │
│  │  └─────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│ CRI-O Runtime                                       │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │ Seccomp Notifier Watcher                      │ │
│  │ - Receives notifications from seccomp filter  │ │
│  │ - Logs blocked syscalls                       │ │
│  │ - Updates Prometheus metrics                  │ │
│  └───────────────────────────────────────────────┘ │
│                    ↓                                │
│  ┌───────────────────────────────────────────────┐ │
│  │ Metrics Endpoint (port 9090)                  │ │
│  │ container_runtime_crio_containers_seccomp_    │ │
│  │   notifier_count_total{                       │ │
│  │     name="...",                                │ │
│  │     syscall="bpf"                             │ │
│  │   } 1                                          │ │
│  └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

## Metric Details

### Metric Name
`container_runtime_crio_containers_seccomp_notifier_count_total`

### Type
Counter (monotonically increasing)

### Labels
- `name`: Full container name (e.g., `k8s_test_seccomp-test_default_<uid>_<restart>`)
- `syscall`: Syscall name (e.g., "bpf", "clone3", "perf_event_open")

### Example Query (Prometheus)
```promql
# Total blocked syscalls across all containers
sum(container_runtime_crio_containers_seccomp_notifier_count_total)

# Blocked syscalls by syscall type
sum by (syscall) (container_runtime_crio_containers_seccomp_notifier_count_total)

# Blocked syscalls for specific pod
container_runtime_crio_containers_seccomp_notifier_count_total{name=~".*seccomp-test.*"}
```

## Production Considerations

1. **Performance Impact**: Seccomp notifier has overhead. Use only for debugging/auditing.

2. **Metric Cardinality**: Each container instance creates new metric series. Monitor cardinality in production.

3. **Configuration Management**: Use configuration management tools (Ansible, Puppet) to deploy CRI-O configs consistently.

4. **Monitoring**: Set up alerts for unexpected syscall blocks that might indicate:
   - Application incompatibility with seccomp profile
   - Potential security incidents
   - Need for custom seccomp profiles

5. **Log Rotation**: CRI-O logs can grow with seccomp notifications. Ensure proper log rotation.

## References

- [CRI-O Configuration](https://github.com/cri-o/cri-o/blob/main/docs/crio.conf.5.md)
- [Seccomp Notifier PR](https://github.com/cri-o/cri-o/pull/5563)
- [Kubernetes Seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [Linux Seccomp](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)

## Tested Date

2026-03-12
