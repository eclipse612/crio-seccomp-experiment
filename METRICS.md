# Enabling CRI-O Seccomp Notifier Metrics

The `crio_containers_seccomp_notifier_count_total` metric requires specific CRI-O configuration. Follow these steps to enable it.

## Prerequisites

- CRI-O 1.24+ (tested with 1.35.0)
- Linux kernel 5.9+ (for full seccomp notify support)
- Minikube with CRI-O runtime

## Configuration Steps

### Step 1: Enable Metrics

Create metrics configuration file:

```bash
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s

kubectl exec node-shell -- sh -c "cat > /host/etc/crio/crio.conf.d/99-metrics.conf << 'EOF'
[crio.metrics]
enable_metrics = true
metrics_port = 9090
EOF
"
```

### Step 2: Allow Seccomp Notifier Annotation

The `io.kubernetes.cri-o.seccompNotifierAction` annotation must be in the allowed list for your runtime (crun or runc):

```bash
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
```

### Step 3: Restart CRI-O

```bash
kubectl exec node-shell -- sh -c "chroot /host systemctl restart crio"
```

Wait for the cluster to stabilize:
```bash
sleep 15
kubectl get nodes
```

### Step 4: Verify Configuration

Check that CRI-O is listening on the metrics port:

```bash
kubectl delete pod node-shell
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s

kubectl exec node-shell -- sh -c "chroot /host ss -tlnp | grep :9090"
```

Expected output:
```
LISTEN 0      4096       127.0.0.1:9090       0.0.0.0:*    users:(("crio",pid=XXXX,fd=52))
```

Check that metrics are available:
```bash
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | grep container_runtime_crio | head -5"
```

### Step 5: Deploy Test Pod and Check Metrics

```bash
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/seccomp-test --timeout=300s
sleep 5

# Check the metrics
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | grep seccomp_notifier"
```

## Expected Metrics Output

```
# HELP container_runtime_crio_containers_seccomp_notifier_count_total Number of forbidden syscalls by syscall and container name
# TYPE container_runtime_crio_containers_seccomp_notifier_count_total counter
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="bpf"} 1
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="perf_event_open"} 1
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="userfaultfd"} 1
```

**Note**: Syscall names are used in labels, not numbers.

## Verify in CRI-O Logs

Check that the seccomp notifier watcher started:

```bash
kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '5 minutes ago' | grep 'seccomp notifier'"
```

Expected output:
```
Starting seccomp notifier watcher
```

## Troubleshooting

### Metrics endpoint not responding

Check if CRI-O is listening:
```bash
kubectl exec node-shell -- sh -c "chroot /host ss -tlnp | grep 9090"
```

If not, verify the configuration was applied:
```bash
kubectl exec node-shell -- cat /host/etc/crio/crio.conf.d/99-metrics.conf
```

### No seccomp metrics appearing

1. **Check annotation is allowed**: Verify the annotation is in the `allowed_annotations` list for your runtime
   ```bash
   kubectl exec node-shell -- sh -c "chroot /host crio config | grep -A 10 'allowed_annotations'"
   ```

2. **Verify annotation on pod**:
   ```bash
   kubectl get pod seccomp-test -o jsonpath='{.metadata.annotations.io\.kubernetes\.cri-o\.seccompNotifierAction}'
   ```
   Should output: `log`

3. **Check syscalls are blocked**:
   ```bash
   kubectl logs seccomp-test
   ```
   Should show EPERM (errno 1) errors

4. **Check CRI-O logs**:
   ```bash
   kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '5 minutes ago' | grep -i seccomp"
   ```

### Annotation not working

If you see "Allowed annotations are specified for workload" but your annotation isn't listed, the annotation isn't in the allowed list for your runtime. Make sure to add it to the correct runtime (crun or runc) based on your `default_runtime` setting.

## Alternative: Access Metrics from Outside Cluster

Port-forward the metrics endpoint (requires privileged pod):

```bash
kubectl port-forward pod/node-shell 9090:9090
```

Then from your local machine:
```bash
curl http://localhost:9090/metrics | grep seccomp
```

## Configuration Files Summary

After configuration, you should have:

- `/etc/crio/crio.conf.d/99-metrics.conf` - Enables metrics
- `/etc/crio/crio.conf.d/10-crio.conf` - Allows seccomp notifier annotation
- `/etc/crio/crio.conf.d/02-crio.conf` - Base CRI-O config (pre-existing)
