# Experiment Results - Syscall Comparison

This document shows the comparison between syscalls attempted by the test program and what CRI-O's seccomp notifier actually tracked.

## Test Program Output

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

## CRI-O Seccomp Notifier Metrics

```
# HELP container_runtime_crio_containers_seccomp_notifier_count_total Number of forbidden syscalls by syscall and container name
# TYPE container_runtime_crio_containers_seccomp_notifier_count_total counter
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="clone3"} 1
```

## Analysis

### Syscalls Attempted vs Tracked

| Syscall | Number | Attempted | Error Code | Tracked by Notifier |
|---------|--------|-----------|------------|---------------------|
| clone3 | 435 | ✅ | ENOSYS (38) | ✅ |
| bpf | 321 | ✅ | ENOSYS (38) | ❌ |
| perf_event_open | 298 | ✅ | ENOSYS (38) | ❌ |
| userfaultfd | 323 | ✅ | ENOSYS (38) | ❌ |

### Key Findings

1. **All syscalls returned ENOSYS (38)** - "Function not implemented"
   - This is different from EPERM (1) - "Operation not permitted"
   - ENOSYS typically means the syscall is not available in the kernel or blocked before reaching seccomp

2. **Only clone3 was tracked** by the seccomp notifier
   - This suggests the seccomp notifier only tracks certain syscalls
   - Or the other syscalls were blocked at a different layer (before seccomp)

3. **Seccomp notifier is selective**
   - Not all blocked syscalls trigger the notifier
   - The notifier appears to track syscalls that reach the seccomp filter
   - Syscalls blocked earlier in the call chain may not be tracked

### Why ENOSYS Instead of EPERM?

There are several possible reasons:

1. **Kernel doesn't support these syscalls** - The kernel version may not have these syscalls implemented
2. **Seccomp returns ENOSYS** - Some seccomp profiles return ENOSYS instead of EPERM for certain syscalls
3. **Architecture mismatch** - Syscall numbers may differ between architectures
4. **Early blocking** - Syscalls blocked before reaching the seccomp filter

### Why Only clone3 is Tracked?

Possible explanations:

1. **Seccomp notify mechanism** - Only syscalls that trigger the seccomp NOTIFY action are tracked
2. **Filter configuration** - The RuntimeDefault profile may only have NOTIFY configured for certain syscalls
3. **Implementation detail** - CRI-O's seccomp notifier may only track specific syscall types

## Verification Steps

### Check Kernel Support

```bash
# Check if syscalls are available in kernel
kubectl exec seccomp-test -- grep -E "clone3|bpf|perf_event_open|userfaultfd" /proc/kallsyms
```

### Check Seccomp Profile

The RuntimeDefault profile is defined by CRI-O. To see it:

```bash
kubectl exec node-shell -- sh -c "chroot /host cat /usr/share/containers/seccomp.json | grep -A 5 -B 5 'clone3\|bpf\|perf_event_open\|userfaultfd'"
```

### Check CRI-O Logs

```bash
kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '5 minutes ago' | grep -i 'seccomp\|syscall'"
```

## Implications

### For Security Monitoring

- **Don't rely solely on seccomp notifier metrics** for complete syscall monitoring
- The notifier only tracks a subset of blocked syscalls
- Combine with other monitoring tools (auditd, eBPF) for comprehensive coverage

### For Debugging

- **ENOSYS vs EPERM matters** - Different error codes indicate different blocking mechanisms
- Check multiple sources: application logs, seccomp metrics, kernel logs
- The seccomp notifier is useful but not exhaustive

### For Custom Seccomp Profiles

- If you need to track specific syscalls, ensure they're configured with NOTIFY action
- Test your profile to verify which syscalls are actually tracked
- Document which syscalls are monitored vs blocked silently

## Recommendations

1. **Use seccomp notifier for high-value syscalls** - Focus on the most security-sensitive operations
2. **Combine monitoring approaches** - Use seccomp notifier + auditd + eBPF for complete visibility
3. **Test your profiles** - Always verify which syscalls are tracked in your environment
4. **Document behavior** - Record which syscalls trigger notifications in your setup

## Environment Details

- **Kubernetes**: v1.35.1
- **CRI-O**: 1.35.0
- **Runtime**: crun 1.25.1
- **Kernel**: 6.6.87.2-microsoft-standard-WSL2
- **Seccomp Profile**: RuntimeDefault
- **Date**: 2026-03-13
