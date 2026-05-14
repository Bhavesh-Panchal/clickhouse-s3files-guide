# Kubernetes Manifests for ClickHouse S3 Files

This directory contains production-ready Kubernetes manifests for deploying ClickHouse with S3 Files storage.

## 📁 Files

- `storageclass.yaml` - S3 Files StorageClass configuration
- `persistentvolume.yaml` - PersistentVolume for S3 Files
- `clickhouse-statefulset.yaml` - ClickHouse StatefulSet example
- `clickhouse-service.yaml` - ClickHouse Service

## 🚀 Quick Start

### 1. Update Configuration

Replace placeholders in the YAML files:

```bash
# Set your values
export FILESYSTEM_ID="fs-abc123def456"
export MOUNT_TARGET_IP="10.0.1.100"
export NAMESPACE="production"

# Update all files
sed -i "s/REPLACE_WITH_YOUR_FILESYSTEM_ID/$FILESYSTEM_ID/g" *.yaml
sed -i "s/REPLACE_WITH_YOUR_MOUNT_TARGET_IP/$MOUNT_TARGET_IP/g" *.yaml
sed -i "s/production/$NAMESPACE/g" *.yaml
```

### 2. Apply Manifests

```bash
# Apply in order
kubectl apply -f storageclass.yaml
kubectl apply -f persistentvolume.yaml
kubectl apply -f clickhouse-statefulset.yaml
kubectl apply -f clickhouse-service.yaml
```

### 3. Verify Deployment

```bash
# Check all resources
kubectl get pv,pvc,pods,svc -n production

# Check ClickHouse logs
kubectl logs clickhouse-0 -n production -f
```

## 📋 Manifest Details

### StorageClass (`storageclass.yaml`)

Creates the S3 Files StorageClass with:
- EFS CSI driver provisioner
- NFS mount options (TLS, IAM)
- Retain reclaim policy

### PersistentVolume (`persistentvolume.yaml`)

Pre-creates PV with:
- 500Gi capacity
- ReadWriteMany access mode
- Binding to specific PVC via claimRef

### StatefulSet (`clickhouse-statefulset.yaml`)

Deploys ClickHouse with:
- ClickHouse 25.5.1
- 2 CPU / 4Gi memory (requests)
- 4 CPU / 8Gi memory (limits)
- S3 Files volume mount

### Service (`clickhouse-service.yaml`)

Exposes ClickHouse:
- Port 9000 (native protocol)
- Port 8123 (HTTP interface)

## 🔧 Customization

### Change Storage Size

Edit `clickhouse-statefulset.yaml`:

```yaml
volumeClaimTemplates:
  - metadata:
      name: data-volume
    spec:
      resources:
        requests:
          storage: 1Ti  # Change this
```

### Change Resources

Edit `clickhouse-statefulset.yaml`:

```yaml
resources:
  requests:
    cpu: "4"      # Change this
    memory: "8Gi" # Change this
  limits:
    cpu: "8"      # Change this
    memory: "16Gi" # Change this
```

### Change Namespace

```bash
# Update all files
sed -i 's/production/YOUR_NAMESPACE/g' *.yaml
```

## ✅ Verification

After applying manifests:

```bash
# 1. Check PV status
kubectl get pv clickhouse-s3files-pv
# Expected: STATUS = Bound or Available

# 2. Check PVC status
kubectl get pvc -n production
# Expected: STATUS = Bound

# 3. Check pod status
kubectl get pods -n production
# Expected: STATUS = Running

# 4. Check S3 Files mount
kubectl exec clickhouse-0 -n production -- df -h | grep clickhouse
# Expected: Shows EFS mount

# 5. Test ClickHouse
kubectl exec clickhouse-0 -n production -- clickhouse-client --query "SELECT 1"
# Expected: Returns 1
```

## 🐛 Troubleshooting

### PVC Stuck in Pending

```bash
# Check PV
kubectl get pv clickhouse-s3files-pv

# Check events
kubectl describe pvc -n production

# Solution: Verify claimRef matches PVC name
```

### Pod CrashLoopBackOff

```bash
# Check logs
kubectl logs clickhouse-0 -n production

# Check mount
kubectl describe pod clickhouse-0 -n production

# Solution: Check EFS CSI driver is running
kubectl get pods -n kube-system | grep efs-csi
```

### Mount Failed

```bash
# Check EFS CSI driver logs
kubectl logs -n kube-system -l app=efs-csi-controller

# Solution: Verify filesystem ID and mount target IP are correct
```

## 📚 Additional Resources

- [Manual Setup Guide](../docs/manual-setup-guide.md)
- [Migration Guide](../docs/migration-guide.md)
- [Troubleshooting Guide](../docs/troubleshooting.md)

## 🔗 Related Scripts

- `../scripts/setup-aws.sh` - Create S3 Files filesystem
- `../scripts/migrate.sh` - Automated migration
- `../scripts/verify.sh` - Verify setup
- `../scripts/rollback.sh` - Rollback to EBS
