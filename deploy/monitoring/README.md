# Monitoring Configuration

This directory contains Helm values for **kube-prometheus-stack** deployment.

## Files

| File | Purpose |
|------|---------|
| `values-alerting.yaml` | Alertmanager configuration (Slack integration, receivers, routes) |
| `values-extra.yaml` | Additional stack configurations (e.g., extra env vars) |

## Architecture

```
kube-prometheus-stack (Helm Chart)
├── Prometheus (metrics collection)
├── Grafana (visualization)
└── Alertmanager (alert routing)
    └── Slack Webhook (notifications)
```

## Quick Start

### 1. Install/Upgrade Stack

```bash
# Full install with all values
make mon-install

# Or apply alerting config only
make mon-alerts-apply
```

### 2. Setup Slack Webhook

**Create Secret:**
```bash
kubectl create secret generic am-slack-webhook \
  -n monitoring \
  --from-literal=webhook='https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
```

**Verify:**
```bash
kubectl -n monitoring get secret am-slack-webhook -o yaml
```

### 3. Access Components

```bash
make mon-pf-prom     # Prometheus → http://localhost:9090
make mon-pf-grafana  # Grafana   → http://localhost:3000
make mon-pf-am       # Alertmanager → http://localhost:9093
```

## Configuration Details

### Alertmanager (`values-alerting.yaml`)

**Key Sections:**

1. **Global Config:**
   ```yaml
   config:
     global:
       slack_api_url_file: /etc/alertmanager/secrets/am-slack-webhook/webhook
   ```
   - Webhook URL loaded from Secret (NOT hardcoded!)
   - Path: `/etc/alertmanager/secrets/<secret-name>/<key>`

2. **Routing:**
   ```yaml
   route:
     receiver: default
     group_by: [namespace, alertname]
     group_wait: 30s        # Wait before first notification
     group_interval: 2m     # Interval between updates
     repeat_interval: 2h    # Repeat resolved alerts
   ```

3. **Receivers:**
   ```yaml
   receivers:
     - name: default
       slack_configs:
         - channel: "#devops-alerts"
           text: |
             Alert:  {{ .CommonLabels.alertname }}
             Status: {{ .Status }}
             ...
   ```

4. **Secret Mounting (IMPORTANT!):**
   ```yaml
   alertmanagerSpec:
     secrets:
       - am-slack-webhook   # Auto-mounted to /etc/alertmanager/secrets/
   ```
   - **Do NOT use `extraSecretMounts` inside `config`!** (See incident postmortem)
   - Use `alertmanagerSpec.secrets` list (Prometheus Operator pattern)

## Testing Alerts

### Manual Alert Injection

```bash
# 1. Port-forward Alertmanager
make mon-pf-am

# 2. Send test alert
curl -X POST http://localhost:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "namespace": "october"
    },
    "annotations": {
      "summary": "Test alert from CLI"
    }
  }]'

# 3. Check Slack channel #devops-alerts
```

### Using Make Targets

```bash
# Trigger CrashLoopBackOff alert
make mon-fire-crash
# Wait ~7-8 minutes, check Slack

# Heal the crash
make mon-heal-crash

# Trigger CPU alert
make mon-fire-cpu
# Wait ~5-6 minutes, check Slack
```

## Troubleshooting

### Alert Not Firing?

1. **Check Prometheus targets:**
   ```bash
   make mon-pf-prom
   # Visit: http://localhost:9090/targets
   # Ensure API ServiceMonitor is UP
   ```

2. **Check alert rules:**
   ```bash
   # Visit: http://localhost:9090/alerts
   # Look for PENDING/FIRING state
   ```

3. **Check PrometheusRule:**
   ```bash
   kubectl -n october get prometheusrule -o yaml
   ```

### Slack Not Working?

1. **Check Alertmanager logs:**
   ```bash
   kubectl -n monitoring logs -l app.kubernetes.io/name=alertmanager --tail=100
   ```

2. **Check secret mount:**
   ```bash
   POD=$(kubectl -n monitoring get pod -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
   kubectl -n monitoring exec $POD -- ls -la /etc/alertmanager/secrets/am-slack-webhook/
   ```

