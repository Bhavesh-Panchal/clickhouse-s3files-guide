# ClickHouse S3 Files Implementation Guide

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS](https://img.shields.io/badge/AWS-S3%20Files-orange)](https://aws.amazon.com/efs/)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-25.x-green)](https://clickhouse.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.25%2B-blue)](https://kubernetes.io/)

> **Complete guide to migrate ClickHouse from EBS to Amazon S3 Files, achieving 70% cost savings with minimal performance impact.**

📖 **Read the full blog post:** [Migrating ClickHouse to Amazon S3 Files](https://medium.com/@bhavesh-panchal)

---

## 🎯 What This Guide Covers

This repository provides a **production-ready implementation guide** for migrating ClickHouse storage from EBS to Amazon S3 Files on Kubernetes.

### Key Benefits

- ✅ **70% cost reduction** ($80/TB → $24/TB)
- ✅ **Zero data loss** migration
- ✅ **Minimal downtime** (< 5 minutes)
- ✅ **Unlimited scalability**
- ✅ **Production-tested** (30+ days uptime)

### What's Included

```
📦 clickhouse-s3files-guide/
├── 📁 aws/                    # AWS setup scripts
├── 📁 kubernetes/             # K8s manifests
├── 📁 helm/                   # Helm chart templates
├── 📁 scripts/                # Migration & automation scripts
├── 📁 benchmarks/             # Performance testing tools
├── 📁 monitoring/             # Grafana dashboards
├── 📁 docs/                   # Detailed documentation
└── 📁 examples/               # Real-world examples
```

---

## 🚀 Quick Start

### Prerequisites

- AWS Account with EKS cluster
- ClickHouse running on Kubernetes
- kubectl and helm installed
- AWS CLI configured

### 5-Minute Setup

```bash
# 1. Clone repository
git clone https://github.com/Bhavesh-Panchal/clickhouse-s3files-guide.git
cd clickhouse-s3files-guide

# 2. Configure your environment
cp config.example.yaml config.yaml
# Edit config.yaml with your AWS details

# 3. Run setup script
./scripts/setup.sh

# 4. Deploy S3 Files storage
kubectl apply -f kubernetes/

# 5. Migrate ClickHouse
./scripts/migrate.sh
```

**That's it!** Your ClickHouse is now running on S3 Files.

---

## 📚 Documentation

### Getting Started

**Choose Your Approach:**

#### 🔧 Manual Setup (Step-by-Step)
Perfect for learning and understanding each component:
1. [Manual Setup Guide](docs/manual-setup-guide.md) - Complete manual configuration
   - AWS S3 Files creation
   - Kubernetes configuration
   - ClickHouse integration
   - Verification and testing

#### 🚀 Automated Setup (Quick Start)
Perfect for production deployments:
1. [Migration Guide](docs/migration-guide.md) - Automated migration with scripts
   - Pre-built automation scripts
   - Multiple migration strategies
   - Rollback procedures

### Advanced Topics

- [Hybrid Architecture](docs/hybrid-architecture.md) - EBS + S3 Files tiering
- [Performance Tuning](docs/performance-tuning.md) - Optimize for your workload
- [Monitoring](docs/monitoring.md) - Grafana dashboards and alerts
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [Cost Calculator](docs/cost-calculator.md) - Estimate your savings

---

## 📁 Repository Structure

### `/aws` - AWS Setup Scripts

```bash
aws/
├── create-s3files.sh          # Create S3 Files filesystem
├── create-mount-target.sh     # Create mount target
├── configure-security-group.sh # Setup NFS security rules
└── cleanup.sh                 # Cleanup resources
```

**Usage:**
```bash
cd aws
./create-s3files.sh --region us-east-1 --name clickhouse-storage
```

### `/kubernetes` - Kubernetes Manifests

```bash
kubernetes/
├── storageclass.yaml          # S3 Files StorageClass
├── persistentvolume.yaml      # PV template
├── efs-csi-driver.yaml        # EFS CSI driver config
└── examples/
    ├── clickhouse-statefulset.yaml
    └── clickhouse-service.yaml
```

**Usage:**
```bash
kubectl apply -f kubernetes/storageclass.yaml
kubectl apply -f kubernetes/persistentvolume.yaml
```

### `/helm` - Helm Chart

```bash
helm/
├── Chart.yaml
├── values.yaml                # Default values
├── values-s3files.yaml        # S3 Files configuration
└── templates/
    ├── storageclass.yaml
    ├── persistentvolume.yaml
    └── clickhouse-installation.yaml
```

**Usage:**
```bash
helm install clickhouse-s3files ./helm \
  -f helm/values-s3files.yaml \
  --namespace production
```

### `/scripts` - Automation Scripts

```bash
scripts/
├── setup.sh                   # Complete setup automation
├── migrate.sh                 # Migration script
├── rollback.sh                # Rollback to EBS
├── verify.sh                  # Verification tests
└── cost-calculator.sh         # Calculate savings
```

**Usage:**
```bash
# Run migration with dry-run
./scripts/migrate.sh --dry-run

# Actual migration
./scripts/migrate.sh --execute

# Rollback if needed
./scripts/rollback.sh
```

### `/benchmarks` - Performance Testing

```bash
benchmarks/
├── query-benchmark.sql        # Query performance tests
├── insert-benchmark.sql       # Insert performance tests
├── run-benchmarks.sh          # Automated benchmark runner
└── results/
    ├── ebs-baseline.json
    └── s3files-results.json
```

**Usage:**
```bash
cd benchmarks
./run-benchmarks.sh --storage s3files --output results/
```

### `/monitoring` - Monitoring & Dashboards

```bash
monitoring/
├── grafana-dashboard.json     # Grafana dashboard
├── prometheus-rules.yaml      # Alert rules
└── cloudwatch-metrics.yaml    # CloudWatch integration
```

**Usage:**
```bash
kubectl apply -f monitoring/prometheus-rules.yaml
# Import grafana-dashboard.json into Grafana
```

---

## 🔧 Configuration

### Example Configuration

```yaml
# config.yaml
aws:
  region: us-east-1
  filesystem_id: fs-abc123def456  # Will be created by setup script
  mount_target_ip: 10.0.1.100     # Will be created by setup script
  
kubernetes:
  namespace: production
  storageclass_name: s3files-sc
  pv_name: clickhouse-s3files-pv
  pvc_name: clickhouse-data-pvc
  
clickhouse:
  cluster_name: my-cluster
  storage_size: 500Gi
  backup_before_migration: true
  
migration:
  strategy: in-place  # Options: in-place, blue-green, data-copy
  downtime_window: 5m
  rollback_enabled: true
```

---

## 📊 Performance Comparison

### Query Performance

| Query Type | EBS gp3 | S3 Files | Difference |
|------------|---------|----------|------------|
| 2-day range (2.7 GB) | 30-45 sec | 1-1.5 min | 2x slower |
| Full scan (150 GB) | 1m 15s | 3m 6s | 2.5x slower |
| Small queries (< 1 MB) | 3-5 ms | 7-8 ms | 2x slower |

### Insert Performance

| Metric | EBS gp3 | S3 Files | Difference |
|--------|---------|----------|------------|
| Insert rate | 1.5M rows/s | 312K rows/s | 5x slower |
| Throughput | 250 MB/s | 125 MB/s | 2x slower |

### Cost Comparison

| Storage Size | EBS gp3 | S3 Files | Savings |
|--------------|---------|----------|---------|
| 100 GB | $8/month | $2.40/month | 70% |
| 1 TB | $80/month | $24/month | 70% |
| 10 TB | $800/month | $240/month | 70% |

---

## 🎓 Use Cases

### ✅ Good Fit for S3 Files

- **Analytics workloads** (aggregations, time-series)
- **Large datasets** (> 100 GB)
- **Cost-sensitive** applications
- **Compliance/archival** data
- **SIEM/log analytics**
- **Data lakes**

### ⚠️ Not Recommended

- **Real-time queries** (< 1 sec latency)
- **High write throughput** (> 1M rows/sec)
- **Random I/O heavy** workloads
- **Small datasets** (< 50 GB)

---

## 🛠️ Migration Strategies

### Strategy 1: In-Place Migration (Recommended)

**Pros:** Minimal downtime (< 5 min), simple  
**Cons:** Brief service interruption

```bash
./scripts/migrate.sh --strategy in-place
```

### Strategy 2: Blue-Green Deployment

**Pros:** Zero downtime, easy rollback  
**Cons:** Requires 2x storage temporarily

```bash
./scripts/migrate.sh --strategy blue-green
```

### Strategy 3: Data Copy

**Pros:** No service interruption  
**Cons:** Longer migration time

```bash
./scripts/migrate.sh --strategy data-copy
```

---

## 🔍 Troubleshooting

### Common Issues

#### Issue: PVC Stuck in Pending

```bash
# Check PV status
kubectl get pv

# Check events
kubectl describe pvc clickhouse-data-pvc

# Solution: Verify claimRef matches
kubectl get pv clickhouse-s3files-pv -o yaml | grep -A 5 claimRef
```

#### Issue: Mount Failed

```bash
# Check EFS CSI driver version
kubectl get deployment efs-csi-controller -n kube-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Solution: Upgrade to v2.0.7+
helm upgrade aws-efs-csi-driver \
  aws-efs-csi-driver/aws-efs-csi-driver \
  --set image.tag=v2.0.7 \
  --namespace kube-system
```

**Full troubleshooting guide:** [docs/troubleshooting.md](docs/troubleshooting.md)

---

## 📈 Monitoring

### Grafana Dashboard

Import the included Grafana dashboard to monitor:
- Query latency (P50, P95, P99)
- Throughput (read/write)
- Storage usage
- Cost metrics

```bash
# Import dashboard
kubectl apply -f monitoring/grafana-dashboard.json
```

### CloudWatch Metrics

Monitor S3 Files performance:
- DataReadIOBytes
- DataWriteIOBytes
- ClientConnections
- PercentIOLimit

```bash
# Setup CloudWatch alarms
aws cloudwatch put-metric-alarm \
  --alarm-name clickhouse-s3files-throughput \
  --metric-name DataReadIOBytes \
  --namespace AWS/EFS \
  --statistic Sum \
  --period 300 \
  --threshold 1000000000 \
  --comparison-operator GreaterThanThreshold
```

---

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [ClickHouse Team](https://clickhouse.com/) for the amazing database
- [AWS EFS Team](https://aws.amazon.com/efs/) for S3 Files
- [Kubernetes SIG Storage](https://github.com/kubernetes-sigs) for EFS CSI driver

---

## 📞 Support

- 📖 **Documentation:** [docs/](docs/)
- 🐛 **Issues:** [GitHub Issues](https://github.com/Bhavesh-Panchal/clickhouse-s3files-guide/issues)
- 💬 **Discussions:** [GitHub Discussions](https://github.com/Bhavesh-Panchal/clickhouse-s3files-guide/discussions)
- 📧 **Email:** Open an issue for support

---

## 👤 Author

**Bhavesh Panchal**

- 💼 LinkedIn: [linkedin.com/in/bhavesh-panchal01](https://linkedin.com/in/bhavesh-panchal01/)
- 🐙 GitHub: [@Bhavesh-Panchal](https://github.com/Bhavesh-Panchal)
- 📝 Blog: [Medium](https://medium.com/@bhavesh-panchal)

---

## ⭐ Star History

If this project helped you, please consider giving it a ⭐!

[![Star History Chart](https://api.star-history.com/svg?repos=Bhavesh-Panchal/clickhouse-s3files-guide&type=Date)](https://star-history.com/#Bhavesh-Panchal/clickhouse-s3files-guide&Date)

---

**Made with ❤️ for the DevOps community**
