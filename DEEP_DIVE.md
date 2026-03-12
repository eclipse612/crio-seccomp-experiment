# Seccomp Notifier Deep Dive

## What is Seccomp?

Seccomp (Secure Computing Mode) is a Linux kernel feature that restricts the system calls a process can make. It's a key security mechanism for containerized workloads.

## CRI-O Seccomp Notifier

The seccomp notifier is a feature that allows CRI-O to be notified when a container attempts to make a blocked syscall. This enables:

1. **Logging**: Record which syscalls are being blocked
2. **Metrics**: Track blocked syscall counts via Prometheus metrics
3. **Debugging**: Understand why applications fail in restricted environments

## How It Works

```
Application → Syscall → Seccomp Filter → Blocked → Notifier → CRI-O → Logs/Metrics
```

When a syscall is blocked:
1. The seccomp filter intercepts it
2. Instead of just returning EPERM, it notifies the supervisor (CRI-O)
3. CRI-O logs the event and updates metrics
4. The application receives EPERM

## Annotation Details

```yaml
metadata:
  annotations:
    io.kubernetes.cri-o.seccompNotifierAction: "log"
```

This annotation tells CRI-O to enable seccomp notification for the pod. The value "log" means blocked syscalls will be logged.

## RuntimeDefault Profile

The RuntimeDefault seccomp profile is maintained by the container runtime (CRI-O). It typically blocks:

- **Process manipulation**: `clone3`, `unshare`, `setns`
- **Kernel modules**: `init_module`, `finit_module`, `delete_module`
- **System configuration**: `reboot`, `swapon`, `swapoff`
- **Performance/debugging**: `perf_event_open`, `ptrace`
- **BPF operations**: `bpf`
- **Memory management**: `userfaultfd`, `mbind`, `move_pages`
- **Privileged operations**: `ioperm`, `iopl`, `kexec_load`

## Syscalls in This Experiment

### clone3() - Syscall 435
Modern replacement for `clone()`. Blocked because it can be used to create new namespaces and escape container isolation.

**Why blocked**: Container escape risk, namespace manipulation

### bpf() - Syscall 321
Berkeley Packet Filter system calls. Allows loading programs into the kernel.

**Why blocked**: Kernel manipulation, privilege escalation risk

### perf_event_open() - Syscall 298
Opens performance monitoring events. Can leak timing information.

**Why blocked**: Information disclosure, side-channel attacks

### userfaultfd() - Syscall 323
User-space page fault handling. Can be exploited for race conditions.

**Why blocked**: Known exploitation vector in container escapes

## Expected Errors

- **EPERM (errno 1)**: Operation not permitted - syscall blocked by seccomp
- **ENOSYS (errno 38)**: Function not implemented - syscall not supported by kernel

## Metrics

CRI-O exposes Prometheus metrics at port 9090 (default):

```
crio_containers_seccomp_notifier_count_total{syscall="321",container="..."} 1
crio_containers_seccomp_notifier_count_total{syscall="298",container="..."} 1
```

Each blocked syscall increments the counter for that syscall number.

## Limitations

1. **Configuration Required**: Seccomp notifier may need explicit CRI-O configuration
2. **Kernel Support**: Requires Linux kernel 5.9+ for full seccomp notify support
3. **Performance**: Notification has overhead compared to simple blocking
4. **Runtime Specific**: This is a CRI-O feature, not available in containerd/Docker

## Security Considerations

- Seccomp is defense-in-depth, not a complete security solution
- Always combine with other security measures (AppArmor, SELinux, capabilities)
- Custom seccomp profiles should be carefully audited
- Blocked syscalls indicate potential security issues or misconfigurations

## Further Reading

- [Seccomp BPF](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)
- [CRI-O Configuration](https://github.com/cri-o/cri-o/blob/main/docs/crio.conf.5.md)
- [Kubernetes Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
