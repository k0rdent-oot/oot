# Nutanix CAPX Standalone Chart

This Helm chart deploys a Nutanix CAPX infrastructure provider for Kubernetes clusters using **Standalone** mode with VM-based control plane.

## Chart Scope

- **Control Plane**: Deployed as Nutanix VMs running k0s
- **Worker Nodes**: Deployed as Nutanix VMs via CAPX
- **Target**: CAPI v1beta2 ClusterClass with templateRef patterns

## Prerequisites

- k0rdent/kcm management cluster
- Nutanix Prism Central accessible from management cluster
- VM images prepared with cloud-init and k0s requirements
- Network subnet configured for control plane and worker VMs

## Installation

```bash
helm install nutanix-standalone oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-capx-standalone -n kcm-system
```

## Configuration

### Required Values

```yaml
nutanix:
  prismCentral:
    address: "10.1.1.100"  # Your Prism Central IP
  controlPlaneEndpoint:
    host: "10.1.1.201"     # VIP outside DHCP range

machineDefaults:
  image:
    name: "ubuntu-22.04-k0s"  # Your prepared image
  cluster:
    name: "PE-Cluster-01"     # Your PE cluster
  subnets:
    - name: "VM-Network"      # Your network

controlPlane:
  vcpuSockets: 4
  memorySize: "8Gi"
  systemDiskSize: "80Gi"

k0s:
  controlPlane:
    replicas: 3
```

### Credentials

Create credentials before installation:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: nutanix-creds
  namespace: capx-system
stringData:
  credentials: |
    [{"type": "basic_auth", "data": {"prismCentral": {"username": "admin", "password": "password"}}}]
EOF
```

## Usage

After installation, create clusters using:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: my-standalone-cluster
spec:
  template: nutanix-k0s-standalone-0-1-0
  config:
    # Your cluster configuration
```

## Resources Created

This chart creates:
- `ClusterClass` (nutanix-k0s-standalone)
- `K0sControlPlaneTemplate` (VM-based control plane)
- `NutanixMachineTemplate` (control plane VMs)
- `K0sWorkerConfigTemplate` (worker bootstrap)
- `NutanixMachineTemplate` (worker VMs)
- `NutanixCluster` (infrastructure)
- `ProviderTemplate` + `ProviderInterface` (CAPX installation)

## Support

- Repository: https://github.com/k0rdent-oot/oot
- Issues: https://github.com/k0rdent-oot/oot/issues
