# Kubernetes Manifests for ClickHouse S3 Files

## StorageClass

```yaml
# kubernetes/storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: s3files-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-REPLACE_WITH_YOUR_FILESYSTEM_ID
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

## PersistentVolume

```yaml
# kubernetes/persistentvolume.yaml
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
    volumeHandle: s3files:fs-REPLACE_WITH_YOUR_FILESYSTEM_ID
    volumeAttributes:
      mounttargetip: "REPLACE_WITH_YOUR_MOUNT_TARGET_IP"
  claimRef:
    namespace: production
    name: data-volume-clickhouse-0
```

## ClickHouse StatefulSet Example

```yaml
# kubernetes/examples/clickhouse-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: clickhouse
  namespace: production
spec:
  serviceName: clickhouse
  replicas: 1
  selector:
    matchLabels:
      app: clickhouse
  template:
    metadata:
      labels:
        app: clickhouse
    spec:
      containers:
      - name: clickhouse
        image: clickhouse/clickhouse-server:25.5.1
        ports:
        - containerPort: 9000
          name: native
        - containerPort: 8123
          name: http
        volumeMounts:
        - name: data-volume
          mountPath: /var/lib/clickhouse
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
  volumeClaimTemplates:
  - metadata:
      name: data-volume
    spec:
      accessModes:
        - ReadWriteMany
      storageClassName: s3files-sc
      resources:
        requests:
          storage: 500Gi
```

## ClickHouse Service

```yaml
# kubernetes/examples/clickhouse-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: clickhouse
  namespace: production
spec:
  type: ClusterIP
  ports:
  - port: 9000
    targetPort: 9000
    name: native
  - port: 8123
    targetPort: 8123
    name: http
  selector:
    app: clickhouse
```

## Apply Instructions

```bash
# 1. Update filesystem ID and mount target IP in the manifests
sed -i 's/REPLACE_WITH_YOUR_FILESYSTEM_ID/fs-abc123def456/g' kubernetes/*.yaml
sed -i 's/REPLACE_WITH_YOUR_MOUNT_TARGET_IP/10.0.1.100/g' kubernetes/*.yaml

# 2. Apply StorageClass
kubectl apply -f kubernetes/storageclass.yaml

# 3. Apply PersistentVolume
kubectl apply -f kubernetes/persistentvolume.yaml

# 4. Apply ClickHouse StatefulSet
kubectl apply -f kubernetes/examples/clickhouse-statefulset.yaml

# 5. Apply ClickHouse Service
kubectl apply -f kubernetes/examples/clickhouse-service.yaml

# 6. Verify
kubectl get pv,pvc,pods -n production
```
