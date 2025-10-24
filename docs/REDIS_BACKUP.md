# Redis Backup & Restore

## Overview

This document describes the backup and restore procedures for Redis data in the October project. The strategy uses **RDB snapshots** (Redis Database file) via the `BGSAVE` command, producing a point-in-time snapshot stored as a local `.rdb` file.

**Key characteristics:**
- **Backup method:** Non-blocking background save (`BGSAVE`)
- **Format:** Binary RDB file (`dump.rdb`)
- **Storage:** Local filesystem (`./backups/`)
- **Downtime:** None for backup; minimal for restore (~60s)

---

## Prerequisites

Before performing backup or restore operations, ensure you have:

1. **kubectl** installed and configured
2. **Cluster access** to the target Kubernetes cluster
3. **Namespace access** to `october` (or your target namespace)
4. **Permissions** to execute commands in pods (`kubectl exec`, `kubectl cp`)
5. **Redis pod** running with label `app=redis`

### Verify prerequisites:

```bash
# Check cluster access
kubectl cluster-info

# Check namespace and Redis pod
kubectl -n october get pods -l app=redis

# Test exec access
kubectl -n october exec deploy/redis -- redis-cli PING
```

Expected output: `PONG`

---

## Backup Procedure

### Quick Start

```bash
# Backup Redis to ./backups/
make redis-backup

# List backups
make redis-list-backups
```

### Detailed Steps

**1. Trigger backup:**

```bash
make redis-backup
```

**2. Monitor progress:**

```
[backup] detecting redis pod in ns=october label app=redis...
[backup] LASTSAVE (before)
  1729800000
[backup] BGSAVE...
[backup] waiting for LASTSAVE to advance...
  done (1729800005)
[backup] copying /data/dump.rdb -> ./backups/redis-backup-20251024_180500.rdb
[backup] OK
```

**3. Verify backup:**

```bash
ls -lh ./backups/
# -rw-r--r-- 1 user user 123K Oct 24 18:05 redis-backup-20251024_180500.rdb
```

### Advanced Usage

**Override namespace or output directory:**

```bash
# Custom namespace
NS=production make redis-backup

# Custom backup directory
BACKUPS_DIR=/mnt/backups make redis-backup

# Both
NS=staging BACKUPS_DIR=/tmp/redis-backups make redis-backup
```

**Manual script execution:**

```bash
NS=october OUT_DIR=./backups ./scripts/redis-backup.sh
```

---

## Restore Procedure

⚠️ **WARNING:** Restore will **replace all current Redis data** and causes **brief downtime** (~60s).

### Quick Start

```bash
# List available backups
make redis-list-backups

# Restore from backup
make redis-restore BACKUP=./backups/redis-backup-20251024_180500.rdb
```

### Detailed Steps

**1. Identify backup file:**

```bash
make redis-list-backups
# ./backups/redis-backup-20251024_180500.rdb
```

**2. Initiate restore:**

```bash
make redis-restore BACKUP=./backups/redis-backup-20251024_180500.rdb
```

**3. Confirm operation:**

```
[restore] WARNING: This will REPLACE current Redis data!
Backup ./backups/redis-backup-20251024_180500.rdb
Target: october / redis
Continue? (yes/no): yes
```

**4. Monitor restore process:**

```
[restore] scale worker to 0 (prevent writes)
deployment.apps/worker scaled
[restore] detect redis pod...
[restore] copy backup to pod:/data/dump.rdb
[restore] SHUTDOWN NOSAVE (pod will terminate, RS will recreate)
[restore] wait for new pod...
deployment "redis" successfully rolled out
[restore] verify PING
PONG
[restore] scale worker back to 1
deployment.apps/worker scaled
[restore] DONE
```

### What Happens During Restore

1. **Worker scaling:** Celery workers scaled to 0 replicas (prevents writes)
2. **Backup copy:** `.rdb` file copied to Redis pod at `/data/dump.rdb`
3. **Redis restart:** `SHUTDOWN NOSAVE` terminates pod gracefully
4. **Pod recreation:** ReplicaSet creates new pod, loads `dump.rdb` on startup
5. **Verification:** `PING` confirms Redis is healthy
6. **Worker scaling:** Workers scaled back to 1 replica

**Total downtime:** ~30-60 seconds (pod restart time)

---

## Testing Backup & Restore

### End-to-End Test

**1. Insert test data:**

