# RUNBOOK: kubectl "No Route to Host"

## 📋 Incident Overview

**Trigger**: `kubectl` command fails with "no route to host" error
**Severity**: HIGH - Cannot connect to Kubernetes cluster
**Expected Resolution Time**: 5-10 minutes

## 🚨 Symptoms

```bash
$ kubectl get nodes
Unable to connect to the server: dial tcp 192.168.49.2:8443: connect: no route to host
```

or

```bash
$ kubectl cluster-info
Unable to connect to the server: dial tcp 192.168.49.2:8443: i/o timeout
```

Indicators:
- kubectl commands fail with network errors
- Cannot reach cluster API server
- Minikube may be stopped or IP changed

## 🔍 Step 1: Identify the Problem

### Check Minikube status
```bash
minikube status

# Expected output when running:
# minikube
# type: Control Plane
# host: Running
# kubelet: Running
# apiserver: Running
# kubeconfig: Configured
```

### Check current cluster configuration
```bash
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
# Shows: https://192.168.49.2:8443

minikube ip
# Shows: 192.168.49.2 (or different IP)
```

**If IPs don't match → IP CHANGED**

## 🛠️ Step 2: Common Causes & Solutions

### Cause A: Minikube Not Running

**Diagnosis**:
```bash
minikube status
# Shows: Stopped or Host: Stopped
```

**Solution**:
```bash
# Start Minikube
minikube start

# Wait for cluster to be ready
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Verify
kubectl get nodes
# Should show: Ready
```

### Cause B: Minikube IP Address Changed

**Diagnosis**:
```bash
# Get kubeconfig server IP
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
# Example: https://192.168.49.2:8443

# Get actual Minikube IP
minikube ip
# Example: 192.168.49.3 (DIFFERENT!)
```

**Solution**:
```bash
# Update kubeconfig with correct IP
minikube update-context

# Verify update
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
# Should match: minikube ip

# Test connection
kubectl get nodes
```

### Cause C: VPN Interference

**Diagnosis**:
```bash
# Test connectivity to Minikube IP
MINIKUBE_IP=$(minikube ip)
ping -c 3 $MINIKUBE_IP

# If ping fails but Minikube is running → VPN ISSUE
```

**Solution**:
```bash
# Option 1: Disable VPN temporarily
# (Disconnect VPN and retry)

# Option 2: Restart Minikube network
minikube stop
minikube start

# Option 3: Recreate cluster (last resort)
minikube delete
minikube start --cpus=4 --memory=8192
```

### Cause D: Minikube Paused

**Diagnosis**:
```bash
minikube status
# Shows: Host: Running, kubelet: Stopped
```

**Solution**:
```bash
# Unpause Minikube
minikube unpause

# Verify
minikube status
kubectl get nodes
```

### Cause E: Network Configuration Changed

**Diagnosis**:
```bash
# Check if Minikube IP is reachable
MINIKUBE_IP=$(minikube ip)
ping -c 3 $MINIKUBE_IP

# Check route
ip route | grep $(minikube ip)
```

**Solution**:
```bash
# Restart network and Minikube
minikube stop
minikube start

# If still fails, recreate
minikube delete
minikube start --cpus=4 --memory=8192
```

### Cause F: Firewall Blocking Connection

**Diagnosis**:
```bash
# Test connection to API server port
MINIKUBE_IP=$(minikube ip)
nc -zv $MINIKUBE_IP 8443

# If fails → FIREWALL ISSUE
```

**Solution**:
```bash
# Check firewall rules (Linux)
sudo iptables -L -n | grep 8443

# Temporarily disable firewall for testing
sudo ufw disable  # Ubuntu
sudo systemctl stop firewalld  # CentOS/RHEL

# Test kubectl again
kubectl get nodes

# Re-enable firewall and add exception if needed
```

## ✅ Step 3: Verification

### 1. Check Minikube is running
```bash
minikube status
# All components should be: Running
```

### 2. Verify IP connectivity
```bash
MINIKUBE_IP=$(minikube ip)
ping -c 3 $MINIKUBE_IP
# Should get replies
```

### 3. Check kubeconfig is correct
```bash
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
# Should contain correct IP from: minikube ip
```

### 4. Test kubectl commands
```bash
kubectl get nodes
# Should show: minikube   Ready

kubectl cluster-info
# Should show cluster info

kubectl get pods -A
# Should list all pods
```

### 5. Test application access
```bash
# If you had deployments running
kubectl -n october get pods
kubectl -n october get svc

# Test Ingress (if configured)
MINIKUBE_IP=$(minikube ip)
curl -f http://api.$MINIKUBE_IP.nip.io/healthz
```

## 🔧 Step 4: Advanced Diagnostics

### Check Minikube logs
```bash
minikube logs --length=50

# Look for network errors
minikube logs | grep -i "network\|connection\|error"
```

### Check Docker/Podman driver
```bash
# If using Docker driver
docker ps | grep minikube

# If using Podman
podman ps | grep minikube

# Restart container runtime if needed
sudo systemctl restart docker
```

### SSH into Minikube
```bash
# SSH to debug from inside
minikube ssh

# Inside Minikube VM
ping 8.8.8.8  # Test internet
netstat -tuln | grep 8443  # Check API server listening
exit
```

## 📊 Post-Incident

### Document the issue
- What caused the "no route to host" error?
- Which solution worked?
- How long was cluster unreachable?

### Preventive measures
- Add health check script to monitor Minikube status
- Document VPN conflicts
- Set up cluster restart automation

### Health check script
```bash
#!/bin/bash
# minikube-health.sh

if ! minikube status &>/dev/null; then
    echo "⚠️  Minikube not running, starting..."
    minikube start
fi

if ! kubectl get nodes &>/dev/null; then
    echo "⚠️  kubectl cannot connect, updating context..."
    minikube update-context
fi

echo "✅ Minikube healthy"
```

## 📚 Related Documentation

- [Troubleshooting Guide](../TROUBLESHOOTING.md)
- [Deployment Guide - Kubernetes](../DEPLOYMENT_GUIDE.md#kubernetes-deployment)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/start/)

## 🔑 Quick Reference

### Fastest diagnosis path
```bash
# 1. Check if Minikube is running
minikube status

# 2. If stopped, start it
minikube start

# 3. If running but kubectl fails, check IPs
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
minikube ip

# 4. If IPs differ, update context
minikube update-context

# 5. Test connection
kubectl get nodes
```

### Common fixes
```bash
# Start Minikube
minikube start

# Update kubeconfig
minikube update-context

# Restart network
minikube stop && minikube start

# Full recreate (last resort)
minikube delete && minikube start --cpus=4 --memory=8192
```

### Verification
```bash
minikube status                    # All: Running
ping -c 3 $(minikube ip)          # Reachable
kubectl get nodes                  # Ready
kubectl cluster-info               # Shows cluster
```

---

**Last Updated**: 2025-10-19
**Version**: 2.0 (Updated to standard format)
**Tested On**: Minikube 1.32, Kubernetes 1.28
