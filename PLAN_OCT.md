# Plan Październik 2025 – „K8s + Helm + CI/CD + Observability” (po update)

## Stałe zasady

- **Typy dni:**
  - Pełny wolny → ~7,5h (ciężkie rzeczy).
  - Z nocą (przed nocą) → ~4–5h (średnie).
  - Po nocy → 2,5–4,5h (lekkie/średnie).
  - Po dniówce → 1–2h (mikro).
- **Tracking:** GitHub Projects (Board „October-DevOps”), kolumny: _Backlog → In Progress → Review → Done_.  
  Codzienny commit z tagiem w wiadomości: **`[DAY##]`**.
- **Debug:** zainstaluj **K9s** od razu, używaj zamiast samego `kubectl`.
- **Repo:** 2 serwisy (API FastAPI + worker Celery) + Redis, katalog `deploy/` (k8s/helm).

## Milestony

- **M1 (do 09.10):** Docker + docker-compose, podstawowe manifesty K8s, health/probes, Ingress, HPA, Redis, Worker.  
  → _Rezultat:_ działający lokalny i klastrowy stack w Minikube.

- **M2 (do 14.10):** Helm chart (dev/prod) z rollout/rollback, `values-dev.yaml` i `values-prod.yaml`.  
  → _Rezultat:_ aplikacja zdeployowana przez Helm z konfigurowalnymi wartościami środowiskowymi.

- **M3 (do 19.10):** CI/CD pipeline – build, test, scan, push image, deploy (`helm upgrade --install`), E2E smoke test.  
  → _Rezultat:_ pełny automatyczny pipeline: commit → build → scan → deploy → test.

- **M4 (do 23.10):** Observability stack – Prometheus + Grafana + Alertmanager, 2 alerty (CrashLoop, CPU>80%), dashboardy.  
  → _Rezultat:_ działający monitoring i alerty dla aplikacji i klastra.

- **M5 (do 31.10):** Release polish – Redis backup/restore, prod config, chaos test, README (EN) z sekcją kosztów i diagramami.  
  → _Rezultat:_ gotowe repo z pełną dokumentacją, kosztorysem i wydaniem **v0.1.0**.

---

## Plan datami (dopasowany do grafiku)

### Tydzień 1

**1 (noc 18–06)** – _4–5h przed nocą_

- Inicjalizacja repo: `api/`, `worker/`, `deploy/`, `scripts/`, `Makefile`.
- Kontrakt `/healthz`, `/metrics`, kolejka w workerze.
- **Załóż Project board** + wklej backlog.

**2 (po nocy)** – _2–3h_

- Dockerfile (API, multi-stage) + `make build/run`.
- `[DAY02]` commit.

**3 (po nocy)** – _2,5–4,5h_

- Dockerfile (worker), `docker-compose.yml` (api+redis+worker), smoke lokalnie.

**4 (pełny wolny)** – _~7,5h_

- Setup `pytest`, `ruff`, `black`; testy bazowe API.
- Endpoint `/ready`, **HEALTHCHECK** w Dockerfile.
- **Instalacja K9s**, krótkie notatki „k9s-cheats”.

**5 (pełny wolny)** – _~7,5h_

- K8s: Namespace, Deploy (api/worker), Service (api), ConfigMap/Secret.
- Uruchom w Minikube (`minikube start`), `kubectl port-forward`.

**6 (po dniówce)** – _1–2h_

- Dodaj `resources` + `liveness/readinessProbe`.
- `[DAY06]` porządki.

**7 (wolny)** – _~7,5h_

- NGINX Ingress Controller (Minikube addon) + Ingress dla API.
- „Local Dev vs K8s Runbook” (docs/).

### Tydzień 2

**8 (wolny)** – _~7,5h_

- HPA na CPU dla API + skrypt `scripts/load_tester.py`.

**9 (wolny)** – _~7,5h_ → **M1 DONE**

