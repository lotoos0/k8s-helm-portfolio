#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-october}"
APP_LABEL="${APP_LABEL:-redis}"
OUT_DIR="${OUT_DIR:-./backups}"
mkdir -p "$OUT_DIR"

echo "[backup] detecting redis pod in ns=$NS label app=$APP_LABEL..."
POD="$(kubectl -n "$NS" get po -l app="$APP_LABEL" -o jsonpath='{.items[0].metadata.name}')"
[ -n "$POD" ] || {
  echo "redis pod not found"
  exit 2
}

echo "[backup] LASTSAVE (before)"
BEFORE=$(kubectl -n "$NS" exec "$POD" -- redis-cli LASTSAVE | tr -d '\r')
echo "  $BEFORE"

echo "[backup] BGSAVE..."
kubectl -n "$NS" exec "$POD" -- redis-cli BGSAVE >/dev/null

echo "[backup] waiting for LASTSAVE to advance..."
for i in $(seq 1 30); do
  NOW=$(kubectl -n "$NS" exec "$POD" -- redis-cli LASTSAVE | tr -d '\r')
  if [ "$NOW" -gt "$BEFORE" ]; then
    echo "  done ($NOW)"
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    echo "BGSAVE still not finished"
    exit 3
  fi
done

TS=$(date +%Y%m%d_%H%M%S)
DST="$OUT_DIR/redis-backup-$TS.rdb"
echo "[backup] copying /data/dump.rdb -> $DST"
kubectl -n "$NS" cp "$POD:/data/dump.rdb" "$DST"

[ -s "$DST" ] || {
  echo "backup file empty"
  exit 4
}
ls -lh "$DST"
echo "[backup] OK"
