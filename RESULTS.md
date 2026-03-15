# Experiment Results

This document compares syscalls attempted by the test program against CRI-O's
seccomp notifier metrics, and explains the observed behaviour based on CRI-O's
source code.

## Test Program Output

```
Testing blocked syscalls...

=== allowlist (SCMP_ACT_ALLOW -> NOTIFY) ===
1. clone3 (nr 435): ret=-1, errno=38 (Function not implemented)

=== unconditional deny (SCMP_ACT_ERRNO -> NOTIFY) ===
2. swapon (nr 167): ret=-1, errno=38 (Function not implemented)
3. swapoff (nr 168): ret=-1, errno=38 (Function not implemented)
4. kexec_load (nr 246): ret=-1, errno=38 (Function not implemented)

=== conditional deny (caps-based -> NOTIFY) ===
5. bpf (nr 321): ret=-1, errno=38 (Function not implemented)
6. perf_event_open (nr 298): ret=-1, errno=38 (Function not implemented)

=== conditional deny (no caps -> NOTIFY) ===
7. userfaultfd (nr 323): ret=-1, errno=38 (Function not implemented)
```

## CRI-O Seccomp Notifier Metrics

```
container_runtime_crio_containers_seccomp_notifier_count_total{...,syscall="clone3"} 1
```

Only `clone3` appears. The other 6 syscalls are absent from the metrics.

## CRI-O Log

```
Injecting seccomp notifier into seccomp profile of container b06ee4...
The seccomp profile default action SCMP_ACT_ERRNO cannot be overridden to SCMP_ACT_NOTIFY, ...
Got seccomp notifier message for container ID: b06ee4... (syscall = clone3)
```

## Comparison

| # | Syscall | Profile Rule | Rewritten to NOTIFY? | Tracked? | errno |
|---|---------|-------------|---------------------|----------|-------|
| 1 | clone3 | ALLOW (allowlist) | ✅ Yes | ✅ Yes (first) | 38 (ENOSYS) |
| 2 | swapon | ERRNO/EPERM (unconditional) | ✅ Yes | ❌ No | 38 (ENOSYS) |
| 3 | swapoff | ERRNO/EPERM (unconditional) | ✅ Yes | ❌ No | 38 (ENOSYS) |
| 4 | kexec_load | ERRNO/EPERM (unconditional) | ✅ Yes | ❌ No | 38 (ENOSYS) |
| 5 | bpf | ERRNO/EPERM (if !CAP_SYS_ADMIN) | ✅ Yes | ❌ No | 38 (ENOSYS) |
| 6 | perf_event_open | ERRNO/EPERM (if !CAP_SYS_ADMIN) | ✅ Yes | ❌ No | 38 (ENOSYS) |
| 7 | userfaultfd | ERRNO/EPERM (unconditional) | ✅ Yes | ❌ No | 38 (ENOSYS) |

## Proof: Reordering Changes Which Syscall Is Tracked

To confirm the "first syscall only" behaviour, we reordered the test to call
`swapon` before `clone3`:

```
container_runtime_crio_containers_seccomp_notifier_count_total{...,syscall="swapon"} 1
```

The metric switched from `clone3` to `swapon` — whichever NOTIFY-intercepted
syscall fires first is the only one tracked.

## Root Cause Analysis

### Step 1: Profile Compilation

CRI-O uses `containers/common` to compile the seccomp JSON profile into a
kernel-ready BPF filter. During compilation, `includes`/`excludes` conditions
are evaluated against the container's capabilities:

- **bpf, perf_event_open**: Have `excludes: {caps: ["CAP_SYS_ADMIN"]}` on
  their ERRNO/EPERM rule. Since the container lacks CAP_SYS_ADMIN, the
  excludes check passes and the ERRNO rule is **kept** in the compiled profile.
- **swapon, swapoff, kexec_load, userfaultfd**: Have unconditional ERRNO/EPERM
  rules — always included.
- **clone3**: In the explicit allowlist (SCMP_ACT_ALLOW).

All 7 syscalls have explicit rules in the compiled profile.

### Step 2: Notifier Injection

