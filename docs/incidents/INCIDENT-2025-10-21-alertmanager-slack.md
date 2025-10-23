# Incident Postmortem: Alertmanager → Slack Integration Failure

**Date:** 2025-10-21
**Duration:** ~4 hours
**Severity:** P2 (Monitoring degraded)
**Status:** RESOLVED
**Author:** DevOps Engineer

---

## Executive Summary

Alertmanager failed to send notifications to Slack webhook despite correct configuration in Helm values. The issue was caused by **two configuration errors** that prevented Prometheus Operator from properly reconciling the Alertmanager custom resource, resulting in a fallback to default templates with invalid field references.

**Impact:** Zero Slack notifications delivered. Production alerts (CrashLoop, CPU) were not reaching on-call team.

**Resolution:** Fixed `extraSecretMounts` placement in Helm values and migrated to Prometheus Operator's native `secrets` mount pattern.

---

## Timeline (UTC)

| Time   | Event                                                                                |
| ------ | ------------------------------------------------------------------------------------ |
| ~08:00 | Initial Alertmanager deployment with Slack config                                    |
| ~09:00 | Noticed Slack notifications not arriving                                             |
| 09:15  | Started debugging - found templating errors in logs                                  |
| 09:30  | **False lead:** Attempted to fix using Sprig `default` filter (not supported in AM)  |
| 10:00  | Removed `default` filter, new error appeared: `.Annotations.summary` field not found |
| 10:30  | Rewrote template to minimal version (only `.CommonLabels`)                           |
| 11:00  | **False lead:** Suspected multiple AM instances or wrong port-forward target         |
| 11:30  | Discovered API config ≠ Secret config (root cause investigation begins)              |
| 11:52  | **BREAKTHROUGH:** Found `extraSecretMounts` inside `alertmanager.config` (invalid!)  |
| 11:54  | Fixed config structure, Helm upgrade revision 14                                     |
| 11:55  | **RESOLVED:** 15 Slack notifications sent successfully, 0 failures                   |

---

## Root Cause Analysis

### Problem 1: `extraSecretMounts` in Wrong YAML Scope ⚠️

**Location:** `deploy/monitoring/values-alerting.yaml:29-34`

**Incorrect structure:**

```yaml
alertmanager:
  config:                    # ← Alertmanager configuration (pure AM YAML)
    global: ...
    route: ...
    receivers: ...
    extraSecretMounts:       # ❌ THIS IS THE BUG!
      - name: am-slack-webhook
        mountPath: /etc/alertmanager/slack
        ...
```

**Why it failed:**

- `alertmanager.config` is serialized **directly** to Alertmanager configuration YAML
- Prometheus Operator validates this config against Alertmanager's schema
- `extraSecretMounts` is **not** a valid Alertmanager config field
- Operator error: `field extraSecretMounts not found in type config.plain`
- Operator **fell back** to an old/default template containing `.Annotations.*` references

**Evidence:**

```bash
kubectl -n monitoring get alertmanager mon-kube-prometheus-stack-alertmanager -o yaml
# Status showed:
#   ReconciliationFailed: "field extraSecretMounts not found in type config.plain"
```

---

### Problem 2: Wrong Secret Mount Mechanism ⚠️

