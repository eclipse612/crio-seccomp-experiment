# Quick Reference

## One-Command Run

```bash
./run-experiment.sh
```

## Manual Steps

### 1. Deploy Test Pod
```bash
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/seccomp-test --timeout=300s
```

### 2. View Results
```bash
kubectl exec seccomp-test -- cat /proc/1/fd/1
```

### 3. Check Logs
```bash
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s
kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '10 minutes ago' | grep -i seccomp"
```

### 4. Cleanup
```bash
kubectl delete pod seccomp-test node-shell
```

## Key Files

- **pod.yaml** - Main test pod with seccomp configuration
- **seccomp-test.c** - Test program source code
- **node-shell.yaml** - Privileged pod for node access
- **run-experiment.sh** - Automated experiment runner

## Expected Output

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
```

**errno 1 = EPERM** means the syscall was blocked by seccomp.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Pod stuck in ContainerCreating | `kubectl describe pod seccomp-test` |
| No output visible | `kubectl logs seccomp-test` |
| Image pull errors | Pod uses public `gcc:12-bookworm` image |
| Metrics not available | See METRICS.md |

## Architecture

```
┌─────────────────────────────────────────┐
│           Kubernetes Pod                │
│  ┌───────────────────────────────────┐  │
│  │  Container (gcc:12-bookworm)      │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │  seccomp-test program       │  │  │
│  │  │  - Calls clone3()           │  │  │
│  │  │  - Calls bpf()              │  │  │
│  │  │  - Calls perf_event_open()  │  │  │
│  │  │  - Calls userfaultfd()      │  │  │
│  │  └─────────────────────────────┘  │  │
│  │              ↓                     │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │  Seccomp Filter             │  │  │
│  │  │  (RuntimeDefault)           │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
│                 ↓                        │
│  Annotation: seccompNotifierAction=log  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│            CRI-O Runtime                │
│  - Receives seccomp notifications       │
│  - Logs blocked syscalls                │
│  - Updates metrics                      │
└─────────────────────────────────────────┘
```

## Syscall Numbers (x86_64)

- 298: perf_event_open
- 321: bpf
- 323: userfaultfd
- 435: clone3

## Links

- [Full Documentation](README.md)
- [Deep Dive](DEEP_DIVE.md)
- [Metrics Setup](METRICS.md)
