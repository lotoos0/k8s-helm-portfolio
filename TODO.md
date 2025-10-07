# October-DevOps – Issues (M1, Day07)

## [M1] Enable NGINX Ingress Controller (Minikube)

**Labels:** `feature`, `chore`  
**Description:**  
Enable and verify the NGINX Ingress Controller on Minikube for routing external traffic to services.

**Acceptance criteria:**

- [x] Ingress controller enabled via `minikube addons enable ingress`.
- [x] Pods in `kube-system` show `ingress-nginx-controller` running.
- [x] Verified by `kubectl get pods -n ingress-nginx`.
- [x] Namespace `ingress-nginx` confirmed and reachable.

---

## [M1] API Ingress resource

**Labels:** `feature`  
**Description:**  
Create and apply an Ingress manifest for the API service, exposing it through NGINX with nip.io domain mapping.

**Acceptance criteria:**

- [x] Manifest `deploy/k8s/ingress-api.yaml` created.
- [x] Ingress route maps `api.<MINIKUBE_IP>.nip.io` → API service on port 8000.
- [x] `curl http://api.<MINIKUBE_IP>.nip.io/healthz` returns `{"status":"ok"}`.
- [x] TLS not required (plain HTTP for now).
- [x] Ingress applies cleanly and works after controller is enabled.

---

## [M1] Makefile ingress targets

**Labels:** `chore`  
**Description:**  
Extend Makefile with helper targets for ingress operations.

**Acceptance criteria:**

- [x] `make ingress-enable` – enables Minikube ingress addon.
- [x] `make ingress-apply` – applies ingress manifests.
- [x] `make ingress-test` – performs curl test to `/healthz` endpoint.
- [x] Commands work without manual typing of IP (resolved via `minikube ip`).

---

## [M1] docs: Local vs K8s runbook

**Labels:** `docs`  
**Description:**  
Create a runbook explaining local Docker Compose vs K8s environments and how to debug ingress flows.

**Acceptance criteria:**

- [x] File `docs/local-vs-k8s-runbook.md` created.
- [x] Includes short guide:
  - How to access API via Minikube IP.
  - How to check ingress logs.
  - How to troubleshoot 404/connection issues.
- [x] Provides comparison table: Docker Compose vs K8s.

---

## [M1] docs: README update: Ingress section

**Labels:** `docs`  
**Description:**  
Add a section about Minikube Ingress setup and API exposure in README.md.

**Acceptance criteria:**

- [ ] README includes step-by-step Ingress instructions.
- [ ] Mentions `nip.io` usage with `minikube ip`.
- [ ] References new Makefile ingress targets.
- [ ] Section titled “Ingress (Minikube)” added.