```bash
# Set test key
kubectl -n october exec deploy/redis -- redis-cli SET test-backup "backup-$(date +%s)"

# Verify
kubectl -n october exec deploy/redis -- redis-cli GET test-backup
# "backup-1729800000"
```

**2. Create backup:**

```bash
make redis-backup
```

**3. Modify data:**

```bash
# Change the key
kubectl -n october exec deploy/redis -- redis-cli SET test-backup "modified"

# Verify change
kubectl -n october exec deploy/redis -- redis-cli GET test-backup
# "modified"
```

**4. Restore from backup:**

```bash
make redis-restore BACKUP=./backups/redis-backup-20251024_180500.rdb
# Type "yes" when prompted
```

**5. Verify restoration:**

```bash
kubectl -n october exec deploy/redis -- redis-cli GET test-backup
# "backup-1729800000"  ✅ Original value restored!
```

### Database Size Check

```bash
# Check number of keys
kubectl -n october exec deploy/redis -- redis-cli DBSIZE

# List all keys (use carefully in production!)
kubectl -n october exec deploy/redis -- redis-cli KEYS '*'
```

---

## Troubleshooting

### Common Issues

#### 1. **Pod Not Found**

**Error:**
```
redis pod not found
```

**Cause:** No Redis pod with label `app=redis` in namespace.

**Solution:**
```bash
# Check Redis pod
kubectl -n october get pods -l app=redis

# If missing, deploy Redis
helm upgrade --install app deploy/helm/api -n october
```

---

#### 2. **BGSAVE Timeout**

**Error:**
```
BGSAVE still not finished
```

**Cause:** Background save takes >30s (large dataset, slow disk).

**Solution:**
- Check Redis logs: `kubectl -n october logs deploy/redis`
- Check PVC storage space: `kubectl -n october exec deploy/redis -- df -h /data`
- Increase timeout in `scripts/redis-backup.sh` (line 31: change `30` to `60`)

---

#### 3. **No Space on PVC**

**Error:**
```
(error) ERR Background save failed: Cannot allocate memory
```

**Cause:** Insufficient disk space on Persistent Volume.

**Solution:**
```bash
# Check PVC usage
kubectl -n october exec deploy/redis -- df -h /data

# If full, resize PVC or clean old data
kubectl -n october edit pvc redis-data
# Change storage size, e.g., 1Gi -> 2Gi
```

---

#### 4. **Permission Denied on `kubectl cp`**

**Error:**
```
error: unable to copy file: error executing command
```

**Cause:** Insufficient RBAC permissions or pod security policy.

**Solution:**
```bash
# Check RBAC
kubectl auth can-i create pods/exec -n october

# Alternative: Use port-forward + redis-cli SAVE
kubectl -n october port-forward deploy/redis 6379:6379
redis-cli -h localhost BGSAVE
```

---

#### 5. **Backup File Empty**

**Error:**
```
backup file empty
```

**Cause:** BGSAVE failed silently or `/data/dump.rdb` doesn't exist.

**Solution:**
```bash
# Check Redis data directory
kubectl -n october exec deploy/redis -- ls -lh /data/

# Manually trigger SAVE (blocking!)
kubectl -n october exec deploy/redis -- redis-cli SAVE

# Check Redis logs for errors
kubectl -n october logs deploy/redis
```

---

#### 6. **Worker Not Scaling Back**

**Symptom:** After restore, workers remain at 0 replicas.

**Cause:** Script failure after restore, or manual interruption.

**Solution:**
```bash
# Manually scale workers back
kubectl -n october scale deploy/worker --replicas=1

# Verify
kubectl -n october get deploy worker
```

---

## Best Practices

### 1. **Backup Frequency**

- **Development:** Manual backups before risky operations
- **Staging:** Daily backups via cron job
- **Production:** Hourly backups + daily snapshots

**Example cron job (production):**

```bash
# /etc/cron.d/redis-backup
0 * * * * cd /path/to/project && make redis-backup >> /var/log/redis-backup.log 2>&1
```

---

### 2. **Retention Policy**

Avoid accumulating unlimited backups:

```bash
# Keep last 7 daily backups
find ./backups/ -name "redis-backup-*.rdb" -mtime +7 -delete

# Keep last 24 hourly backups
ls -t ./backups/redis-backup-*.rdb | tail -n +25 | xargs rm -f
```

---

### 3. **Offsite Storage (S3/GCS)**