- PVC dla Redisa; ujednolicone env (dev/prod szkic).

**10 (noc)** – _4–5h przed nocą_

- Start **Helm chart**: `charts/app/` (Deployment/Service/Ingress/HPA/CM/Secret/PVC).
- `values-dev.yaml`, `values-prod.yaml`.

**11 (noc)** – _3–4h_

- Szablony Helm + `helpers.tpl` (naming/labels).

**12 (noc)** – _3–4h_

- `helm lint/template`, pierwszy `helm install -f values-dev.yaml`.

**13 (po nocy)** – _2,5–4,5h_

- **Upgrade/rollback** – scenariusze; checklista release’u.

**14 (wolny)** – _~7,5h_ → **M2 DONE**

- Porządki repo, szkic README, diagram ASCII, backlog update.

### Tydzień 3

**15 (po dniówce)** – _1–2h_

- CI szkic (GitHub Actions/GitLab CI): build + test.

**16 (po dniówce)** – _1–2h_

- Push image do GHCR/DockerHub (secrets), semver tagi.

**17 (06–14:15)** – _~2h po pracy_

- Job CD: `helm upgrade --install` (Minikube kubeconfig jako secret/artefakt).

**18 (wolny)** – _~7,5h_

- **Trivy** w CI (fail na HIGH/CRITICAL).
- `helm upgrade --atomic`, timeouty, retry.

**19 (wolny)** – _~7,5h_ → **M3 DONE**

- **E2E smoke w CI:** po deploy zrób `curl /healthz` przez port-forward/Ingress; fail ⇒ auto-rollback job.
- End-to-end: commit→build→scan→deploy→smoke.

**20 (UW, wolny)** – _~7,5h_

- **Prometheus**: scrape `/metrics`. Grafana dashboard: RPS, p95, 5xx.

**21 (UW, wolny)** – _~7,5h_

- **Alertmanager**:
  - Alert 1: CrashLoopBackOff >5m.
  - Alert 2: CPU >80% przez 5m.

**22 (wolny)** – _~7,5h_

- **SecurityContext** (non-root, fs read-only), NetworkPolicy (API↔Redis).

**23 (wolny)** – _~7,5h_ → **M4 DONE**

- Minimal base image (alpine/distroless), README „Security Notes”.

### Tydzień 4

**24 (po dniówce)** – _1–2h_

- Skrypt backup/restore Redis + dokument.

**25 (po dniówce)** – _1–2h_

- `values-prod.yaml`: limity, repliki, host ingress.

**26 (po dniówce)** – _1–2h_

- „Prod-like” namespace, smoke test.

**27 (wolny)** – _~7,5h_

- Mini-chaos: kill pod, obserwuj HPA/rollback; screeny do README.

**28 (wolny)** – _~7,5h_

- CI/CD polishing: cache, matrix, badge, status checks.

**29 (noc)** – _4–5h przed nocą_

- Porządki: `scripts/`, `docs/`, `make help`; nagraj krótki gif/asciinema z rolloutem.

**30 (noc)** – _3–4h_

- **README: sekcja „Koszty”**
  - Minikube (lokalnie, 0 zł za compute, uwagi o RAM/CPU).
  - Wersja chmurowa – orientacyjnie: node e2-micro/t3.micro, storage, egress; koszt monitoringu.
  - Notka o optymalizacji (HPA, limity, smalle obrazy).

**31 (po nocy)** – _2,5–4,5h_ → **M5 DONE**

- Final README (EN), diagramy, „Operations runbook”, linki do dashboardów.
- Release **v0.1.0** + krótkie ogłoszenie (zrzuty/ GIF).

---

## Priorytety na wypadek poślizgu

- **Must-have:** M1–M3 w całości, z E2E smoke.
- **Nice-to-have:** chaos testy, gif, rozbudowane dashboardy.
- **Tryb skrócony:** zostaw API+Redis, usuń workera (to samo CI/CD i Helm).
