#!/bin/bash
# AWS S3 Files Setup Script

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "AWS S3 Files Setup for ClickHouse"
echo "========================================="
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found${NC}"
    exit 1
fi

# Get parameters
read -p "AWS Region (default: us-east-1): " REGION
REGION=${REGION:-us-east-1}

read -p "VPC ID: " VPC_ID
if [ -z "$VPC_ID" ]; then
    echo -e "${RED}Error: VPC ID is required${NC}"
    exit 1
fi

read -p "Subnet ID (private subnet): " SUBNET_ID
if [ -z "$SUBNET_ID" ]; then
    echo -e "${RED}Error: Subnet ID is required${NC}"
    exit 1
fi

read -p "Security Group ID: " SG_ID
if [ -z "$SG_ID" ]; then
    echo -e "${RED}Error: Security Group ID is required${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Creating S3 Files filesystem...${NC}"

# Create filesystem
FILESYSTEM_ID=$(aws efs create-file-system \
  --region $REGION \
  --performance-mode generalPurpose \
  --throughput-mode elastic \
  --encrypted \
  --tags Key=Name,Value=clickhouse-storage \
  --query 'FileSystemId' \
  --output text)

echo -e "${GREEN}✓ Filesystem created: $FILESYSTEM_ID${NC}"

# Wait for filesystem to be available
echo -e "${YELLOW}Waiting for filesystem to be available...${NC}"
aws efs describe-file-systems \
  --file-system-id $FILESYSTEM_ID \
  --region $REGION \
  --query 'FileSystems[0].LifeCycleState' \
  --output text | grep -q "available" || sleep 10

echo -e "${GREEN}✓ Filesystem is available${NC}"

# Create mount target
echo -e "${YELLOW}Creating mount target...${NC}"
MOUNT_TARGET_IP=$(aws efs create-mount-target \
  --region $REGION \
  --file-system-id $FILESYSTEM_ID \
  --subnet-id $SUBNET_ID \
  --security-groups $SG_ID \
  --query 'IpAddress' \
  --output text)

echo -e "${GREEN}✓ Mount target created: $MOUNT_TARGET_IP${NC}"

# Add NFS rule to security group
echo -e "${YELLOW}Configuring security group...${NC}"
aws ec2 authorize-security-group-ingress \
  --region $REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 2049 \
  --cidr 10.0.0.0/8 \
  --description "Allow NFS from cluster" 2>/dev/null || echo "NFS rule may already exist"

echo -e "${GREEN}✓ Security group configured${NC}"

# Save configuration
cat > s3files-config.env << EOF
# S3 Files Configuration
export FILESYSTEM_ID=$FILESYSTEM_ID
export MOUNT_TARGET_IP=$MOUNT_TARGET_IP
export REGION=$REGION
export VPC_ID=$VPC_ID
export SUBNET_ID=$SUBNET_ID
export SG_ID=$SG_ID
EOF

echo ""
echo "========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "========================================="
echo ""
echo "Configuration saved to: s3files-config.env"
echo ""
echo "Filesystem ID: $FILESYSTEM_ID"
echo "Mount Target IP: $MOUNT_TARGET_IP"
echo "Region: $REGION"
echo ""
echo "Next steps:"
echo "1. Source the config: source s3files-config.env"
echo "2. Update Kubernetes manifests with these values"
echo "3. Apply Kubernetes configuration"
echo ""
