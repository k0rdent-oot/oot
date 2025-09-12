# Nutanix Standalone Provider Pack

This provider pack enables deployment of Nutanix clusters with **Standalone** mode in k0rdent/kcm.

## What This Pack Provides

- **ProviderTemplate**: Installs CAPX (Nutanix infrastructure provider)
- **ProviderInterface**: Exposes `nutanix-standalone` provider for KCM discovery
- **ClusterTemplate**: References `nutanix-k0s-standalone` ClusterClass

## Installation

```bash
helm install nutanix-pp-standalone oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-pp-standalone -n kcm-system
```

## Usage

After installation, the `nutanix-standalone` provider will be available in KCM for cluster creation:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: my-cluster
spec:
  template: nutanix-k0s-standalone-0-1-0  # Available after installation
  config:
    # Cluster configuration
```

## Mode Details

- **Control Plane**: Nutanix VMs running k0s control plane
- **Worker Nodes**: Nutanix VMs managed by CAPX
- **Scaling**: Traditional cluster deployment with full VM isolation

## Dependencies

This provider pack requires:
- `nutanix-capx-standalone` chart (installed automatically via ProviderTemplate)
- CAPX CRDs (installed by CAPI operator)

## Documentation

For detailed configuration and examples, see [NUTANIX.md](../../NUTANIX.md).

## Support

- Repository: https://github.com/k0rdent-oot/oot
- Issues: https://github.com/k0rdent-oot/oot/issues
