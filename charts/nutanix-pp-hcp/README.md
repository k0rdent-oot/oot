# Nutanix HCP Provider Pack

This provider pack enables deployment of Nutanix clusters with **Hosted Control Plane (HCP)** mode in k0rdent/kcm.

## What This Pack Provides

- **ProviderTemplate**: Installs CAPX (Nutanix infrastructure provider)
- **ProviderInterface**: Exposes `nutanix-hcp` provider for KCM discovery
- **ClusterTemplate**: References `nutanix-k0s-hcp` ClusterClass

## Installation

```bash
helm install nutanix-pp-hcp oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-pp-hcp -n kcm-system
```

## Usage

After installation, the `nutanix-hcp` provider will be available in KCM for cluster creation:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: my-cluster
spec:
  template: nutanix-k0s-hcp-0-1-0  # Available after installation
  config:
    # Cluster configuration
```

## Mode Details

- **Control Plane**: Runs as k0smotron pods in management cluster
- **Worker Nodes**: Nutanix VMs managed by CAPX
- **Scaling**: Fast worker scaling, shared management overhead

## Dependencies

This provider pack requires:
- `nutanix-capx-hcp` chart (installed automatically via ProviderTemplate)
- CAPX CRDs (installed by CAPI operator)
- k0smotron (installed with k0rdent)

## Documentation

For detailed configuration and examples, see [NUTANIX.md](../../NUTANIX.md).

## Support

- Repository: https://github.com/k0rdent-oot/oot
- Issues: https://github.com/k0rdent-oot/oot/issues
