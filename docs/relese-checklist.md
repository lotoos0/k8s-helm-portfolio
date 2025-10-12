# Release Checklist (Dev via Helm)

## Pre-flight

- [ ] `helm lint --strict` clean
- [ ] `helm template --debug --validate` clean
- [ ] Images built & present in Minikube (`make k8s-build-load`, `imagePullPolicy: IfNotPresent`)
- [ ] Ingress controller running (`minikube addons enable ingress`)

## Deploy

```bash
make helm-up-dev
kubectl -n october get po,svc,ing
kubectl -n october rollout status deploy/api
kubectl -n october rollout status deploy/worker
```

## Smoke

```bash
IP=$(minikube ip)
curl -s http://api.$IP.nip.io/healthz
curl -s http://api.$IP.nip.io/ready
```

## Troubleshooting

- Pods not ready → kubectl -n october describe po -l app=api
- Ingress 404/timeout → host mismatch or service port mapping
- Image not found → rebuild & minikube image load
- Rollout stuck → helm rollback app <REV>

## Post

- [ ] helm history app -n october
- [ ] README update (what changed)
