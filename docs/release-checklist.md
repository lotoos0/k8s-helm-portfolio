## Pre-flight (strict)
- [ ] helm lint --strict
- [ ] helm template --debug --validate
- [ ] helm diff upgrade --allow-unreleased app deploy/helm/api -n october -f values.yaml -f values-dev.yaml --set api.ingress.host=api.<ip>.nip.io

## Deploy
- [ ] helm upgrade --install (with exact images/tags)
- [ ] kubectl rollout status (api, worker)
- [ ] ingress smoke: /healthz, /ready

## Rollback plan
- [ ] helm history app -n october
- [ ] helm rollback app <REV> -n october
- [ ] capture events / describe (root cause)
- [ ] restore previous `values-dev.yaml` or image tag

## Versioning (when releasing)
- [ ] Chart.yaml: version/appVersion updated
- [ ] Images built and pushed with semver tag
- [ ] Git tag vX.Y.Z
