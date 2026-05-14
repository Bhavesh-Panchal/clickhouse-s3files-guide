#!/bin/bash
# Rollback Script - Revert to EBS

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-production}"
BACKUP_DIR="${BACKUP_DIR:-./backup}"

echo "========================================="
echo "S3 Files Rollback Script"
echo "========================================="
echo ""

# Confirm rollback
read -p "This will rollback to EBS storage. Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting rollback...${NC}"

# Step 1: Scale down ClickHouse
echo -e "${YELLOW}[1/6] Scaling down ClickHouse...${NC}"
kubectl scale statefulset clickhouse --replicas=0 -n $NAMESPACE
echo -e "${GREEN}✓ ClickHouse scaled down${NC}"

# Step 2: Delete S3 Files PVC
echo -e "${YELLOW}[2/6] Deleting S3 Files PVC...${NC}"
PVC_NAME=$(kubectl get pvc -n $NAMESPACE -o name | grep clickhouse | head -1)
if [ -n "$PVC_NAME" ]; then
    kubectl delete $PVC_NAME -n $NAMESPACE
    echo -e "${GREEN}✓ PVC deleted${NC}"
else
    echo -e "${YELLOW}⊘ No PVC found${NC}"
fi

# Step 3: Restore backup configuration
echo -e "${YELLOW}[3/6] Restoring backup configuration...${NC}"
if [ -d "$BACKUP_DIR" ]; then
    if [ -f "$BACKUP_DIR/statefulset-backup.yaml" ]; then
        kubectl apply -f $BACKUP_DIR/statefulset-backup.yaml
        echo -e "${GREEN}✓ StatefulSet restored${NC}"
    else
        echo -e "${RED}✗ Backup file not found${NC}"
    fi
else
    echo -e "${RED}✗ Backup directory not found${NC}"
fi

# Step 4: Wait for pod to be ready
echo -e "${YELLOW}[4/6] Waiting for pod to be ready...${NC}"
kubectl wait --for=condition=ready pod/clickhouse-0 \
  --timeout=300s -n $NAMESPACE || echo -e "${YELLOW}⊘ Timeout waiting for pod${NC}"

# Step 5: Restore data from backup
echo -e "${YELLOW}[5/6] Restoring data from backup...${NC}"
if kubectl get pod clickhouse-0 -n $NAMESPACE &>/dev/null; then
    BACKUP_FILE=$(ls $BACKUP_DIR/backup-*.zip 2>/dev/null | head -1)
    if [ -n "$BACKUP_FILE" ]; then
        kubectl exec clickhouse-0 -n $NAMESPACE -- \
          clickhouse-client --query "RESTORE DATABASE production_db FROM Disk('default', '$(basename $BACKUP_FILE)')" || \
          echo -e "${YELLOW}⊘ Data restore failed or not needed${NC}"
        echo -e "${GREEN}✓ Data restore attempted${NC}"
    else
        echo -e "${YELLOW}⊘ No backup file found${NC}"
    fi
else
    echo -e "${RED}✗ Pod not ready${NC}"
fi

# Step 6: Resume operations
echo -e "${YELLOW}[6/6] Resuming operations...${NC}"
kubectl scale deployment data-ingestion --replicas=3 -n $NAMESPACE 2>/dev/null || \
  echo -e "${YELLOW}⊘ data-ingestion deployment not found${NC}"

echo ""
echo "========================================="
echo -e "${GREEN}Rollback Complete${NC}"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Verify ClickHouse is running: kubectl get pods -n $NAMESPACE"
echo "2. Check data integrity: kubectl exec clickhouse-0 -n $NAMESPACE -- clickhouse-client"
echo "3. Monitor logs: kubectl logs clickhouse-0 -n $NAMESPACE -f"
echo ""