CRI-O's `injectNotifier` function
([source](https://github.com/cri-o/cri-o/blob/main/internal/config/seccomp/notifier.go))
iterates all explicit rules and replaces `SCMP_ACT_ERRNO` / `SCMP_ACT_KILL*`
with `SCMP_ACT_NOTIFY`. It also replaces `SCMP_ACT_ALLOW` with
`SCMP_ACT_NOTIFY`.

The `defaultAction` (`SCMP_ACT_ERRNO` with `errnoRet: 38`) **cannot** be
replaced — the kernel's seccomp notify mechanism does not support notification
on the default action. CRI-O logs this limitation.

After injection, all 7 syscalls have `SCMP_ACT_NOTIFY` as their action.

### Step 3: The First-Syscall-Only Limitation

The notifier's `handler` function in CRI-O processes incoming seccomp
notifications in a loop, but **breaks after the first syscall**:

```go
// From notifier.go handler()
msgChan <- Notification{ctx, containerID, syscall}
resp := &libseccomp.ScmpNotifResp{
    ID:    req.ID,
    Error: int32(unix.ENOSYS),
    Val:   uint64(0),
    Flags: 0,
}
// ...
if err = libseccomp.NotifRespond(fd, resp); err != nil { ... }
// We only catch the first syscall
break
```

This is by design. The handler:
1. Receives the first NOTIFY event (clone3, since it fires first)
2. Sends it to the metrics channel
3. Responds with ENOSYS
4. **Exits the loop**

After the handler exits, subsequent NOTIFY-intercepted syscalls (swapon,
swapoff, kexec_load, bpf, perf_event_open, userfaultfd) have no listener on
the seccomp notification fd. The kernel's default behaviour when a NOTIFY
action has no listener is to return ENOSYS.

### Why clone3 Fires First

Even though our test program calls clone3 first, that's not the only reason.
The `gcc` compiler and glibc runtime call `clone3` during process startup
(glibc uses it for thread creation). CRI-O's notifier catches this startup
`clone3` call before our test program even begins executing.

### Summary Diagram

```
  Seccomp Profile (after CRI-O injection)
  ┌─────────────────────────────────────────────────┐
  │ defaultAction: SCMP_ACT_ERRNO (errnoRet=38)     │ ← Cannot be NOTIFY
  │                                                   │
  │ Explicit rules (all rewritten to SCMP_ACT_NOTIFY):│
  │   clone3, swapon, swapoff, kexec_load,           │
  │   bpf, perf_event_open, userfaultfd              │
  └──────────────────────┬──────────────────────────┘
                         │
                    First NOTIFY event
                    (clone3 at startup)
                         │
                         ▼
  ┌──────────────────────────────────────────────────┐
  │ CRI-O handler:                                    │
  │  1. Receives clone3 notification                  │
  │  2. Logs it, updates metric                       │
  │  3. Responds with ENOSYS                          │
  │  4. break  ← exits the handler loop               │
  └──────────────────────────────────────────────────┘
                         │
              Handler is now gone.
              No listener on the fd.
                         │
                         ▼
  ┌──────────────────────────────────────────────────┐
  │ Subsequent NOTIFY syscalls (swapon, bpf, etc.):  │
  │  → Kernel has no listener → returns ENOSYS        │
  │  → No metric, no log entry                        │
  └──────────────────────────────────────────────────┘
```

## Implications

1. **The seccomp notifier tracks exactly one syscall per container** — the
   first one that triggers a NOTIFY action. This is intentional (`// We only
   catch the first syscall`).

2. **All explicit rules are rewritten to NOTIFY**, regardless of whether they
   were originally ALLOW or ERRNO. The `includes`/`excludes` conditions are
   evaluated at profile compile time, not by CRI-O's notifier injection.

3. **The defaultAction is never tracked**. Any syscall not covered by an
   explicit rule falls through to `SCMP_ACT_ERRNO` with `errnoRet=38` (ENOSYS)
   and is invisible to the notifier.

4. **All NOTIFY-intercepted syscalls return ENOSYS (errno 38)**, not their
   original errno. The notifier handler hardcodes `unix.ENOSYS` in its
   response, and after the handler exits, the kernel also returns ENOSYS for
   unhandled NOTIFY actions.

5. **The metric is useful for detecting which blocked syscall fires first** in
   a container — typically `clone3` for glibc-based containers, since glibc
   probes for `clone3` support at startup.

## Environment

- Kubernetes: v1.35.1
- CRI-O: 1.35.0
- Runtime: crun 1.25.1
- Kernel: 6.6.87.2-microsoft-standard-WSL2
- Seccomp Profile: RuntimeDefault (`/usr/share/containers/seccomp.json`)
- Date: 2026-03-15