**Planned for M5 milestone:**

```bash
# Upload to S3
aws s3 cp ./backups/redis-backup-$(date +%Y%m%d).rdb \
  s3://my-bucket/redis-backups/

# Download from S3
aws s3 cp s3://my-bucket/redis-backups/redis-backup-20251024.rdb \
  ./backups/
```

**Alternative: Google Cloud Storage:**

```bash
gsutil cp ./backups/redis-backup-*.rdb gs://my-bucket/redis-backups/
```

---

### 4. **Encryption**

**At rest:**

```bash
# Encrypt backup with GPG
gpg --symmetric --cipher-algo AES256 ./backups/redis-backup-20251024.rdb

# Decrypt
gpg --decrypt redis-backup-20251024.rdb.gpg > redis-backup-20251024.rdb
```

**In transit:** Use encrypted S3 buckets or TLS for transfers.

---

### 5. **Test Restores Regularly**

**Weekly restore drill:**

```bash
# 1. Restore to staging namespace
NS=staging make redis-restore BACKUP=./backups/latest.rdb

# 2. Verify data integrity
kubectl -n staging exec deploy/redis -- redis-cli DBSIZE

# 3. Run smoke tests
kubectl -n staging exec deploy/api -- curl localhost:8000/healthz
```

---

### 6. **Monitoring Backup Success**

Add backup verification to CI/CD or monitoring:

```bash
# Check backup age (alert if >24h old)
LATEST=$(ls -t ./backups/redis-backup-*.rdb | head -1)
AGE=$(( $(date +%s) - $(stat -c %Y "$LATEST") ))
if [ "$AGE" -gt 86400 ]; then
  echo "WARNING: Latest backup is $((AGE/3600))h old!"
fi
```

---

## Security Considerations

### 1. **Backup File Permissions**

```bash
# Backups may contain sensitive data!
chmod 600 ./backups/*.rdb
```

### 2. **Access Control**

- Restrict `kubectl exec` access via RBAC
- Use separate service accounts for backup automation
- Audit backup access logs

### 3. **Data Sanitization**

For non-production environments:

```bash
# Anonymize sensitive keys before backup
kubectl -n october exec deploy/redis -- redis-cli DEL sensitive:key:*
make redis-backup
```

---

## Script Reference

### `scripts/redis-backup.sh`

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `NS` | `october` | Kubernetes namespace |
| `APP_LABEL` | `redis` | Pod label selector |
| `OUT_DIR` | `./backups` | Output directory for backups |

**Exit Codes:**

- `0` - Success
- `2` - Pod not found or file validation failed
- `3` - BGSAVE timeout (>30s)
- `4` - Backup file empty

---

### `scripts/redis-restore.sh`

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `NS` | `october` | Kubernetes namespace |
| `APP_LABEL` | `redis` | Pod label selector |
| `WORKER_DEPLOY` | `worker` | Worker deployment name |
| `BACKUP` | *(required)* | Path to `.rdb` backup file |

**Exit Codes:**

- `0` - Success
- `1` - User aborted confirmation
- `2` - Missing BACKUP parameter or pod not found

---

## Future Enhancements (M5)

Planned improvements for production readiness:

- [ ] **Automated S3/GCS upload** after each backup
- [ ] **Backup encryption** by default (GPG/KMS)
- [ ] **Prometheus metrics** for backup age/size
- [ ] **Alerting** on backup failures
- [ ] **Multi-region replication** for disaster recovery
- [ ] **Incremental backups** using AOF (Append-Only File)
- [ ] **CronJob manifest** for automated hourly backups

---

## Related Documentation

- [Kubernetes Operations](./DEPLOYMENT_GUIDE.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Security Notes](./SECURITY.md)

---

## Quick Reference

```bash
# Backup
make redis-backup                          # Create backup
make redis-list-backups                    # List backups

# Restore
make redis-restore BACKUP=./backups/file.rdb  # Restore from backup

# Override namespace
NS=production make redis-backup
NS=staging make redis-restore BACKUP=./backups/file.rdb

# Test data
kubectl -n october exec deploy/redis -- redis-cli SET test "value"
kubectl -n october exec deploy/redis -- redis-cli GET test
kubectl -n october exec deploy/redis -- redis-cli DBSIZE
```

---

**Last updated:** 2025-10-24
**Author:** Claude Code (docs-qa-engineer)
**Status:** Production-ready
