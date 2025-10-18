#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
if [[ -z "$HOST" ]]; then
  echo "usage: $0 api.192.168.49.2.nip.io"
  exit 2
fi

echo "[SMOKE] GET http://$HOST/healthz"
code=$(curl -s -o /dev/null -w "%{http_code}" "http://$HOST/healthz" || true)
if [[ "$code" != "200" ]]; then
  echo "[SMOKE] /healthz failed with code=$code"
  exit 1
fi

echo "[SMOKE] GET http://$HOST/ready"
code=$(curl -s -o /dev/null -w "%{http_code}" "http://$HOST/ready" || true)
if [[ "$code" != "200" ]]; then
  echo "[SMOKE] /ready failed with code=$code"
  exit 1
fi

echo "[SMOKE] OK"
