# ClickHouse Migration Guide: EBS to S3 Files

This guide provides step-by-step instructions for migrating your ClickHouse deployment from EBS to Amazon S3 Files.

---

## Table of Contents

1. [Pre-Migration Checklist](#pre-migration-checklist)
2. [Migration Strategies](#migration-strategies)
3. [Step-by-Step Migration](#step-by-step-migration)
4. [Verification](#verification)
5. [Rollback Procedure](#rollback-procedure)

---

## Pre-Migration Checklist

### ✅ Prerequisites

- [ ] S3 Files filesystem created and available
- [ ] EFS CSI Driver v2.0.7+ installed
- [ ] StorageClass `s3files-sc` created
- [ ] PersistentVolume created with correct claimRef
- [ ] Backup of current data completed
- [ ] Maintenance window scheduled
- [ ] Rollback plan documented

### ✅ Verify Current State

```bash
# Check ClickHouse pod status
kubectl get pods -n production | grep clickhouse

# Check current PVC
kubectl get pvc -n production

# Check current storage usage
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    SELECT
        formatReadableSize(sum(bytes_on_disk)) AS size
    FROM system.parts
    WHERE active;
  "

# Verify data integrity
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "SELECT count() FROM system.tables;"
```

---

## Migration Strategies

### Strategy 1: In-Place Migration (Recommended)

**Best for:** Production environments with acceptable 5-minute downtime

**Pros:**
- ✅ Minimal downtime (< 5 minutes)
- ✅ Simple process
- ✅ No data duplication

**Cons:**
- ⚠️ Brief service interruption
- ⚠️ Requires careful execution

**Downtime:** 4-5 minutes

---

### Strategy 2: Blue-Green Deployment

**Best for:** Zero-downtime requirements

**Pros:**
- ✅ Zero downtime
- ✅ Easy rollback
- ✅ Safe testing

**Cons:**
- ⚠️ Requires 2x storage temporarily
- ⚠️ More complex setup

**Downtime:** 0 minutes

---

### Strategy 3: Data Copy

**Best for:** Large datasets, no time pressure

**Pros:**
- ✅ No service interruption
- ✅ Gradual migration
- ✅ Extensive testing possible

**Cons:**
- ⚠️ Longer migration time
- ⚠️ Requires 2x storage

**Downtime:** 0 minutes (during migration), brief cutover

---

## Step-by-Step Migration

### Strategy 1: In-Place Migration

#### Step 1: Create Backup

```bash
# Backup ClickHouse data
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    BACKUP DATABASE production_db 
    TO Disk('default', 'backup-$(date +%Y%m%d).zip');
  "

# Backup Kubernetes manifests
kubectl get clickhouseinstallation -n production -o yaml > backup-chi.yaml
kubectl get pvc -n production -o yaml > backup-pvc.yaml
```

#### Step 2: Stop Data Ingestion

```bash
# Scale down data ingestion pods
kubectl scale deployment data-ingestion --replicas=0 -n production

# Verify no writes are happening
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    SELECT count() 
    FROM system.processes 
    WHERE query LIKE '%INSERT%';
  "
```

#### Step 3: Update ClickHouse Installation

```bash
# Update CHI to use S3 Files StorageClass
kubectl patch clickhouseinstallation my-cluster -n production \
  --type merge \
  --patch '
{
  "spec": {
    "templates": {
      "volumeClaimTemplates": [
        {
          "name": "data-volume",
          "spec": {
            "storageClassName": "s3files-sc",
            "accessModes": ["ReadWriteMany"],
            "resources": {
              "requests": {
                "storage": "500Gi"
              }
            }
          }
        }
      ]
    }
  }
}'
```

#### Step 4: Delete Pod to Trigger Recreation

```bash
# Delete ClickHouse pod
kubectl delete pod clickhouse-0 -n production

# Watch pod recreation
kubectl get pods -n production -w
```

#### Step 5: Wait for Pod Ready

```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod/clickhouse-0 \
  --timeout=300s -n production

# Check pod status
kubectl get pod clickhouse-0 -n production
```

#### Step 6: Verify Mount

```bash
# Verify S3 Files is mounted
kubectl exec clickhouse-0 -n production -- df -h | grep clickhouse

# Expected output:
# fs-abc123def456.efs.us-east-1.amazonaws.com:/  8.0E  0  8.0E  0%  /var/lib/clickhouse

# Check mount options
kubectl exec clickhouse-0 -n production -- mount | grep clickhouse
```

#### Step 7: Restore Data (if needed)

```bash
# If data didn't migrate automatically, restore from backup
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    RESTORE DATABASE production_db 
    FROM Disk('default', 'backup-$(date +%Y%m%d).zip');
  "
```

#### Step 8: Verify Data Integrity

```bash
# Check table count
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "SELECT count() FROM system.tables;"

# Check row counts
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    SELECT 
        database,
        table,
        formatReadableSize(sum(bytes_on_disk)) AS size,
        sum(rows) AS rows
    FROM system.parts
    WHERE active
    GROUP BY database, table;
  "

# Run test query
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "SELECT count() FROM production_db.main_table;"
```

#### Step 9: Resume Data Ingestion

```bash
# Scale up data ingestion
kubectl scale deployment data-ingestion --replicas=3 -n production

# Verify ingestion is working
kubectl logs -f deployment/data-ingestion -n production
```

#### Step 10: Monitor Performance

```bash
# Monitor query performance
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    SELECT
        event_time,
        query_duration_ms,
        read_rows,
        formatReadableSize(read_bytes) AS read_size
    FROM system.query_log
    WHERE event_time > now() - INTERVAL 10 MINUTE
    ORDER BY event_time DESC
    LIMIT 10;
  "
```

---

### Strategy 2: Blue-Green Deployment

#### Step 1: Deploy New ClickHouse with S3 Files

```bash
# Create new ClickHouse installation
kubectl apply -f - <<EOF
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: my-cluster-s3files
  namespace: production
spec:
  configuration:
    clusters:
      - name: my-cluster
        layout:
          shardsCount: 1
          replicasCount: 1
  templates:
    volumeClaimTemplates:
      - name: data-volume
        spec:
          storageClassName: s3files-sc
          accessModes:
            - ReadWriteMany
          resources:
            requests:
              storage: 500Gi
EOF
```

#### Step 2: Copy Data

```bash
# Use ClickHouse's BACKUP/RESTORE
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    BACKUP DATABASE production_db 
    TO Disk('default', 'migration-backup.zip');
  "

kubectl exec clickhouse-s3files-0 -n production -- \
  clickhouse-client --query "
    RESTORE DATABASE production_db 
    FROM Disk('default', 'migration-backup.zip');
  "
```

#### Step 3: Sync Recent Data

```bash
# Sync data written during migration
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    INSERT INTO clickhouse-s3files-0:9000.production_db.main_table
    SELECT * FROM production_db.main_table
    WHERE timestamp > '2026-05-14 00:00:00';
  "
```

#### Step 4: Switch Traffic

```bash
# Update service to point to new pods
kubectl patch service clickhouse -n production \
  --type merge \
  --patch '
{
  "spec": {
    "selector": {
      "clickhouse.altinity.com/chi": "my-cluster-s3files"
    }
  }
}'
```

#### Step 5: Verify and Cleanup

```bash
# Verify new cluster is serving traffic
kubectl exec clickhouse-s3files-0 -n production -- \
  clickhouse-client --query "SELECT count() FROM production_db.main_table;"

# After 24 hours of successful operation, delete old cluster
kubectl delete clickhouseinstallation my-cluster -n production
```

---

## Verification

### Functional Tests

```bash
# Test 1: Basic connectivity
kubectl exec clickhouse-0 -n production -- clickhouse-client --query "SELECT 1;"

# Test 2: Database access
kubectl exec clickhouse-0 -n production -- clickhouse-client --query "SHOW DATABASES;"

# Test 3: Table access
kubectl exec clickhouse-0 -n production -- clickhouse-client --query "SHOW TABLES FROM production_db;"

# Test 4: Data query
kubectl exec clickhouse-0 -n production -- clickhouse-client --query "
  SELECT count() FROM production_db.main_table;
"

# Test 5: Insert test
kubectl exec clickhouse-0 -n production -- clickhouse-client --query "
  CREATE TABLE test_insert (id UInt64, data String) ENGINE = MergeTree() ORDER BY id;
  INSERT INTO test_insert VALUES (1, 'test'), (2, 'test2');
  SELECT * FROM test_insert;
  DROP TABLE test_insert;
"
```

### Performance Tests

```bash
# Run benchmark script
cd benchmarks/
./run-benchmarks.sh --storage s3files --output results/post-migration.json

# Compare with baseline
./compare-results.sh results/ebs-baseline.json results/post-migration.json
```

### Data Integrity Check

```bash
# Compare row counts
kubectl exec clickhouse-0 -n production -- clickhouse-client --query "
  SELECT 
      database,
      table,
      sum(rows) AS total_rows,
      formatReadableSize(sum(bytes_on_disk)) AS total_size
  FROM system.parts
  WHERE active
  GROUP BY database, table
  ORDER BY database, table;
"

# Verify checksums (if available)
kubectl exec clickhouse-0 -n production -- clickhouse-client --query "
  SELECT 
      table,
      sum(rows) AS rows,
      sum(data_uncompressed_bytes) AS uncompressed_bytes
  FROM system.parts
  WHERE active AND database = 'production_db'
  GROUP BY table;
"
```

---

## Rollback Procedure

### When to Rollback

Rollback if you encounter:
- ❌ Data integrity issues
- ❌ Unacceptable performance degradation
- ❌ Application errors
- ❌ Mount failures

### Rollback Steps

#### Step 1: Stop New Writes

```bash
kubectl scale deployment data-ingestion --replicas=0 -n production
```

#### Step 2: Restore from Backup

```bash
# Restore Kubernetes manifests
kubectl apply -f backup-chi.yaml
kubectl apply -f backup-pvc.yaml
```

#### Step 3: Delete S3 Files PVC

```bash
kubectl delete pvc data-volume-clickhouse-0 -n production
```

#### Step 4: Recreate Pod with EBS

```bash
# Update CHI to use EBS StorageClass
kubectl patch clickhouseinstallation my-cluster -n production \
  --type merge \
  --patch '
{
  "spec": {
    "templates": {
      "volumeClaimTemplates": [
        {
          "name": "data-volume",
          "spec": {
            "storageClassName": "gp3",
            "accessModes": ["ReadWriteOnce"],
            "resources": {
              "requests": {
                "storage": "100Gi"
              }
            }
          }
        }
      ]
    }
  }
}'

# Delete pod
kubectl delete pod clickhouse-0 -n production
```

#### Step 5: Restore Data

```bash
# Restore from backup
kubectl exec clickhouse-0 -n production -- \
  clickhouse-client --query "
    RESTORE DATABASE production_db 
    FROM Disk('default', 'backup-$(date +%Y%m%d).zip');
  "
```

#### Step 6: Resume Operations

```bash
kubectl scale deployment data-ingestion --replicas=3 -n production
```

---

## Post-Migration Checklist

- [ ] All pods are running
- [ ] S3 Files is mounted correctly
- [ ] Data integrity verified
- [ ] Query performance acceptable
- [ ] Insert performance acceptable
- [ ] Monitoring dashboards updated
- [ ] Alerts configured
- [ ] Documentation updated
- [ ] Team notified
- [ ] Old EBS volumes cleaned up (after 7 days)

---

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues and solutions.

---

## Next Steps

1. [Monitor performance](monitoring.md) for 7 days
2. [Optimize queries](performance-tuning.md) if needed
3. [Implement hybrid architecture](hybrid-architecture.md) for better performance
4. [Set up cost tracking](cost-calculator.md)

---

**Need help?** Open an issue on [GitHub](https://github.com/Bhavesh-Panchal/clickhouse-s3files-guide/issues)
