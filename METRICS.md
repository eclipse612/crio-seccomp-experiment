# Enabling CRI-O Seccomp Notifier Metrics

If the `crio_containers_seccomp_notifier_count_total` metric is not available, you may need to configure CRI-O to enable it.

## Check Current Configuration

```bash
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s
kubectl exec node-shell -- cat /host/etc/crio/crio.conf.d/*.conf
```

## Enable Metrics (if needed)

Create or modify CRI-O configuration:

```bash
# On the minikube node
minikube ssh

# Create config file
sudo tee /etc/crio/crio.conf.d/99-metrics.conf <<EOF
[crio.metrics]
enable_metrics = true
metrics_port = 9090
EOF

# Restart CRI-O
sudo systemctl restart crio
```

## Verify Metrics Endpoint

```bash
# From within the cluster
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | grep crio"
```

## Access Metrics from Outside

Port-forward the metrics endpoint:

```bash
kubectl port-forward -n kube-system pod/node-shell 9090:9090
```

Then access from your local machine:

```bash
curl http://localhost:9090/metrics | grep seccomp
```

## Expected Metrics

```
# HELP crio_containers_seccomp_notifier_count_total Total number of seccomp notifier events
# TYPE crio_containers_seccomp_notifier_count_total counter
crio_containers_seccomp_notifier_count_total{container="test",namespace="default",pod="seccomp-test",syscall="321"} 1
crio_containers_seccomp_notifier_count_total{container="test",namespace="default",pod="seccomp-test",syscall="298"} 1
crio_containers_seccomp_notifier_count_total{container="test",namespace="default",pod="seccomp-test",syscall="323"} 1
```

## Troubleshooting

### Metrics endpoint not responding

Check if CRI-O is listening:
```bash
kubectl exec node-shell -- sh -c "chroot /host ss -tlnp | grep 9090"
```

### No seccomp metrics

1. Verify CRI-O version supports seccomp notifier (1.24+)
2. Check kernel version (5.9+ recommended)
3. Ensure the annotation is correctly set on the pod
4. Verify syscalls are actually being blocked (check application logs)

### Permission denied

The metrics endpoint may require authentication or be bound to localhost only. Check CRI-O configuration for `metrics_socket` settings.
