#!/bin/bash
# quick-diag.sh - Comprehensive diagnostics for K8s-Helm-CICD-Portfolio
# Usage: ./scripts/quick-diag.sh > diagnostics.txt

set -e

echo "========================================="
echo "K8s-Helm-CICD Portfolio Diagnostics"
echo "Generated: $(date)"
echo "========================================="
echo ""

echo "=== 1. System Information ==="
echo "Docker:"
docker --version 2>&1 || echo "  ✗ Docker not found"
echo ""
echo "Kubernetes (kubectl):"
kubectl version --client --short 2>&1 || echo "  ✗ kubectl not found"
echo ""
echo "Helm:"
helm version --short 2>&1 || echo "  ✗ Helm not found"
echo ""
echo "Minikube:"
minikube version 2>&1 || echo "  ✗ Minikube not found"
echo ""

echo "=== 2. Minikube Status ==="
minikube status 2>&1 || echo "  ✗ Minikube not running"
echo ""

echo "=== 3. Cluster Information ==="
kubectl cluster-info 2>&1 || echo "  ✗ Cannot connect to cluster"
echo ""

echo "=== 4. Node Status ==="
kubectl get nodes -o wide 2>&1 || echo "  ✗ Cannot get nodes"
echo ""

echo "=== 5. Namespace Resources (october) ==="
kubectl -n october get all 2>&1 || echo "  ✗ Namespace 'october' not found or no resources"
echo ""

echo "=== 6. Pod Details ==="
kubectl -n october get pods -o wide 2>&1 || echo "  ✗ Cannot get pods"
echo ""

echo "=== 7. Pod Status & Restarts ==="
kubectl -n october get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,READY:.status.containerStatuses[0].ready 2>&1 || echo "  ✗ Cannot get pod details"
echo ""

echo "=== 8. Service Endpoints ==="
kubectl -n october get endpoints 2>&1 || echo "  ✗ Cannot get endpoints"
echo ""

echo "=== 9. Ingress Configuration ==="
kubectl -n october get ingress 2>&1 || echo "  ✗ No ingress found"
echo ""

echo "=== 10. HPA Status ==="
kubectl -n october get hpa 2>&1 || echo "  ✗ No HPA found"
echo ""

echo "=== 11. ConfigMaps & Secrets ==="
echo "ConfigMaps:"
kubectl -n october get configmap 2>&1 || echo "  ✗ No ConfigMaps found"
echo ""
echo "Secrets:"
kubectl -n october get secret 2>&1 || echo "  ✗ No Secrets found"
echo ""

echo "=== 12. PersistentVolumeClaims ==="
kubectl -n october get pvc 2>&1 || echo "  ✗ No PVCs found"
echo ""

echo "=== 13. Recent Events (last 20) ==="
kubectl -n october get events --sort-by='.lastTimestamp' 2>&1 | tail -20 || echo "  ✗ Cannot get events"
echo ""

echo "=== 14. Helm Releases ==="
helm list -n october 2>&1 || echo "  ✗ No Helm releases found"
echo ""

echo "=== 15. Helm Release History ==="
helm history app -n october 2>&1 || echo "  ✗ No history for release 'app'"
echo ""

echo "=== 16. Resource Usage (if metrics-server enabled) ==="
echo "Node metrics:"
kubectl top nodes 2>&1 || echo "  ✗ Metrics not available (enable with: minikube addons enable metrics-server)"
echo ""
echo "Pod metrics:"
kubectl -n october top pods 2>&1 || echo "  ✗ Metrics not available"
echo ""

echo "=== 17. API Pod Logs (last 50 lines) ==="
API_POD=$(kubectl -n october get pod -l app=api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$API_POD" ]; then
    echo "Pod: $API_POD"
    kubectl -n october logs "$API_POD" --tail=50 2>&1 || echo "  ✗ Cannot get logs"
else
    echo "  ✗ No API pod found"
fi
echo ""

echo "=== 18. Worker Pod Logs (last 50 lines) ==="
WORKER_POD=$(kubectl -n october get pod -l app=worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$WORKER_POD" ]; then
    echo "Pod: $WORKER_POD"
    kubectl -n october logs "$WORKER_POD" --tail=50 2>&1 || echo "  ✗ Cannot get logs"
else
    echo "  ✗ No Worker pod found"
fi
echo ""

echo "=== 19. Redis Pod Logs (last 30 lines) ==="
REDIS_POD=$(kubectl -n october get pod -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$REDIS_POD" ]; then
    echo "Pod: $REDIS_POD"
    kubectl -n october logs "$REDIS_POD" --tail=30 2>&1 || echo "  ✗ Cannot get logs"
else
    echo "  ✗ No Redis pod found"
fi
echo ""

echo "=== 20. Health Check Test ==="
MINIKUBE_IP=$(minikube ip 2>/dev/null)
if [ -n "$MINIKUBE_IP" ]; then
    echo "Minikube IP: $MINIKUBE_IP"
    echo "Testing: http://api.$MINIKUBE_IP.nip.io/healthz"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://api.$MINIKUBE_IP.nip.io/healthz" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "  ✓ Health check PASSED (HTTP $HTTP_CODE)"
        curl -s "http://api.$MINIKUBE_IP.nip.io/healthz" 2>&1
    else
        echo "  ✗ Health check FAILED (HTTP $HTTP_CODE)"
    fi
else
    echo "  ✗ Minikube not running, cannot test health check"
fi
echo ""

echo "=== 21. Port-Forward Health Check (fallback) ==="
echo "Testing via port-forward..."
kubectl -n october port-forward svc/api 8888:80 >/dev/null 2>&1 &
PF_PID=$!
sleep 2

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8888/healthz" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✓ Port-forward health check PASSED (HTTP $HTTP_CODE)"
    curl -s "http://localhost:8888/healthz" 2>&1
else
    echo "  ✗ Port-forward health check FAILED (HTTP $HTTP_CODE)"
fi

kill $PF_PID 2>/dev/null || true
echo ""

echo "=== 22. Ingress Controller Status ==="
kubectl -n ingress-nginx get pods 2>&1 || echo "  ✗ Ingress controller not found (enable with: minikube addons enable ingress)"
echo ""

echo "========================================="
echo "Diagnostics Complete"
echo "========================================="
echo ""
echo "SUMMARY:"
echo "- Generated: $(date)"
echo "- Namespace: october"
MINIKUBE_IP=$(minikube ip 2>/dev/null)
if [ -n "$MINIKUBE_IP" ]; then
    echo "- Minikube IP: $MINIKUBE_IP"
    echo "- Ingress URL: http://api.$MINIKUBE_IP.nip.io"
fi
echo ""
echo "Next steps:"
echo "  - Review errors marked with ✗"
echo "  - Check 'Recent Events' for issues"
echo "  - View pod logs for detailed errors"
echo "  - See troubleshooting guide: docs/TROUBLESHOOTING.md"
echo ""
