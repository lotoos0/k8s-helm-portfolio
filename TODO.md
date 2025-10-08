# October-DevOps – Issues (M1, Day08)

## [M1] Enable metrics-server on Minikube

**Labels:** `feature`, `chore`  
**Description:**  
Enable the Kubernetes metrics-server addon on Minikube to provide CPU/memory metrics required by HPA.

**Acceptance criteria:**

- [x] Metrics server enabled via `minikube addons enable metrics-server`.
- [x] Confirmed running: `kubectl get pods -n kube-system | grep metrics-server`.
- [x] `kubectl top nodes` and `kubectl top pods` return live CPU/memory metrics.
- [x] API Deployment metrics visible (`kubectl top pod -n october`).

---

## [M1] Create HPA manifest for API (CPU autoscaling)

**Labels:** `feature`, `test`  
**Description:**  
Create and apply a HorizontalPodAutoscaler (HPA) manifest for the API Deployment (autoscaling/v2).

**Acceptance criteria:**

- [x] File `deploy/k8s/hpa-api.yaml` created.
- [x] Scales Deployment/api between minReplicas=1 and maxReplicas=3. *(Note: maxReplicas=5)*
- [x] Uses CPU utilization target (e.g. `targetCPUUtilizationPercentage: 70`). *(averageUtilization: 60)*
- [x] Applies cleanly: `kubectl apply -f deploy/k8s/hpa-api.yaml -n october`.
- [x] Verify: `kubectl get hpa -n october` shows target and metrics.

---

## [M1] Load tester script

**Labels:** `feature`, `test`  
**Description:**  
Create a simple load testing script that generates configurable concurrent requests against the API to trigger autoscaling.

**Acceptance criteria:**

- [x] Script located at `scripts/load_tester.py`.
- [x] Configurable parameters: RPS, concurrency, duration.
- [x] Uses `aiohttp` or `requests-futures` to send `/healthz` or `/ready` requests. *(Uses requests+ThreadPoolExecutor)*
- [x] Prints live request rate and success/failure counts.
- [x] Can trigger HPA scaling when run for ~60–120s.
- [ ] Optional: progress bar or ASCII chart of responses.

---

## [M1] Makefile: HPA & metrics targets

**Labels:** `chore`  
**Description:**  
Add helper Makefile targets for HPA lifecycle and cluster monitoring.

**Acceptance criteria:**

- [x] `make k8s-enable-metrics` – enables metrics-server.
- [x] `make k8s-apply-hpa` – applies HPA manifest.
- [x] `make k8s-hpa-status` – shows HPA status (`kubectl get hpa -n october`).
- [x] `make k8s-top` – displays CPU usage for pods/nodes.
- [x] `make load-test` – runs local load tester against API ingress or port-forward.
