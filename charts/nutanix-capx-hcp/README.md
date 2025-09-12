# Nutanix CAPX HCP Chart

This Helm chart deploys a Nutanix CAPX infrastructure provider for Kubernetes clusters using **Hosted Control Plane (HCP)** mode with k0smotron.

## Chart Scope

- **Control Plane**: Runs as k0smotron pods in the management cluster
- **Worker Nodes**: Deployed as Nutanix VMs via CAPX
- **Target**: CAPI v1beta2 ClusterClass with templateRef patterns

## Prerequisites

- k0rdent/kcm management cluster
- Nutanix Prism Central accessible from management cluster
- VM images prepared with cloud-init and k0s requirements
- Network subnet configured for worker VMs

## Installation

```bash
helm install nutanix-hcp oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-capx-hcp -n kcm-system
```

## Configuration

### Required Values

```yaml
nutanix:
  prismCentral:
    address: "10.1.1.100"  # Your Prism Central IP
  controlPlaneEndpoint:
    host: "10.1.1.200"     # VIP outside DHCP range

machineDefaults:
  image:
    name: "ubuntu-22.04-k0s"  # Your prepared image
  cluster:
    name: "PE-Cluster-01"     # Your PE cluster
  subnets:
    - name: "VM-Network"      # Your network
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
  name: my-hcp-cluster
spec:
  template: nutanix-k0s-hcp-0-1-0
  config:
    # Your cluster configuration
```

## Resources Created

This chart creates:
- `ClusterClass` (nutanix-k0s-hcp)
- `K0smotronControlPlaneTemplate` (hosted control plane)
- `K0sWorkerConfigTemplate` (worker bootstrap)
- `NutanixMachineTemplate` (worker VMs only)
- `NutanixCluster` (infrastructure)
- `ProviderTemplate` + `ProviderInterface` (CAPX installation)

## Documentation

For detailed usage and examples, see [NUTANIX.md](../../NUTANIX.md).

## Support

- Repository: https://github.com/k0rdent-oot/oot
- Issues: https://github.com/k0rdent-oot/oot/issues
