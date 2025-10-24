#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-october}"
APP_LABEL="${APP_LABEL:-redis}"
WORKER_DEPLOY="${WORKER_DEPLOY:-worker}"
BACKUP="${BACKUP:-}"

if [ -z "${BACKUP:-}" ]; then
  echo "usage: BACKUP=./backups/redis-backup-YYYYMMDD_HHMMSS.rdb NS=october $0"
  exit 2
fi
[ -f "$BACKUP" ] || {
  echo "backup file not found: $BACKUP"
  exit 2
}

echo "[restore] WARNING: This will REPLACE current Redis data!"
echo "Backup: $BACKUP"
echo "Target: $NS / redis"
read -p "Continue? (yes/no): " confirm
[ "$confirm" = "yes" ] || {
  echo "Aborted."
  exit 1
}

# helpers
get_redis_container() {
  kubectl -n "$NS" get deploy redis -o jsonpath='{.spec.template.spec.containers[0].name}'
}
get_running_redis_pod() {
  kubectl -n "$NS" get po -l app="$APP_LABEL" \
    -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -n1
}
detect_rdb_path() {
  local pod="$1" ctr="$2"
  # prefer /data (official), fallback to bitnami path
  if kubectl -n "$NS" exec "$pod" -c "$ctr" -- sh -lc 'test -d /data'; then
    echo "/data/dump.rdb"
    return
  fi
  if kubectl -n "$NS" exec "$pod" -c "$ctr" -- sh -lc 'test -d /bitnami/redis/data'; then
    echo "/bitnami/redis/data/dump.rdb"
    return
  fi
  # last resort
  echo "/data/dump.rdb"
}

# remember worker replicas and scale down to avoid writes
echo "[restore] scale worker to 0 (prevent writes)"
PREV_WORKER_REPLICAS="$(kubectl -n "$NS" get deploy/"$WORKER_DEPLOY" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)"
kubectl -n "$NS" scale deploy/"$WORKER_DEPLOY" --replicas=0 || true

echo "[restore] detect redis pod & container..."
POD="$(get_running_redis_pod)"
[ -n "$POD" ] || {
  echo "redis pod not found"
  exit 2
}
CTR="$(get_redis_container)"
[ -n "$CTR" ] || {
  echo "redis container name not found"
  exit 2
}

RDB_PATH="$(detect_rdb_path "$POD" "$CTR")"
echo "[restore] copy backup to $POD:$RDB_PATH (container: $CTR)"
kubectl -n "$NS" cp "$BACKUP" "$POD:$RDB_PATH" -c "$CTR"

echo "[restore] SHUTDOWN NOSAVE (pod will terminate, RS will recreate)"
# SHUTDOWN zabije proces -> spodziewamy się nie-0 (np. 137), nie przerywamy
set +e
kubectl -n "$NS" exec "$POD" -c "$CTR" -- sh -lc 'redis-cli SHUTDOWN NOSAVE'
set -e

echo "[restore] wait for rollout..."
kubectl -n "$NS" rollout status deploy/redis --timeout=180s
kubectl -n "$NS" wait --for=condition=Ready pod -l app="$APP_LABEL" --timeout=180s

NEW_POD="$(get_running_redis_pod)"
NEW_CTR="$(get_redis_container)"
echo "[restore] new pod: $NEW_POD (container: $NEW_CTR)"

echo "[restore] verify PING"
kubectl -n "$NS" exec "$NEW_POD" -c "$NEW_CTR" -- redis-cli PING

echo "[restore] scale worker back to $PREV_WORKER_REPLICAS"
kubectl -n "$NS" scale deploy/"$WORKER_DEPLOY" --replicas="$PREV_WORKER_REPLICAS" || true

echo "[restore] DONE"