3. **Check metrics:**
   ```bash
   curl http://localhost:9093/metrics | grep alertmanager_notifications
   # Look for:
   # - alertmanager_notifications_total{integration="slack"} > 0
   # - alertmanager_notifications_failed_total{integration="slack"} = 0
   ```

4. **Verify Alertmanager config:**
   ```bash
   curl http://localhost:9093/api/v2/status | jq -r '.config.original' | head -80
   ```

### Common Issues

**Problem:** `ReconciliationFailed: field extraSecretMounts not found`

**Cause:** `extraSecretMounts` placed inside `alertmanager.config` (wrong location)

**Fix:** Move to `alertmanagerSpec.secrets` list
```yaml
# ❌ WRONG:
alertmanager:
  config:
    extraSecretMounts: [...]

# ✅ CORRECT:
alertmanager:
  config: {...}
  alertmanagerSpec:
    secrets:
      - am-slack-webhook
```

**See:** `docs/incidents/INCIDENT-2025-10-21-alertmanager-slack.md` for full postmortem

---

**Problem:** Template error: `can't evaluate field Annotations`

**Cause:** Using `.Annotations.*` in template (only available in notification context)

**Fix:** Use `.CommonAnnotations.*` or `.CommonLabels.*`
```yaml
# ❌ WRONG:
text: |
  Summary: {{ .Annotations.summary }}

# ✅ CORRECT:
text: |
  Summary: {{ .CommonAnnotations.summary }}
  Alert: {{ .CommonLabels.alertname }}
```

---

**Problem:** `open /etc/alertmanager/slack/webhook: no such file or directory`

**Cause:** Webhook path doesn't match secret mount location

**Fix:** Ensure path matches `alertmanagerSpec.secrets` mount:
```yaml
config:
  global:
    slack_api_url_file: /etc/alertmanager/secrets/am-slack-webhook/webhook
    #                   ^^^^^^^^^^^^^^^^^^^^^^^^ Must match secret name
alertmanagerSpec:
  secrets:
    - am-slack-webhook  # Mounted at /etc/alertmanager/secrets/<name>/
```

## Alertmanager Template Syntax

Alertmanager uses **Go templates** (NOT Sprig like Helm!).

**Available Data:**

| Field | Description | Example |
|-------|-------------|---------|
| `.Status` | Alert state | `firing`, `resolved` |
| `.CommonLabels` | Labels shared by all alerts in group | `alertname`, `namespace`, `severity` |
| `.CommonAnnotations` | Annotations shared by all alerts | `summary`, `description` |
| `.GroupLabels` | Labels used for grouping | `namespace`, `alertname` |
| `.Alerts` | Array of individual alerts | For loops |

**NOT available at root level:**
- ❌ `.Annotations` (only inside `.Alerts` loop)
- ❌ `.Labels` (only inside `.Alerts` loop)
- ❌ Sprig functions like `default`, `upper`, `lower`

**Example Template:**
```yaml
text: |
  *Alert:* {{ .CommonLabels.alertname }}
  *Severity:* {{ .CommonLabels.severity }}
  *Namespace:* {{ .CommonLabels.namespace }}
  *Summary:* {{ .CommonAnnotations.summary }}

  *Alerts Firing:* {{ len .Alerts }}
  {{- range .Alerts }}
  • {{ .Labels.instance }}: {{ .Annotations.description }}
  {{- end }}
```

## Resources

- [Prometheus Operator Alertmanager Spec](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#alertmanagerspec)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [Go Template Syntax](https://pkg.go.dev/text/template)
- **Incident Postmortem:** `docs/incidents/INCIDENT-2025-10-21-alertmanager-slack.md`

## Checklist: Adding New Alert Receiver

- [ ] Create Secret with credentials (e.g., webhook URL, API token)
- [ ] Add secret name to `alertmanagerSpec.secrets` list
- [ ] Configure receiver in `config.receivers` (reference secret path)
- [ ] Add route in `config.route.routes` (if conditional routing needed)
- [ ] Test with manual alert injection
- [ ] Verify via metrics: `alertmanager_notifications_total{integration="..."}`
- [ ] Document in runbook

---

**Last Updated:** 2025-10-21
**Maintained by:** DevOps Team
