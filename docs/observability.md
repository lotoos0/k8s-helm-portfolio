# Observability Guide

Complete guide to monitoring, metrics, dashboards, and alerting for the October DevOps platform.

## Table of Contents

- [Overview](#overview)
- [Setup (kube-prometheus-stack)](#setup-kube-prometheus-stack)
- [Accessing Dashboards](#accessing-dashboards)
- [Metrics Available](#metrics-available)
- [Grafana Dashboards](#grafana-dashboards)
- [Alerts (PrometheusRule)](#alerts-prometheusrule)
- [Alerting Runbook](#alerting-runbook)
- [Troubleshooting](#troubleshooting)

---

## Overview

The observability stack includes:

- **Prometheus** - Metrics collection and storage
- **Grafana** - Visualization and dashboards
- **Alertmanager** - Alert routing and notifications
- **ServiceMonitor** - Automatic metrics scraping (Prometheus Operator)
- **PrometheusRule** - Alert definitions

**Key Metrics**:
- `http_requests_total` - Request counter with labels (method, path, status)
- `http_request_duration_seconds` - Request latency histogram

---

## Setup (kube-prometheus-stack)

### Install Prometheus, Grafana, Alertmanager

```bash
# Install the full stack
make mon-install

# Check status
make mon-status

# Verify pods are running
kubectl -n monitoring get pods
```

**What gets installed**:
- Prometheus Operator
- Prometheus (metrics storage)
- Grafana (dashboards)
- Alertmanager (alert routing)
- Node Exporter (node metrics)
- Kube State Metrics (K8s object metrics)

---

## Accessing Dashboards

### Grafana

```bash
# Port-forward to http://localhost:3000
make mon-pf-grafana

# Get admin password
make mon-grafana-pass
```

**Default credentials**:
- Username: `admin`
- Password: Use `make mon-grafana-pass`

### Prometheus

```bash
# Port-forward to http://localhost:9090
make mon-pf-prom
```

**Useful Prometheus URLs**:
- Targets: http://localhost:9090/targets
- Alerts: http://localhost:9090/alerts
- Graph: http://localhost:9090/graph

### Alertmanager

```bash
# Port-forward to http://localhost:9093
make mon-pf-am
```

---

## Metrics Available

The API exposes Prometheus metrics at `/metrics` endpoint.

### Application Metrics

**1. Request Counter**:
```
http_requests_total{method="GET", path="/healthz", status="200"} 42
```

Labels:
- `method` - HTTP method (GET, POST, etc.)
- `path` - Request path
- `status` - HTTP status code (200, 404, 500, etc.)

**2. Request Duration Histogram**:
```
http_request_duration_seconds_bucket{method="GET", path="/healthz", status="200", le="0.005"} 38
http_request_duration_seconds_bucket{method="GET", path="/healthz", status="200", le="0.01"} 42
...
http_request_duration_seconds_sum{method="GET", path="/healthz", status="200"} 0.082
http_request_duration_seconds_count{method="GET", path="/healthz", status="200"} 42
```

Buckets (in seconds): `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5`

### ServiceMonitor Configuration

Metrics are automatically scraped by Prometheus using ServiceMonitor (configured in `values.yaml`):

```yaml
serviceMonitor:
  enabled: true
  interval: 15s  # Scrape every 15 seconds
  additionalLabels:
    release: mon  # Required for Prometheus Operator selector
```

**Verify scraping**:
```bash
# Check ServiceMonitor exists
kubectl -n october get servicemonitor

# Check Prometheus targets (should show API as UP)
# Open: http://localhost:9090/targets (after `make mon-pf-prom`)
```

---

## Grafana Dashboards

### Creating a Custom Dashboard

1. Open Grafana: http://localhost:3000
2. Click **+** → **Dashboard** → **Add visualization**
3. Select **Prometheus** as data source
4. Add PromQL queries (see below)
5. Save dashboard

### Recommended Panels

#### 1. RPS (Requests Per Second) by Status

**Query**:
```promql
sum by (status) (rate(http_requests_total{namespace="october"}[$__rate_interval]))
```

**Panel Settings**:
- Visualization: Time series (line graph)
- Legend: `{{status}}`
- Y-axis: requests/sec

**What it shows**: Request rate broken down by HTTP status code (200, 404, 500, etc.)

#### 2. Latency p95 (95th Percentile)

**Query**:
```promql
1000 * histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{namespace="october"}[$__rate_interval]))
)
```

**Panel Settings**:
- Visualization: Time series
- Y-axis unit: milliseconds (ms)
- Threshold: Add warning at 500ms, critical at 1000ms

**What it shows**: 95% of requests complete within this latency

#### 3. 5xx Error Rate

**Query**:
```promql
sum(rate(http_requests_total{namespace="october", status=~"5.."}[$__rate_interval]))
```

**Panel Settings**:
- Visualization: Time series
- Y-axis: errors/sec
- Alert threshold: > 0 errors

**What it shows**: Server error rate (5xx responses)

#### 4. Request Rate by Path

**Query**:
```promql
sum by (path) (rate(http_requests_total{namespace="october"}[$__rate_interval]))
```

**What it shows**: Which endpoints are getting the most traffic

#### 5. Pod CPU Usage

**Query**:
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="october", pod=~"api-.*"}[5m])) by (pod)
```

**What it shows**: CPU usage per API pod

#### 6. Pod Memory Usage

**Query**:
```promql
sum(container_memory_working_set_bytes{namespace="october", pod=~"api-.*"}) by (pod) / 1024 / 1024
```

**Panel Settings**:
- Y-axis unit: MiB

---

## Alerts (PrometheusRule)

### Configuration

Alerts are configured in `deploy/helm/api/templates/prometheusrule.yaml` and enabled via `values.yaml`:

```yaml
alerts:
  enabled: true
  release: "mon"  # Must match Prometheus Operator release name
```

### Active Alerts

#### 1. CrashLoopBackOffPods

**Trigger**: Pod in CrashLoopBackOff state for more than 5 minutes

**Severity**: `warning`

**Query**:
```promql
kube_pod_container_status_waiting_reason{
  namespace="october",
  reason="CrashLoopBackOff"
} > 0
```

**Annotations**:
- Summary: `Pod {{ $labels.pod }} is in CrashLoopBackOff`
- Description: Pod has been crash-looping for >5m

**Runbook**: [CrashLoopBackOff Runbook](runbooks/crashloopbackoff.md)

#### 2. HighCPUApi

**Trigger**: API pod CPU usage > 80% of requests for 5 minutes

**Severity**: `warning`

**Query**:
```promql
sum(rate(container_cpu_usage_seconds_total{
  namespace="october",
  pod=~"api-.*"
}[5m])) by (pod)
/
sum(kube_pod_container_resource_requests{
  namespace="october",
  pod=~"api-.*",
  resource="cpu"
}) by (pod) > 0.8
```

**Annotations**:
- Summary: `API pod {{ $labels.pod }} high CPU`
- Description: CPU usage >80% of requests for 5m

**Action**: Check if HPA is scaling, consider increasing CPU requests/limits

### Viewing Alerts

**Prometheus UI**:
```bash
make mon-pf-prom
# Open: http://localhost:9090/alerts
```

**Alert States**:
- **Inactive** - Condition not met
- **Pending** - Condition met, but not for `for:` duration yet
- **Firing** - Condition met for required duration, alert sent

**Alertmanager UI**:
```bash
make mon-pf-am
# Open: http://localhost:9093
```

---

## Alerting Runbook

### Stack Overview

- **Stack**: kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
- **Alert Rules**: `deploy/helm/api/templates/prometheusrule.yaml`
- **Alertmanager Config**: `deploy/monitoring/values-alerting.yaml`
- **Slack Webhook**: Stored in Secret `am-slack` (namespace `monitoring`)

### Testing Alerts

#### Test 1: CrashLoopBackOff Alert

```bash
# Trigger crash by setting FAIL_HEALTHZ=true
make mon-fire-crash

# Watch pod status
kubectl -n october get pods -w

# Expected timeline:
# - Pod starts crashing immediately
# - After ~2-3 min: CrashLoopBackOff status
# - After ~5-7 min: Alert fires (5m for: duration)

# Check alert in Prometheus
make mon-pf-prom
# Open: http://localhost:9090/alerts

# Heal the crash
make mon-heal-crash
```

#### Test 2: High CPU Alert

```bash
# Generate sustained CPU load
make mon-fire-cpu

# Watch CPU usage
kubectl top pods -n october

# Expected timeline:
# - CPU usage spikes immediately
# - After ~5-6 min: HighCPUApi alert fires

# Stop load test (Ctrl+C)
```

### Alert Timeline

**Understanding Alert Delays**:

- **CrashLoopBackOff**:
  - ~2-3 min: Kubernetes marks pod as CrashLoopBackOff
  - +5 min: `for: 5m` observation period
  - **Total: ~7-8 minutes** from crash to alert

- **HighCPU**:
  - Immediate: CPU spike detected
  - +5 min: `for: 5m` sustained load requirement
  - **Total: ~5-6 minutes** from load start to alert

- **Slack Notifications**: Sent immediately when alert enters **FIRING** state

### Troubleshooting Alerts

**Problem**: No alerts firing

**Solutions**:
1. Check Prometheus targets are UP:
   ```bash
   make mon-pf-prom
   # Open: http://localhost:9090/targets
   # Verify API target shows "UP"
   ```

2. Check ServiceMonitor has correct label:
   ```bash
   kubectl -n october get servicemonitor -o yaml | grep "release: mon"
   ```

3. Check PrometheusRule exists:
   ```bash
   kubectl -n october get prometheusrule
   ```

**Problem**: Slack notifications not working

**Solutions**:
1. Verify Secret exists:
   ```bash
   kubectl -n monitoring get secret am-slack -o yaml
   ```

2. Check Alertmanager config:
   ```bash
   kubectl -n monitoring get secret alertmanager-mon-kube-prometheus-stack-alertmanager -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
   ```

3. Test webhook manually:
   ```bash
   curl -X POST <SLACK_WEBHOOK_URL> \
     -H 'Content-Type: application/json' \
     -d '{"text": "Test alert from Alertmanager"}'
   ```

**Problem**: Alert stuck in PENDING

**Cause**: Condition not met long enough (check `for: 5m` duration)

**Solution**: Wait longer or reduce `for:` duration in PrometheusRule

**Problem**: Too many false positives

**Solution**: Increase `for:` duration or adjust thresholds

---

## Troubleshooting

### No Metrics in Grafana?

**Checklist**:

1. **Check ServiceMonitor has `release: mon` label**:
   ```bash
   kubectl -n october get servicemonitor -o yaml | grep "release: mon"
   ```

2. **Verify Prometheus targets show API as UP**:
   ```bash
   make mon-pf-prom
   # Open: http://localhost:9090/targets
   # Look for "october/api-servicemonitor" - should show "UP"
   ```

3. **Generate traffic to create metrics**:
   ```bash
   curl http://localhost:8080/healthz
   # Or via Ingress:
   IP=$(minikube ip)
   curl http://api.$IP.nip.io/healthz
   ```

4. **Check `/metrics` endpoint directly**:
   ```bash
   kubectl -n october port-forward svc/api 8080:8000
   curl http://localhost:8080/metrics
   # Should see http_requests_total and http_request_duration_seconds
   ```

5. **Verify Prometheus scrape config**:
   ```bash
   kubectl -n monitoring get prometheus mon-kube-prometheus-stack-prometheus -o yaml | grep -A 10 serviceMonitorSelector
   ```

### Dashboard Shows "No Data"?

**Checklist**:

1. **Check namespace variable**: Set to `october` in dashboard settings
2. **Verify time range**: Ensure it includes recent data (Last 5 minutes)
3. **Check Prometheus data source**: Should point to `http://prometheus-operated:9090`
4. **Query Prometheus directly**:
   ```bash
   make mon-pf-prom
   # Open: http://localhost:9090/graph
   # Run query: http_requests_total{namespace="october"}
   ```

### Metrics Not Updating?

**Checklist**:

1. **Check scrape interval**: Default is 15s (configured in ServiceMonitor)
2. **Verify pod is running**:
   ```bash
   kubectl -n october get pods
   ```

3. **Check Prometheus logs**:
   ```bash
   kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus --tail=50
   ```

### High Cardinality Issues

**Problem**: Too many unique label combinations slow down Prometheus

**Solution**: Avoid high-cardinality labels like:
- ❌ User IDs, request IDs, timestamps
- ✅ HTTP status, method, path (limited set)

**Best Practice**: Use `path` label for grouped endpoints:
```python
# Good: path="/users"
# Bad: path="/users/12345"  # unique per user
```

### Prometheus Storage Full

**Check storage usage**:
```bash
kubectl -n monitoring exec -it prometheus-mon-kube-prometheus-stack-prometheus-0 -- df -h /prometheus
```

**Solutions**:
1. Reduce retention period (default: 10d):
   ```yaml
   # values.yaml
   prometheus:
     prometheusSpec:
       retention: 7d
   ```

2. Increase PVC size:
   ```yaml
   prometheus:
     prometheusSpec:
       storageSpec:
         volumeClaimTemplate:
           spec:
             resources:
               requests:
                 storage: 20Gi  # default: 10Gi
   ```

---

## Quick Reference

### Essential Commands

```bash
# Install monitoring stack
make mon-install

# Access Grafana
make mon-pf-grafana  # http://localhost:3000
make mon-grafana-pass

# Access Prometheus
make mon-pf-prom  # http://localhost:9090

# Access Alertmanager
make mon-pf-am  # http://localhost:9093

# Test alerts
make mon-fire-crash  # CrashLoopBackOff test
make mon-heal-crash  # Heal crash
make mon-fire-cpu    # High CPU test

# Check status
make mon-status
kubectl -n october get servicemonitor
kubectl -n october get prometheusrule
```

### Key Metrics Queries

```promql
# RPS by status
sum by (status) (rate(http_requests_total{namespace="october"}[5m]))

# Latency p95 (ms)
1000 * histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="october"}[5m])))

# 5xx error rate
sum(rate(http_requests_total{namespace="october", status=~"5.."}[5m]))

# Request rate by path
sum by (path) (rate(http_requests_total{namespace="october"}[5m]))

# Pod CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="october", pod=~"api-.*"}[5m])) by (pod)

# Pod memory (MiB)
sum(container_memory_working_set_bytes{namespace="october", pod=~"api-.*"}) by (pod) / 1024 / 1024
```

---

## Related Documentation

- **[Architecture: Observability](ARCHITECTURE.md#observability-architecture)** - System design
- **[Troubleshooting: Monitoring Issues](TROUBLESHOOTING.md#monitoring-issues)** - Common problems
- **[Operations: Chaos Testing](operations/README.md)** - Testing resilience with monitoring
- **[API Reference: /metrics endpoint](API_REFERENCE.md#metrics)** - Metrics specification
