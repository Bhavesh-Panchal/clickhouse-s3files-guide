# Amazon S3 Files Manual Setup Guide for ClickHouse on Kubernetes

**Complete step-by-step manual configuration guide**

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites](#2-prerequisites)
3. [Architecture Overview](#3-architecture-overview)
4. [AWS S3 Files Setup](#4-aws-s3-files-setup)
5. [Kubernetes Configuration](#5-kubernetes-configuration)
6. [ClickHouse Integration](#6-clickhouse-integration)
7. [Helm Chart Configuration](#7-helm-chart-configuration)
8. [Deployment Steps](#8-deployment-steps)
9. [Verification and Testing](#9-verification-and-testing)
10. [Troubleshooting](#10-troubleshooting)
11. [Rollback Procedures](#11-rollback-procedures)

---

## 1. Introduction

### What is Amazon S3 Files?

Amazon S3 Files is a fully managed, elastic file system built on Amazon S3 that provides:
- **NFS protocol support** for seamless integration
- **Automatic scaling** from GBs to PBs
- **70% cost savings** compared to EBS ($0.024/GB vs $0.08/GB)
- **High availability** across multiple Availability Zones
- **No capacity planning** required

### Use Case

This guide demonstrates how to configure ClickHouse to use Amazon S3 Files as persistent storage instead of traditional EBS volumes, achieving:
- ✅ Significant cost reduction (70% savings)
- ✅ Unlimited storage capacity
- ✅ Simplified storage management
- ✅ High availability and durability

---

## 2. Prerequisites

### AWS Requirements

- ✅ AWS Account with appropriate permissions
- ✅ EKS cluster running in AWS
- ✅ VPC with private subnets
- ✅ Security groups configured for NFS traffic (port 2049)
- ✅ IAM permissions for S3 Files operations

### Kubernetes Requirements

- ✅ Kubernetes version: 1.25+
- ✅ EFS CSI Driver installed (version 2.0.7+)
- ✅ Helm 3.12+
- ✅ kubectl access to cluster
- ✅ Namespace created (e.g., `production`)

### Tools Required

```bash
# Verify installations
aws --version          # AWS CLI v2.x
kubectl version        # Client v1.25+
helm version           # v3.12+
```

### IAM Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:CreateFileSystem",
        "elasticfilesystem:CreateMountTarget",
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:TagResource",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:CreateSecurityGroup"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 3. Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              ClickHouse Pod                          │  │
│  │  ┌────────────────────────────────────────────┐     │  │
│  │  │  ClickHouse Container                      │     │  │
│  │  │  /var/lib/clickhouse/                      │     │  │
│  │  └────────────────────────────────────────────┘     │  │
│  │                    ↓ mount                           │  │
│  │  ┌────────────────────────────────────────────┐     │  │
│  │  │  PersistentVolumeClaim (PVC)               │     │  │
│  │  │  storage: 500Gi                            │     │  │
│  │  └────────────────────────────────────────────┘     │  │
│  └──────────────────────────────────────────────────────┘  │
│                         ↓ binds to                          │
│  ┌────────────────────────────────────────────────────┐    │
│  │  PersistentVolume (PV)                             │    │
│  │  volumeHandle: s3files:fs-abc123def456             │    │
│  │  mounttargetip: 10.0.1.100                         │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                          ↓ NFS 4.1
┌─────────────────────────────────────────────────────────────┐
│                    Amazon S3 Files                           │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Filesystem: fs-abc123def456                       │    │
│  │  Mount Target: 10.0.1.100 (us-east-1a)            │    │
│  │  Storage Class: General Purpose                    │    │
│  │  Backend: Amazon S3                                │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Storage Classes Comparison

| Storage Type | Use Case | Cost/GB/Month | Performance |
|--------------|----------|---------------|-------------|
| **EBS gp3** | Hot data, high IOPS | $0.08 | 16,000 IOPS |
| **S3 Files** | Warm/cold data, large datasets | $0.024 | 1,000+ MB/s |
| **S3 Standard** | Archive, infrequent access | $0.023 | Variable |

---

## 4. AWS S3 Files Setup

### Step 4.1: Create S3 Files Filesystem

**Option A: AWS Console**

1. Navigate to **Amazon EFS Console**: https://console.aws.amazon.com/efs/
2. Click **Create file system**
3. Select **Customize**
4. Configure filesystem:
   - **Name:** `clickhouse-storage`
   - **Storage class:** General Purpose
   - **Lifecycle management:** None
   - **Performance mode:** General Purpose
   - **Throughput mode:** Elastic
   - **Encryption:** Enabled (recommended)
5. Click **Next**
6. **Network settings:**
   - Select your VPC
   - Select Availability Zones (at least 2 for HA)
   - Select private subnets
   - Security group: Create or select one that allows NFS (port 2049)
7. Click **Next** → **Next** → **Create**
8. **Save the Filesystem ID** (e.g., `fs-abc123def456`)

**Option B: AWS CLI**

```bash
# Set your variables
REGION="us-east-1"
VPC_ID="vpc-xxxxx"              # Your VPC ID
SUBNET_ID="subnet-xxxxx"        # Private subnet in your AZ
SG_ID="sg-xxxxx"                # Security group allowing NFS

# Create filesystem
FILESYSTEM_ID=$(aws efs create-file-system \
  --region $REGION \
  --performance-mode generalPurpose \
  --throughput-mode elastic \
  --encrypted \
  --tags Key=Name,Value=clickhouse-storage \
  --query 'FileSystemId' \
  --output text)

echo "Filesystem ID: $FILESYSTEM_ID"
# Save this ID!

# Create mount target
MOUNT_TARGET_IP=$(aws efs create-mount-target \
  --region $REGION \
  --file-system-id $FILESYSTEM_ID \
  --subnet-id $SUBNET_ID \
  --security-groups $SG_ID \
  --query 'IpAddress' \
  --output text)

echo "Mount Target IP: $MOUNT_TARGET_IP"
# Save this IP!
```

### Step 4.2: Configure Security Group

**Inbound Rules Required:**

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| NFS | TCP | 2049 | VPC CIDR (e.g., 10.0.0.0/16) | Allow NFS from cluster |

**AWS Console:**
1. Go to EC2 → Security Groups
2. Select your security group
3. Click "Inbound rules" → "Edit inbound rules"
4. Add rule:
   - Type: NFS
   - Protocol: TCP
   - Port: 2049
   - Source: Your VPC CIDR (e.g., 10.0.0.0/16)
5. Save rules

**AWS CLI:**

```bash
# Add NFS rule to security group
aws ec2 authorize-security-group-ingress \
  --region $REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 2049 \
  --cidr 10.0.0.0/16 \
  --description "Allow NFS from EKS cluster"
```

### Step 4.3: Verify Filesystem Status

```bash
# Check filesystem state
aws efs describe-file-systems \
  --region $REGION \
  --file-system-id $FILESYSTEM_ID \
  --query 'FileSystems[0].LifeCycleState' \
  --output text

# Expected output: available

# Check mount target
aws efs describe-mount-targets \
  --region $REGION \
  --file-system-id $FILESYSTEM_ID \
  --query 'MountTargets[0].[IpAddress,LifeCycleState]' \
  --output table

# Expected output:
# -----------------
# |  10.0.1.100   |
# |  available    |
# -----------------
```

### Step 4.4: Record Configuration Details

**Create a configuration file to save these values:**

```bash
# Save to config file
cat > s3files-config.txt << EOF
# S3 Files Configuration
FILESYSTEM_ID=$FILESYSTEM_ID
MOUNT_TARGET_IP=$MOUNT_TARGET_IP
REGION=$REGION
AVAILABILITY_ZONE=$(aws efs describe-mount-targets \
  --file-system-id $FILESYSTEM_ID \
  --region $REGION \
  --query 'MountTargets[0].AvailabilityZoneName' \
  --output text)
EOF

cat s3files-config.txt
```

---

## 5. Kubernetes Configuration

### Step 5.1: Install EFS CSI Driver

**Check if already installed:**

```bash
kubectl get pods -n kube-system | grep efs-csi
```

**If not installed, install via Helm:**

```bash
# Add EFS CSI driver Helm repo
helm repo add aws-efs-csi-driver \
  https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

# Install EFS CSI driver
helm upgrade --install aws-efs-csi-driver \
  aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set image.repository=602401143452.dkr.ecr.$REGION.amazonaws.com/eks/aws-efs-csi-driver \
  --set controller.serviceAccount.create=true

# Verify installation
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
```

**Expected output:**
```
NAME                                  READY   STATUS    RESTARTS   AGE
efs-csi-controller-xxx                3/3     Running   0          2m
efs-csi-node-xxx                      3/3     Running   0          2m
```

**Verify driver version (must be v2.0.7+):**

```bash
kubectl get deployment efs-csi-controller -n kube-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Step 5.2: Create StorageClass

**Create file:** `storageclass.yaml`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: s3files-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-abc123def456  # Replace with your filesystem ID
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: "/clickhouse"
mountOptions:
  - tls
  - iam
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

**Apply:**

```bash
# Replace filesystem ID
sed -i "s/fs-abc123def456/$FILESYSTEM_ID/g" storageclass.yaml

# Apply
kubectl apply -f storageclass.yaml

# Verify
kubectl get storageclass s3files-sc
```

### Step 5.3: Create PersistentVolume

**Create file:** `persistentvolume.yaml`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: clickhouse-s3files-pv
  labels:
    app: clickhouse
    storage: s3files
spec:
  capacity:
    storage: 500Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: s3files-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: s3files:fs-abc123def456  # Replace with your filesystem ID
    volumeAttributes:
      mounttargetip: "10.0.1.100"  # Replace with your mount target IP
  claimRef:
    namespace: production  # Replace with your namespace
    name: data-volume-clickhouse-0  # Replace with your PVC name
```

**Key Parameters to Replace:**

| Parameter | Description | Example |
|-----------|-------------|---------|
| `volumeHandle` | S3 Files filesystem ID | `s3files:fs-abc123def456` |
| `mounttargetip` | Mount target IP address | `10.0.1.100` |
| `claimRef.namespace` | Your Kubernetes namespace | `production` |
| `claimRef.name` | Your PVC name | `data-volume-clickhouse-0` |

**Apply:**

```bash
# Replace values
sed -i "s/fs-abc123def456/$FILESYSTEM_ID/g" persistentvolume.yaml
sed -i "s/10.0.1.100/$MOUNT_TARGET_IP/g" persistentvolume.yaml
sed -i "s/production/YOUR_NAMESPACE/g" persistentvolume.yaml
sed -i "s/data-volume-clickhouse-0/YOUR_PVC_NAME/g" persistentvolume.yaml

# Apply
kubectl apply -f persistentvolume.yaml

# Verify
kubectl get pv clickhouse-s3files-pv
```

**Expected output:**
```
NAME                     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      STORAGECLASS   AGE
clickhouse-s3files-pv    500Gi      RWX            Retain           Available   s3files-sc     5s
```

---

## 6. ClickHouse Integration

### Step 6.1: Understand ClickHouse Deployment

ClickHouse can be deployed in two ways:

**Option A: Using ClickHouse Operator (CHI)**
- Automated StatefulSet management
- Automatic PVC creation
- Cluster management

**Option B: Manual StatefulSet**
- Direct control over configuration
- Custom PVC management

### Step 6.2: Get Current PVC Name

```bash
# List current ClickHouse PVCs
kubectl get pvc -n YOUR_NAMESPACE | grep clickhouse

# Example output:
# data-volume-clickhouse-0   Bound   pvc-xxx   100Gi   RWO   gp3   30d
```

**Save the PVC name** - you'll need it for the PV `claimRef`.

### Step 6.3: Check Current Storage Configuration

```bash
# For StatefulSet
kubectl get statefulset clickhouse -n YOUR_NAMESPACE -o yaml | grep -A 10 volumeClaimTemplates

# For ClickHouse Operator
kubectl get clickhouseinstallation -n YOUR_NAMESPACE -o yaml | grep -A 10 volumeClaimTemplates
```

---

## 7. Helm Chart Configuration

### Step 7.1: Update values.yaml

**If using Helm chart, update your `values.yaml`:**

```yaml
clickhouse:
  storage:
    # Change storageClass from gp3 to s3files-sc
    storageClass: "s3files-sc"
    size: "500Gi"
    accessModes:
      - ReadWriteMany  # Changed from ReadWriteOnce
    
    # S3 Files specific configuration
    s3files:
      enabled: true
      volumeHandle: "s3files:fs-abc123def456"  # Replace
      mountTargetIp: "10.0.1.100"  # Replace
```

### Step 7.2: Create PV Template (Optional)

**If using Helm, create:** `templates/clickhouse-s3files-pv.yaml`

```yaml
{{- if .Values.clickhouse.storage.s3files.enabled }}
apiVersion: v1
kind: PersistentVolume
metadata:
  name: clickhouse-s3files-pv
  labels:
    app: clickhouse
    storage: s3files
spec:
  capacity:
    storage: {{ .Values.clickhouse.storage.size }}
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: {{ .Values.clickhouse.storage.storageClass }}
  csi:
    driver: efs.csi.aws.com
    volumeHandle: {{ .Values.clickhouse.storage.s3files.volumeHandle }}
    volumeAttributes:
      mounttargetip: {{ .Values.clickhouse.storage.s3files.mountTargetIp | quote }}
  claimRef:
    namespace: {{ .Release.Namespace }}
    name: data-volume-clickhouse-0
{{- end }}
```

---

## 8. Deployment Steps

### Step 8.1: Pre-Deployment Checklist

```bash
# 1. Check S3 Files filesystem
aws efs describe-file-systems \
  --file-system-id $FILESYSTEM_ID \
  --region $REGION \
  --query 'FileSystems[0].LifeCycleState'
# Expected: "available"

# 2. Check EFS CSI driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
# Expected: All pods Running

# 3. Check StorageClass
kubectl get sc s3files-sc
# Expected: s3files-sc exists

# 4. Check current ClickHouse status
kubectl get pods -n YOUR_NAMESPACE | grep clickhouse
# Expected: Pod Running
```

### Step 8.2: Backup Current Configuration

```bash
# Create backup directory
mkdir -p ~/clickhouse-backup-$(date +%Y%m%d)
cd ~/clickhouse-backup-$(date +%Y%m%d)

# Backup StatefulSet
kubectl get statefulset clickhouse -n YOUR_NAMESPACE -o yaml > statefulset-backup.yaml

# Backup PVC
kubectl get pvc -n YOUR_NAMESPACE -o yaml > pvc-backup.yaml

# Backup ClickHouse data (if possible)
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- \
  clickhouse-client --query "BACKUP DATABASE production_db TO Disk('default', 'backup-$(date +%Y%m%d).zip')"
```

### Step 8.3: Deploy S3 Files Storage

**Method 1: Using Helm**

```bash
# Update Helm release
helm upgrade clickhouse ./helm-chart \
  --namespace YOUR_NAMESPACE \
  --values values.yaml \
  --wait \
  --timeout 10m

# Verify PV created
kubectl get pv clickhouse-s3files-pv
```

**Method 2: Manual Apply**

```bash
# Apply StorageClass
kubectl apply -f storageclass.yaml

# Apply PersistentVolume
kubectl apply -f persistentvolume.yaml

# Verify
kubectl get pv,sc
```

### Step 8.4: Migration Strategy

**Choose one of these strategies:**

#### Strategy 1: In-Place Migration (Recommended)

```bash
# 1. Stop data ingestion
kubectl scale deployment data-ingestion --replicas=0 -n YOUR_NAMESPACE

# 2. Update StatefulSet to use new StorageClass
kubectl patch statefulset clickhouse -n YOUR_NAMESPACE \
  --type='json' \
  -p='[{
    "op": "replace",
    "path": "/spec/volumeClaimTemplates/0/spec/storageClassName",
    "value": "s3files-sc"
  }]'

# 3. Delete pod to trigger recreation
kubectl delete pod clickhouse-0 -n YOUR_NAMESPACE

# 4. Wait for pod to be ready
kubectl wait --for=condition=ready pod/clickhouse-0 \
  --timeout=300s -n YOUR_NAMESPACE

# 5. Resume data ingestion
kubectl scale deployment data-ingestion --replicas=3 -n YOUR_NAMESPACE
```

#### Strategy 2: Blue-Green Deployment

```bash
# 1. Deploy new ClickHouse with S3 Files
kubectl apply -f clickhouse-s3files-statefulset.yaml

# 2. Copy data
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- \
  clickhouse-client --query "BACKUP DATABASE production_db TO Disk('default', 'migration.zip')"

kubectl exec clickhouse-s3files-0 -n YOUR_NAMESPACE -- \
  clickhouse-client --query "RESTORE DATABASE production_db FROM Disk('default', 'migration.zip')"

# 3. Switch traffic
kubectl patch service clickhouse -n YOUR_NAMESPACE \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/selector/app", "value": "clickhouse-s3files"}]'
```

### Step 8.5: Monitor Deployment

```bash
# Watch pod status
kubectl get pods -n YOUR_NAMESPACE -w

# Check PVC binding
kubectl get pvc -n YOUR_NAMESPACE

# Check pod events
kubectl describe pod clickhouse-0 -n YOUR_NAMESPACE

# Check logs
kubectl logs clickhouse-0 -n YOUR_NAMESPACE --tail=100 -f
```

---

## 9. Verification and Testing

### Step 9.1: Verify Mount

```bash
# Check if S3 Files is mounted
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- df -h | grep clickhouse

# Expected output:
# fs-abc123def456.efs.us-east-1.amazonaws.com:/  8.0E  0  8.0E  0%  /var/lib/clickhouse

# Check mount options
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- mount | grep clickhouse
# Expected: nfs4 with tls option
```

### Step 9.2: Verify ClickHouse Functionality

```bash
# Connect to ClickHouse
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -it -- clickhouse-client

# Run test queries
SELECT version();
SHOW DATABASES;
SELECT count() FROM system.tables;

# Check disk usage
SELECT
    name,
    path,
    formatReadableSize(free_space) AS free,
    formatReadableSize(total_space) AS total
FROM system.disks;
```

### Step 9.3: Performance Testing

```bash
# Create test table
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- clickhouse-client --query "
CREATE TABLE test_s3files (
    id UInt64,
    data String,
    timestamp DateTime
) ENGINE = MergeTree()
ORDER BY id;

INSERT INTO test_s3files 
SELECT 
    number,
    randomString(100),
    now()
FROM numbers(1000000);

SELECT count() FROM test_s3files;
"

# Test read performance
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- clickhouse-client --query "
SELECT count(), avg(length(data))
FROM test_s3files
WHERE id > 500000;
" --time

# Clean up
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- clickhouse-client --query "
DROP TABLE test_s3files;
"
```

### Step 9.4: Verify Data Persistence

```bash
# 1. Insert test data
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- clickhouse-client --query "
CREATE TABLE persistence_test (id UInt64) ENGINE = MergeTree() ORDER BY id;
INSERT INTO persistence_test VALUES (1), (2), (3);
"

# 2. Delete pod (simulates restart)
kubectl delete pod clickhouse-0 -n YOUR_NAMESPACE

# 3. Wait for pod to restart
kubectl wait --for=condition=ready pod/clickhouse-0 \
  --timeout=300s -n YOUR_NAMESPACE

# 4. Verify data still exists
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- clickhouse-client --query "
SELECT * FROM persistence_test;
"
# Expected output: 1, 2, 3

# 5. Clean up
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- clickhouse-client --query "
DROP TABLE persistence_test;
"
```

---

## 10. Troubleshooting

### Issue 1: PVC Stuck in Pending

**Check:**
```bash
kubectl describe pvc YOUR_PVC_NAME -n YOUR_NAMESPACE
```

**Solutions:**
1. Verify PV exists: `kubectl get pv clickhouse-s3files-pv`
2. Check claimRef matches PVC name
3. Verify StorageClass exists: `kubectl get sc s3files-sc`

### Issue 2: Mount Failed

**Check:**
```bash
kubectl logs -n kube-system -l app=efs-csi-controller --tail=50
```

**Solutions:**
1. Upgrade EFS CSI driver to v2.0.7+
2. Verify filesystem is available in AWS
3. Check security group allows NFS (port 2049)

### Issue 3: Permission Denied

**Fix permissions:**
```bash
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- \
  chown -R clickhouse:clickhouse /var/lib/clickhouse/
```

---

## 11. Rollback Procedures

### Rollback to EBS

```bash
# 1. Scale down ClickHouse
kubectl scale statefulset clickhouse --replicas=0 -n YOUR_NAMESPACE

# 2. Delete S3 Files PVC
kubectl delete pvc YOUR_PVC_NAME -n YOUR_NAMESPACE

# 3. Restore backup configuration
kubectl apply -f ~/clickhouse-backup-$(date +%Y%m%d)/statefulset-backup.yaml

# 4. Restore data from backup
kubectl exec clickhouse-0 -n YOUR_NAMESPACE -- \
  clickhouse-client --query "RESTORE DATABASE production_db FROM Disk('default', 'backup-*.zip')"
```

---

## Post-Deployment Checklist

- [ ] PV created and bound to PVC
- [ ] PVC status is "Bound"
- [ ] ClickHouse pod is "Running"
- [ ] S3 Files mounted correctly
- [ ] ClickHouse can read/write data
- [ ] Queries execute successfully
- [ ] Data persists after pod restart
- [ ] Performance meets expectations

---

**Document Version:** 1.0  
**Last Updated:** May 14, 2026  
**Status:** Production Ready