**Initial approach (doesn't work):**

```yaml
alertmanagerSpec:
  extraSecretMounts:         # ❌ Not supported by Alertmanager CR!
    - name: am-slack-webhook
      mountPath: /etc/alertmanager/slack
      ...
```

**Correct approach (Prometheus Operator pattern):**

```yaml
alertmanagerSpec:
  secrets: # ✅ Native Prometheus Operator field
    - am-slack-webhook # Auto-mounted to /etc/alertmanager/secrets/<name>/
```

**Why the first approach failed:**

- Helm chart accepted `extraSecretMounts` in values but didn't map it to Alertmanager CR spec
- Alertmanager CRD doesn't have `extraSecretMounts` field (checked via `kubectl get alertmanager -o jsonpath='{.spec}'`)
- The `secrets` field is the **canonical** way to mount secrets in Prometheus Operator

---

## False Leads / Red Herrings (4h debugging!)

### ❌ Theory 1: Multiple Alertmanager Instances

**Hypothesis:** Port-forward connects to wrong AM instance
**Investigation:** `kubectl get pods -A -l app.kubernetes.io/name=alertmanager`
**Result:** Only ONE instance found → **DISPROVEN**

### ❌ Theory 2: Template Syntax Issues (Sprig filters)

**Hypothesis:** Alertmanager uses Sprig template engine like Helm
**Investigation:** Tried `{{ .CommonLabels.severity | default "warning" }}`
**Result:** Error `function "default" not defined` → Alertmanager uses Go templates, NOT Sprig → **DISPROVEN**

### ❌ Theory 3: AlertmanagerConfig CRD Override

**Hypothesis:** External `AlertmanagerConfig` CR injecting old templates
**Investigation:** `kubectl get alertmanagerconfig -A`
**Result:** No CRDs found → **DISPROVEN**

### ❌ Theory 4: Config Reloader Not Syncing

**Hypothesis:** Config-reloader container not watching the right secret
**Investigation:** Checked reloader logs, found "Reload triggered" events
**Result:** Reloader working correctly, but processing **wrong source config** → **DISPROVEN**

---

## The "Aha!" Moment 💡

**Critical discovery:**

```bash
# Checked the SECRET we thought was being used:
kubectl -n monitoring get secret alertmanager-mon-kube-prometheus-stack-alertmanager -o yaml
# ✅ Contained our NEW minimal template (correct)

# But checked the SECRET actually mounted in the pod:
kubectl -n monitoring get pod alertmanager-...-0 -o jsonpath='{.spec.volumes}'
# Found: alertmanager-mon-kube-prometheus-stack-alertmanager-GENERATED ← DIFFERENT SECRET!

# Checked the GENERATED secret:
kubectl -n monitoring get secret alertmanager-...-generated -o yaml
# ❌ Contained OLD template with .Annotations.* (source of errors!)
```

**Realization:** Prometheus Operator **generates** a processed secret from the base secret. When the base secret had invalid fields (`extraSecretMounts`), the operator's reconciliation **failed** and it used a cached/default config instead!

---

## Resolution Steps

### 1. Fix Config Structure

**File:** `deploy/monitoring/values-alerting.yaml`

```diff
alertmanager:
  config:
    global:
-     slack_api_url_file: /etc/alertmanager/slack/webhook
+     slack_api_url_file: /etc/alertmanager/secrets/am-slack-webhook/webhook
    route: ...
    receivers:
      - name: default
        slack_configs:
          - channel: "#devops-alerts"
            text: |-
              Alert:  {{ .CommonLabels.alertname }}
              Status: {{ .Status }}
              Namespace: {{ .CommonLabels.namespace }}
              Labels:
              {{- range $k, $v := .CommonLabels }}
                - {{$k}}={{$v}}
              {{- end }}
-   extraSecretMounts:  # ❌ REMOVE from config
-     - name: am-slack-webhook
-       ...

+ alertmanagerSpec:    # ✅ ADD at correct level
+   secrets:
+     - am-slack-webhook
```

### 2. Apply Helm Upgrade

```bash
helm -n monitoring upgrade mon prometheus-community/kube-prometheus-stack \
  -f deploy/monitoring/values-extra.yaml \
  -f deploy/monitoring/values-alerting.yaml \
  --version 78.3.2
# Release "mon" has been upgraded. Revision: 14
```

### 3. Verify Reconciliation

```bash
# Check Alertmanager CR status:
kubectl -n monitoring get alertmanager mon-kube-prometheus-stack-alertmanager -o jsonpath='{.status.conditions}'
# Before: "ReconciliationFailed: field extraSecretMounts not found..."
# After:  "Reconciled: True" ✅

# Check secret mount in pod:
kubectl -n monitoring exec alertmanager-...-0 -- ls -la /etc/alertmanager/secrets/am-slack-webhook/
# Found: webhook file ✅

# Check metrics:
curl localhost:9093/metrics | grep alertmanager_notifications
# alertmanager_notifications_total{integration="slack"} 15
# alertmanager_notifications_failed_total{integration="slack",...} 0 ✅
```

---

## Verification & Testing

### Manual Alert Injection

```bash
kubectl -n monitoring port-forward svc/mon-kube-prometheus-stack-alertmanager 9093:9093

cat <<'EOF' | curl -X POST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d @-
[{
  "labels": {"alertname": "SlackPipelineTest", "severity": "warning", "namespace": "october"},
  "annotations": {"summary": "Test alert", "description": "Testing Slack integration"},
  "startsAt": "2025-10-21T12:00:00Z"
}]
EOF
```

**Result:** Message arrived in Slack `#devops-alerts` channel ✅

### Metrics Validation

```prometheus
alertmanager_notifications_total{integration="slack"}          # 15 notifications sent
alertmanager_notifications_failed_total{integration="slack"}   # 0 failures
alertmanager_alerts{state="active"}                            # 16 active alerts
```

---

## Lessons Learned

### What Went Well ✅

1. **Systematic debugging approach** - checked logs, secrets, configs, API status methodically
2. **Leveraged Kubernetes introspection** - `kubectl describe`, `exec`, `get -o jsonpath`
3. **Used metrics for validation** - Prometheus metrics confirmed success vs. blind testing
4. **Documented false leads** - prevented revisiting same theories

### What Went Wrong ❌

1. **Assumption about Helm chart behavior** - didn't verify how `extraSecretMounts` was actually implemented
2. **Not checking Operator CRD schema first** - would have revealed `secrets` field immediately
3. **Tunnel vision on template syntax** - spent time on Sprig/Go templates when real issue was config structure

### Key Takeaways 🎓

1. **Prometheus Operator pattern:** Use `alertmanagerSpec.secrets: [list]` NOT `extraSecretMounts`
2. **Config separation:** `alertmanager.config` = pure Alertmanager YAML (no K8s constructs!)
3. **Operator reconciliation:** Watch CR `.status.conditions` for `ReconciliationFailed` errors
4. **Secret generation:** Operator creates `-generated` secrets from base secrets (check BOTH!)
5. **Alertmanager templates:** Use Go templates (`.CommonLabels`, `.CommonAnnotations`), NOT Sprig filters

---

## Technical Deep Dive (Interview Prep 🎤)

### Architecture Flow

```
Helm Values
    ↓
kube-prometheus-stack Chart
    ↓
Alertmanager CR (monitoring.coreos.com/v1)
    ↓
Prometheus Operator Controller
    ↓
Secret: alertmanager-...-generated (with config)
    ↓
StatefulSet: alertmanager-...
    ↓
Pod with mounted secrets + config
    ↓
Alertmanager process reads /etc/alertmanager/config_out/alertmanager.env.yaml
```

### Key Files & Paths

| Location                                             | Purpose                               |
| ---------------------------------------------------- | ------------------------------------- |
| `deploy/monitoring/values-alerting.yaml`             | Helm values (source of truth)         |
| Secret: `alertmanager-mon-...-alertmanager`          | Base config secret (Helm-managed)     |
| Secret: `alertmanager-mon-...-generated`             | Processed config (Operator-generated) |
| `/etc/alertmanager/config_out/alertmanager.env.yaml` | Active config in pod                  |
| `/etc/alertmanager/secrets/am-slack-webhook/webhook` | Slack URL file                        |

### Debugging Commands Cheat Sheet

```bash
# Check Operator reconciliation status
kubectl -n monitoring get alertmanager <name> -o jsonpath='{.status.conditions}' | jq .

# Compare base vs generated secrets
kubectl -n monitoring get secret alertmanager-X -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
kubectl -n monitoring get secret alertmanager-X-generated -o jsonpath='{.data.alertmanager\.yaml\.gz}' | base64 -d | gunzip

# Check actual running config
kubectl -n monitoring exec <pod> -- cat /etc/alertmanager/config_out/alertmanager.env.yaml

# Verify secret mounts
kubectl -n monitoring get pod <pod> -o jsonpath='{.spec.volumes[*].name}' | tr ' ' '\n'

# Query Alertmanager API for config
kubectl -n monitoring port-forward svc/alertmanager 9093:9093
curl http://localhost:9093/api/v2/status | jq -r '.config.original'

# Check notification metrics
curl http://localhost:9093/metrics | grep alertmanager_notifications
```

---

## References

- [Prometheus Operator API Docs](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#alertmanagerspec)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Go Template Syntax](https://pkg.go.dev/text/template) (NOT Sprig!)

---

## Appendix: Working Configuration

**File:** `deploy/monitoring/values-alerting.yaml` (Final version)

```yaml
alertmanager:
  enabled: true
  config:
    global:
      slack_api_url_file: /etc/alertmanager/secrets/am-slack-webhook/webhook
    route:
      receiver: default
      group_by: [namespace, alertname]
      group_wait: 30s
      group_interval: 2m
      repeat_interval: 2h
      routes:
        - matchers: ['namespace="october"']
          receiver: default
    receivers:
      - name: default
        slack_configs:
          - channel: "#devops-alerts"
            send_resolved: true
            title: "{{ .CommonLabels.alertname }} ({{ .Status | toUpper }})"
            text: |-
              Alert:  {{ .CommonLabels.alertname }}
              Status: {{ .Status }}
              Namespace: {{ .CommonLabels.namespace }}
              Labels:
              {{- range $k, $v := .CommonLabels }}
                - {{$k}}={{$v}}
              {{- end }}
  alertmanagerSpec:
    secrets:
      - am-slack-webhook
```

**Secret:** `am-slack-webhook`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: am-slack-webhook
  namespace: monitoring
type: Opaque
stringData:
  webhook: "https://hooks.slack.com/services/***REDACTED***"
```

---

**Document Version:** 1.0
**Last Updated:** 2025-10-21
**Incident ID:** INC-2025-10-21-AM-SLACK
**Severity:** P2 - Monitoring degraded
**Resolution Time:** 4 hours
**Status:** RESOLVED ✅
