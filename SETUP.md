# Setup Guide - From Scratch

This guide covers setting up a Kubernetes cluster with CRI-O and enabling the seccomp notifier feature.

## Table of Contents

1. [Minikube Setup](#minikube-setup)
2. [Generic Kubernetes Cluster Setup](#generic-kubernetes-cluster-setup)
3. [CRI-O Seccomp Notifier Configuration](#crio-seccomp-notifier-configuration)
4. [Verification](#verification)

---

## Minikube Setup

### Prerequisites

- Linux system (tested on WSL2)
- Docker installed and user added to docker group
- 2+ CPUs, 2GB+ RAM

### Install Minikube

```bash
# Download and install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Verify installation
minikube version

# Add user to docker group (if not already done)
sudo usermod -aG docker $USER
newgrp docker
```

### Start Minikube with CRI-O

```bash
# Start minikube with CRI-O runtime
minikube start --container-runtime=cri-o

# Verify cluster is running
kubectl get nodes

# Check CRI-O is being used
kubectl get nodes -o wide
# Look for "cri-o" in the CONTAINER-RUNTIME column
```

### Verify CRI-O Version

```bash
# Access the minikube node
minikube ssh

# Check CRI-O version
sudo crio --version

# Exit minikube node
exit
```

Expected output:
```
crio version 1.35.0
...
SeccompEnabled:   true
```

---

## Alternative: kind with CRI-O

**Note**: kind with CRI-O requires building custom node images and is more complex than minikube. For this experiment, minikube is recommended.

If you want to use kind with CRI-O, follow the [official CRI-O in kind tutorial](https://github.com/cri-o/cri-o/blob/main/tutorials/crio-in-kind.md). Key points:

- Requires building a custom kind node image with CRI-O pre-installed
- More complex setup and troubleshooting
- Useful for CI/CD pipelines where kind is already in use

For most users, **minikube is the simpler choice** for experimenting with CRI-O's seccomp notifier.

---

## Generic Kubernetes Cluster Setup

For non-minikube clusters, ensure CRI-O is installed and configured as the container runtime.

### Install CRI-O (Ubuntu/Debian)

```bash
# Set up repositories
export OS=xUbuntu_22.04
export VERSION=1.35

echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list

# Add GPG keys
mkdir -p /usr/share/keyrings
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/Release.key | sudo gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

# Install CRI-O
sudo apt-get update
sudo apt-get install -y cri-o cri-o-runc

# Start and enable CRI-O
sudo systemctl daemon-reload
sudo systemctl enable crio
sudo systemctl start crio
```

### Configure Kubernetes to Use CRI-O

Edit `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` or create it:

```bash
sudo mkdir -p /etc/systemd/system/kubelet.service.d
sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --container-runtime-endpoint=unix:///var/run/crio/crio.sock"
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

## CRI-O Seccomp Notifier Configuration

This configuration is required for both minikube and generic Kubernetes clusters.

### Step 1: Access the Node

**For Minikube:**
```bash
minikube ssh
```

**For Generic Cluster:**
```bash
# SSH to the node or use a privileged pod
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s
kubectl exec -it node-shell -- sh
chroot /host
```

### Step 2: Enable CRI-O Metrics

Create the metrics configuration file:

```bash
sudo tee /etc/crio/crio.conf.d/99-metrics.conf <<EOF
[crio.metrics]
enable_metrics = true
metrics_port = 9090
EOF
```

**Configuration Details:**
- `enable_metrics = true` - Enables Prometheus metrics endpoint
- `metrics_port = 9090` - Port for metrics (default: 9090)

### Step 3: Configure Seccomp Notifier Annotation

The seccomp notifier annotation must be explicitly allowed for your container runtime.

**Check your default runtime:**
```bash
sudo crio config | grep default_runtime
```

**For crun runtime (most common):**

```bash
sudo tee /etc/crio/crio.conf.d/10-crio.conf <<EOF
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
EOF
```

**For runc runtime:**

```bash
sudo tee /etc/crio/crio.conf.d/10-crio.conf <<EOF
[crio.image]
signature_policy = "/etc/crio/policy.json"

[crio.runtime]
default_runtime = "runc"

[crio.runtime.runtimes.runc]
runtime_path = "/usr/bin/runc"
runtime_root = "/run/runc"
monitor_path = "/usr/libexec/crio/conmon"
allowed_annotations = [
    "io.kubernetes.cri-o.seccompNotifierAction",
]
EOF
```

**Critical**: The `io.kubernetes.cri-o.seccompNotifierAction` annotation MUST be in the `allowed_annotations` list for your active runtime, otherwise it will be silently ignored.

### Step 4: Verify Configuration Files

```bash
# List all CRI-O config files
ls -la /etc/crio/crio.conf.d/

# View the complete merged configuration
sudo crio config | grep -A 20 "crio.metrics"
sudo crio config | grep -A 30 "allowed_annotations"
```

### Step 5: Restart CRI-O

**For Minikube (from host):**
```bash
# Exit minikube ssh if inside
exit

# Restart via kubectl
kubectl apply -f node-shell.yaml
kubectl wait --for=condition=Ready pod/node-shell --timeout=60s
kubectl exec node-shell -- sh -c "chroot /host systemctl restart crio"

# Wait for cluster to stabilize
sleep 15
kubectl get nodes
```

**For Generic Cluster:**
```bash
sudo systemctl restart crio

# Check status
sudo systemctl status crio

# Verify it's running
sudo ss -tlnp | grep :9090
```

**Warning**: Restarting CRI-O will disrupt all running pods on the node. In production, drain the node first:
```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# Restart CRI-O
kubectl uncordon <node-name>
```

---

## Verification

### 1. Check CRI-O is Running

```bash
# For minikube
kubectl exec node-shell -- sh -c "chroot /host systemctl status crio | head -5"

# For generic cluster
sudo systemctl status crio
```

### 2. Verify Metrics Endpoint

```bash
# For minikube
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | head -10"

# For generic cluster
curl -s http://127.0.0.1:9090/metrics | head -10
```

Expected output should show CRI-O metrics:
```
# HELP container_runtime_crio_containers_events_dropped_total Amount of container events dropped
# TYPE container_runtime_crio_containers_events_dropped_total counter
...
```

### 3. Verify Seccomp Notifier Configuration

```bash
# Check that seccomp notifier watcher starts
kubectl exec node-shell -- sh -c "chroot /host journalctl -u crio --since '1 minute ago' | grep 'seccomp notifier'"
```

Expected output:
```
Starting seccomp notifier watcher
```

### 4. Check Allowed Annotations

```bash
# For minikube
kubectl exec node-shell -- sh -c "chroot /host crio config | grep -A 10 'allowed_annotations'"

# For generic cluster
sudo crio config | grep -A 10 'allowed_annotations'
```

Verify `io.kubernetes.cri-o.seccompNotifierAction` is in the list for your runtime.

### 5. Test with Sample Pod

```bash
# Deploy test pod
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/seccomp-test --timeout=300s

# Wait for syscalls to execute
sleep 5

# Check metrics
kubectl exec node-shell -- sh -c "chroot /host curl -s http://127.0.0.1:9090/metrics | grep seccomp_notifier"
```

Expected output:
```
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="bpf"} 1
container_runtime_crio_containers_seccomp_notifier_count_total{name="k8s_test_seccomp-test_default_...",syscall="clone3"} 1
```

---

## Troubleshooting

### CRI-O Won't Start After Configuration

Check configuration syntax:
```bash
sudo crio config 2>&1 | grep -i error
```

View CRI-O logs:
```bash
sudo journalctl -u crio -n 50 --no-pager
```

### Metrics Endpoint Not Accessible

Check if CRI-O is listening:
```bash
sudo ss -tlnp | grep :9090
```

Check firewall rules:
```bash
sudo iptables -L -n | grep 9090
```

### Annotation Not Working

1. Verify annotation is in allowed list:
```bash
sudo crio config | grep -B 5 -A 10 "io.kubernetes.cri-o.seccompNotifierAction"
```

2. Check pod has annotation:
```bash
kubectl get pod seccomp-test -o jsonpath='{.metadata.annotations}'
```

3. Check CRI-O logs for annotation warnings:
```bash
sudo journalctl -u crio --since "5 minutes ago" | grep -i annotation
```

### No Metrics Appearing

1. Verify syscalls are actually blocked:
```bash
kubectl logs seccomp-test
```
Should show EPERM (errno 1) errors.

2. Check seccomp notifier watcher is running:
```bash
sudo journalctl -u crio | grep "seccomp notifier"
```

3. Verify seccomp is enabled in CRI-O:
```bash
sudo crio --version | grep SeccompEnabled
```
Should show: `SeccompEnabled: true`

---

## Configuration File Locations

- **Main config**: `/etc/crio/crio.conf` (usually not edited directly)
- **Drop-in configs**: `/etc/crio/crio.conf.d/*.conf`
- **Metrics config**: `/etc/crio/crio.conf.d/99-metrics.conf`
- **Runtime config**: `/etc/crio/crio.conf.d/10-crio.conf`
- **Seccomp profile**: `/usr/share/containers/seccomp.json` (RuntimeDefault)

## Important Notes

1. **Kernel Requirements**: Seccomp notify requires Linux kernel 5.9+
2. **CRI-O Version**: Seccomp notifier feature requires CRI-O 1.24+
3. **Runtime Compatibility**: Works with both crun and runc
4. **Performance**: Seccomp notifier adds overhead; use for debugging/auditing only
5. **Persistence**: Configuration survives CRI-O restarts but not node reboots (unless using persistent storage)

## Next Steps

After completing this setup, proceed to:
1. Deploy test pods with seccomp annotations
2. Monitor metrics via Prometheus
3. Analyze blocked syscalls
4. Create custom seccomp profiles if needed

See `WORKING_SETUP.md` for the complete experiment workflow.
