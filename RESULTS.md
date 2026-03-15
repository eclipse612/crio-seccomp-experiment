# Experiment Results - Syscall Comparison

This document shows the comparison between syscalls attempted by the test program and what CRI-O's seccomp notifier actually tracked, along with an explanation of the observed behaviour.

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
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="clone3"} 1
```

## CRI-O Log

CRI-O explicitly logs this limitation on container creation:

```
The seccomp profile default action SCMP_ACT_ERRNO cannot be overridden to SCMP_ACT_NOTIFY,
which means that syscalls using that default action can't be traced by the notifier
```

## Comparison

| Syscall | Number | errno | Meaning | Tracked by Notifier |
|---------|--------|-------|---------|---------------------|
| clone3 | 435 | 38 (ENOSYS) | Intercepted by notifier | ✅ Yes |
| bpf | 321 | 38 (ENOSYS) | Hit defaultAction | ❌ No |
| perf_event_open | 298 | 38 (ENOSYS) | Hit defaultAction | ❌ No |
| userfaultfd | 323 | 38 (ENOSYS) | Hit defaultAction | ❌ No |

## Explanation

### How the seccomp notifier works

When the `io.kubernetes.cri-o.seccompNotifierAction` annotation is set, CRI-O rewrites the seccomp profile before applying it. It replaces explicit `SCMP_ACT_ERRNO` (and `SCMP_ACT_KILL*`) actions in the `syscalls` list with `SCMP_ACT_NOTIFY`. This allows CRI-O to receive a notification from the kernel when those syscalls are attempted, log them, and update metrics.

However, CRI-O **cannot** replace the profile's `defaultAction`. The kernel's seccomp notify mechanism does not support notification on the default action.

### The RuntimeDefault profile structure

The CRI-O RuntimeDefault profile (from `/usr/share/containers/seccomp.json`) has:

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "defaultErrnoRet": 38,
  "defaultErrno": "ENOSYS"
}
```

The default action returns ENOSYS (errno 38) for any syscall not matched by an explicit rule. This is by design — unknown/new syscalls should return "Function not implemented" rather than "Operation not permitted".

### Why clone3 is tracked

`clone3` is explicitly listed in the profile's **allowlist** (`SCMP_ACT_ALLOW`). When CRI-O injects the notifier, it replaces this `SCMP_ACT_ALLOW` with `SCMP_ACT_NOTIFY`. The notifier intercepts the call, logs it, updates the metric, and returns ENOSYS.

This is known behaviour: CRI-O has a specific function that returns ENOSYS for `clone3` via the notifier, because `clone3` is used by newer glibc versions and returning ENOSYS causes a graceful fallback to the older `clone` syscall.

### Why bpf, perf_event_open, and userfaultfd are NOT tracked

These syscalls have explicit `SCMP_ACT_ERRNO`/EPERM rules in the profile, but those rules use conditional `includes`/`excludes` based on Linux capabilities:

**bpf and perf_event_open:**
```json
{
  "names": ["bpf", "perf_event_open", ...],
  "action": "SCMP_ACT_ALLOW",
  "includes": { "caps": ["CAP_SYS_ADMIN"] }
},
{
  "names": ["bpf", "perf_event_open", ...],
  "action": "SCMP_ACT_ERRNO",
  "excludes": { "caps": ["CAP_SYS_ADMIN"] },
  "errno": "EPERM"
}
```

**userfaultfd:**
```json
{
  "names": ["userfaultfd", ...],
  "action": "SCMP_ACT_ERRNO",
  "errno": "EPERM"
}
```

When CRI-O compiles the profile with the notifier injection, these syscalls end up falling through to the `defaultAction` (ENOSYS) rather than matching their explicit rules. Since the notifier **cannot intercept the defaultAction**, they are not tracked.

The result: all three return errno 38 (ENOSYS) instead of the expected errno 1 (EPERM), and none appear in the seccomp notifier metrics.

### Summary

```
                    ┌──────────────────────────┐
                    │   Syscall attempted       │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │  Explicit rule in profile?│
                    └────┬──────────────┬──────┘
                         │              │
                        Yes             No
                         │              │
              ┌──────────▼──────┐  ┌───▼────────────────┐
              │ CRI-O replaces  │  │ Falls through to    │
              │ with NOTIFY     │  │ defaultAction       │
              │                 │  │ (ENOSYS, errno 38)  │
              │ → Tracked ✅    │  │                     │
              │ → Metric updated│  │ → NOT tracked ❌    │
              │ → Returns ENOSYS│  │ → No metric         │
              └─────────────────┘  └─────────────────────┘
```

## Implications

1. **The seccomp notifier only tracks syscalls with explicit rules** in the profile — not those handled by the defaultAction.

2. **With the RuntimeDefault profile**, most blocked syscalls fall through to the defaultAction and are invisible to the notifier. Only syscalls in the explicit allowlist (like `clone3`) are tracked.

3. **To track specific syscalls**, you would need a custom seccomp profile with explicit `SCMP_ACT_ERRNO` rules for each syscall you want to monitor, rather than relying on the defaultAction.

4. **The errno changes** when the notifier is active: syscalls that would normally return EPERM (errno 1) may return ENOSYS (errno 38) instead, because they fall through to the defaultAction rather than matching their conditional rules.

## Environment

- Kubernetes: v1.35.1
- CRI-O: 1.35.0
- Runtime: crun 1.25.1
- Kernel: 6.6.87.2-microsoft-standard-WSL2
- Seccomp Profile: RuntimeDefault
- Date: 2026-03-15
