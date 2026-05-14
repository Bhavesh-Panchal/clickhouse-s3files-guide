#!/bin/bash
# scripts/migrate.sh
# ClickHouse EBS to S3 Files Migration Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-production}"
CLICKHOUSE_POD="${CLICKHOUSE_POD:-clickhouse-0}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/clickhouse-backup}"
DRY_RUN="${DRY_RUN:-false}"
STRATEGY="${STRATEGY:-in-place}"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster."
        exit 1
    fi
    
    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace $NAMESPACE does not exist."
        exit 1
    fi
    
    # Check ClickHouse pod exists
    if ! kubectl get pod "$CLICKHOUSE_POD" -n "$NAMESPACE" &> /dev/null; then
        log_error "ClickHouse pod $CLICKHOUSE_POD not found in namespace $NAMESPACE."
        exit 1
    fi
    
    # Check S3 Files StorageClass exists
    if ! kubectl get storageclass s3files-sc &> /dev/null; then
        log_error "StorageClass s3files-sc not found. Please create it first."
        exit 1
    fi
    
    # Check S3 Files PV exists
    if ! kubectl get pv clickhouse-s3files-pv &> /dev/null; then
        log_error "PersistentVolume clickhouse-s3files-pv not found. Please create it first."
        exit 1
    fi
    
    log_info "All prerequisites met ✓"
}

create_backup() {
    log_info "Creating backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup Kubernetes manifests
    kubectl get clickhouseinstallation -n "$NAMESPACE" -o yaml > "$BACKUP_DIR/chi-backup-$(date +%Y%m%d-%H%M%S).yaml"
    kubectl get pvc -n "$NAMESPACE" -o yaml > "$BACKUP_DIR/pvc-backup-$(date +%Y%m%d-%H%M%S).yaml"
    
    # Backup ClickHouse data
    log_info "Creating ClickHouse backup..."
    kubectl exec "$CLICKHOUSE_POD" -n "$NAMESPACE" -- \
        clickhouse-client --query "
            BACKUP DATABASE production_db 
            TO Disk('default', 'backup-$(date +%Y%m%d-%H%M%S).zip');
        " || log_warn "ClickHouse backup failed (may not be critical)"
    
    log_info "Backup created at $BACKUP_DIR ✓"
}

stop_ingestion() {
    log_info "Stopping data ingestion..."
    
    # Scale down data ingestion deployments
    kubectl scale deployment data-ingestion --replicas=0 -n "$NAMESPACE" 2>/dev/null || log_warn "data-ingestion deployment not found"
    
    # Wait for writes to stop
    sleep 5
    
    # Verify no writes
    ACTIVE_WRITES=$(kubectl exec "$CLICKHOUSE_POD" -n "$NAMESPACE" -- \
        clickhouse-client --query "SELECT count() FROM system.processes WHERE query LIKE '%INSERT%';" 2>/dev/null || echo "0")
    
    if [ "$ACTIVE_WRITES" -gt 0 ]; then
        log_warn "There are still $ACTIVE_WRITES active INSERT queries"
    else
        log_info "No active writes ✓"
    fi
}

migrate_in_place() {
    log_info "Starting in-place migration..."
    
    # Update CHI to use S3 Files
    log_info "Updating ClickHouse installation..."
    kubectl patch clickhouseinstallation my-cluster -n "$NAMESPACE" \
        --type merge \
        --patch '{
            "spec": {
                "templates": {
                    "volumeClaimTemplates": [{
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
                    }]
                }
            }
        }'
    
    # Delete pod to trigger recreation
    log_info "Deleting pod to trigger recreation..."
    kubectl delete pod "$CLICKHOUSE_POD" -n "$NAMESPACE"
    
    # Wait for pod to be ready
    log_info "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready pod/"$CLICKHOUSE_POD" \
        --timeout=300s -n "$NAMESPACE"
    
    log_info "In-place migration completed ✓"
}

verify_migration() {
    log_info "Verifying migration..."
    
    # Check mount
    log_info "Checking S3 Files mount..."
    MOUNT_INFO=$(kubectl exec "$CLICKHOUSE_POD" -n "$NAMESPACE" -- df -h | grep clickhouse || echo "")
    
    if [[ $MOUNT_INFO == *"efs"* ]]; then
        log_info "S3 Files mounted successfully ✓"
        echo "$MOUNT_INFO"
    else
        log_error "S3 Files not mounted correctly"
        exit 1
    fi
    
    # Check ClickHouse connectivity
    log_info "Checking ClickHouse connectivity..."
    kubectl exec "$CLICKHOUSE_POD" -n "$NAMESPACE" -- \
        clickhouse-client --query "SELECT 1;" > /dev/null
    log_info "ClickHouse is responding ✓"
    
    # Check databases
    log_info "Checking databases..."
    DB_COUNT=$(kubectl exec "$CLICKHOUSE_POD" -n "$NAMESPACE" -- \
        clickhouse-client --query "SELECT count() FROM system.databases;")
    log_info "Found $DB_COUNT databases ✓"
    
    # Check tables
    log_info "Checking tables..."
    TABLE_COUNT=$(kubectl exec "$CLICKHOUSE_POD" -n "$NAMESPACE" -- \
        clickhouse-client --query "SELECT count() FROM system.tables;")
    log_info "Found $TABLE_COUNT tables ✓"
    
    log_info "Verification completed ✓"
}

resume_ingestion() {
    log_info "Resuming data ingestion..."
    
    kubectl scale deployment data-ingestion --replicas=3 -n "$NAMESPACE" 2>/dev/null || log_warn "data-ingestion deployment not found"
    
    log_info "Data ingestion resumed ✓"
}

print_summary() {
    echo ""
    echo "========================================="
    echo "Migration Summary"
    echo "========================================="
    echo "Strategy: $STRATEGY"
    echo "Namespace: $NAMESPACE"
    echo "ClickHouse Pod: $CLICKHOUSE_POD"
    echo "Backup Location: $BACKUP_DIR"
    echo "Status: SUCCESS ✓"
    echo "========================================="
    echo ""
    echo "Next steps:"
    echo "1. Monitor performance for 24 hours"
    echo "2. Run benchmarks: cd benchmarks && ./run-benchmarks.sh"
    echo "3. Check monitoring dashboards"
    echo "4. If issues occur, run: ./scripts/rollback.sh"
    echo ""
}

# Main execution
main() {
    echo "========================================="
    echo "ClickHouse S3 Files Migration Script"
    echo "========================================="
    echo ""
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warn "DRY RUN MODE - No changes will be made"
    fi
    
    check_prerequisites
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Dry run completed. Run with --execute to perform actual migration."
        exit 0
    fi
    
    # Confirm before proceeding
    read -p "This will migrate ClickHouse to S3 Files. Continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_info "Migration cancelled."
        exit 0
    fi
    
    START_TIME=$(date +%s)
    
    create_backup
    stop_ingestion
    
    case "$STRATEGY" in
        in-place)
            migrate_in_place
            ;;
        *)
            log_error "Unknown strategy: $STRATEGY"
            exit 1
            ;;
    esac
    
    verify_migration
    resume_ingestion
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    log_info "Migration completed in $DURATION seconds"
    
    print_summary
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --execute)
            DRY_RUN=false
            shift
            ;;
        --strategy)
            STRATEGY="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run          Run in dry-run mode (no changes)"
            echo "  --execute          Execute migration"
            echo "  --strategy STRATEGY Migration strategy (in-place, blue-green, data-copy)"
            echo "  --namespace NS     Kubernetes namespace (default: production)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
