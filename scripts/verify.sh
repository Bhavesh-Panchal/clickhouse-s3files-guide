#!/bin/bash
# Verification Script for S3 Files Setup

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-production}"
POD_NAME="${POD_NAME:-clickhouse-0}"

echo "========================================="
echo "S3 Files Setup Verification"
echo "========================================="
echo ""

# Check 1: S3 Files filesystem
echo -e "${YELLOW}[1/8] Checking S3 Files filesystem...${NC}"
if [ -n "$FILESYSTEM_ID" ] && [ -n "$REGION" ]; then
    STATE=$(aws efs describe-file-systems \
      --file-system-id $FILESYSTEM_ID \
      --region $REGION \
      --query 'FileSystems[0].LifeCycleState' \
      --output text 2>/dev/null || echo "error")
    
    if [ "$STATE" = "available" ]; then
        echo -e "${GREEN}✓ Filesystem is available${NC}"
    else
        echo -e "${RED}✗ Filesystem not available (state: $STATE)${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Skipped (FILESYSTEM_ID or REGION not set)${NC}"
fi

# Check 2: EFS CSI Driver
echo -e "${YELLOW}[2/8] Checking EFS CSI Driver...${NC}"
if kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver &>/dev/null; then
    DRIVER_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver --no-headers | wc -l)
    RUNNING_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver --field-selector=status.phase=Running --no-headers | wc -l)
    
    if [ "$DRIVER_PODS" -eq "$RUNNING_PODS" ]; then
        echo -e "${GREEN}✓ EFS CSI Driver running ($RUNNING_PODS pods)${NC}"
    else
        echo -e "${RED}✗ EFS CSI Driver not fully running ($RUNNING_PODS/$DRIVER_PODS)${NC}"
    fi
else
    echo -e "${RED}✗ EFS CSI Driver not found${NC}"
fi

# Check 3: StorageClass
echo -e "${YELLOW}[3/8] Checking StorageClass...${NC}"
if kubectl get storageclass s3files-sc &>/dev/null; then
    echo -e "${GREEN}✓ StorageClass 's3files-sc' exists${NC}"
else
    echo -e "${RED}✗ StorageClass 's3files-sc' not found${NC}"
fi

# Check 4: PersistentVolume
echo -e "${YELLOW}[4/8] Checking PersistentVolume...${NC}"
if kubectl get pv clickhouse-s3files-pv &>/dev/null; then
    PV_STATUS=$(kubectl get pv clickhouse-s3files-pv -o jsonpath='{.status.phase}')
    if [ "$PV_STATUS" = "Bound" ] || [ "$PV_STATUS" = "Available" ]; then
        echo -e "${GREEN}✓ PersistentVolume exists (status: $PV_STATUS)${NC}"
    else
        echo -e "${YELLOW}⊘ PersistentVolume exists but status is: $PV_STATUS${NC}"
    fi
else
    echo -e "${RED}✗ PersistentVolume 'clickhouse-s3files-pv' not found${NC}"
fi

# Check 5: PVC
echo -e "${YELLOW}[5/8] Checking PersistentVolumeClaim...${NC}"
if kubectl get pvc -n $NAMESPACE | grep -q clickhouse; then
    PVC_STATUS=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$PVC_STATUS" = "Bound" ]; then
        echo -e "${GREEN}✓ PVC is bound${NC}"
    else
        echo -e "${YELLOW}⊘ PVC status: $PVC_STATUS${NC}"
    fi
else
    echo -e "${RED}✗ No ClickHouse PVC found in namespace $NAMESPACE${NC}"
fi

# Check 6: ClickHouse Pod
echo -e "${YELLOW}[6/8] Checking ClickHouse pod...${NC}"
if kubectl get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
    POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "${GREEN}✓ ClickHouse pod is running${NC}"
    else
        echo -e "${YELLOW}⊘ ClickHouse pod status: $POD_STATUS${NC}"
    fi
else
    echo -e "${RED}✗ ClickHouse pod '$POD_NAME' not found${NC}"
fi

# Check 7: S3 Files Mount
echo -e "${YELLOW}[7/8] Checking S3 Files mount...${NC}"
if kubectl get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
    MOUNT_INFO=$(kubectl exec $POD_NAME -n $NAMESPACE -- df -h 2>/dev/null | grep clickhouse || echo "")
    if [[ $MOUNT_INFO == *"efs"* ]]; then
        echo -e "${GREEN}✓ S3 Files is mounted${NC}"
        echo "  $MOUNT_INFO"
    else
        echo -e "${RED}✗ S3 Files not mounted${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Skipped (pod not running)${NC}"
fi

# Check 8: ClickHouse Connectivity
echo -e "${YELLOW}[8/8] Checking ClickHouse connectivity...${NC}"
if kubectl get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
    if kubectl exec $POD_NAME -n $NAMESPACE -- clickhouse-client --query "SELECT 1" &>/dev/null; then
        echo -e "${GREEN}✓ ClickHouse is responding${NC}"
    else
        echo -e "${RED}✗ ClickHouse not responding${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Skipped (pod not running)${NC}"
fi

echo ""
echo "========================================="
echo "Verification Complete"
echo "========================================="
