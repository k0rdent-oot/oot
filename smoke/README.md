# Nutanix CAPX Provider Smoke Tests

This directory contains minimal smoke test assets for validating the Nutanix CAPX provider in both HCP and Standalone modes using the new split charts.

## Prerequisites

1. **Management Cluster** with k0rdent/kcm installed
2. **Nutanix Environment** properly configured:
   - Prism Central accessible
   - VM images prepared for k0s
   - Network subnets created
   - Projects/categories configured (optional)

## Setup Steps

### 1. Install k0rdent Management Cluster

```bash
helm install kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.2.0 -n kcm-system --create-namespace \
  --set controller.enableTelemetry=false \
  --set velero.enabled=false

kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

### 2. Install Nutanix Provider Packs

Choose one or both provider packs based on your testing needs:

#### For HCP Mode Testing:
```bash
helm install nutanix-pp-hcp oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-pp-hcp -n kcm-system --take-ownership

kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

#### For Standalone Mode Testing:
```bash
helm install nutanix-pp-standalone oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-pp-standalone -n kcm-system --take-ownership

kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

### 3. Create Nutanix Credentials

Choose **Option A** (global) or **Option B** (per-cluster):

#### Option A: Global Credentials (Recommended)

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: nutanix-creds
  namespace: capx-system
  labels:
    cluster.x-k8s.io/provider: infrastructure-nutanix
stringData:
  credentials: |
    [
      {
        "type": "basic_auth",
        "data": {
          "prismCentral": {
            "username": "admin",
            "password": "your-pc-password"
          },
          "prismElements": null
        }
      }
    ]
EOF
```

#### Option B: Per-Cluster Credentials

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: nutanix-cluster-creds
  namespace: kcm-system
  labels:
    cluster.x-k8s.io/provider: infrastructure-nutanix
stringData:
  credentials: |
    [
      {
        "type": "basic_auth",
        "data": {
          "prismCentral": {
            "username": "cluster-admin", 
            "password": "cluster-password"
          },
          "prismElements": null
        }
      }
    ]
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: nutanix-cluster-identity-cred
  namespace: kcm-system
spec:
  description: Nutanix cluster credentials
  identityRef:
    apiVersion: v1
    kind: Secret
    name: nutanix-cluster-creds
    namespace: kcm-system
EOF
```

### 4. Verify Provider Discoverability

```bash
# Check that provider templates are available
kubectl get providertemplate -A
kubectl get providerinterface -A
kubectl get clustertemplate -A

# Should show (depending on which provider packs you installed):
# - nutanix-capx-hcp-0-1-0 (ProviderTemplate)
# - nutanix-capx-hcp (ProviderInterface)
# - nutanix-capx-standalone-0-1-0 (ProviderTemplate)
# - nutanix-capx-standalone (ProviderInterface)
```

## Testing Modes

### HCP Mode Test

1. **Update values file**:
   ```bash
   cd smoke/hcp/
   cp values.yaml values-local.yaml
   # Edit values-local.yaml and replace all CHANGE_ME values
   ```

2. **Test with the new HCP chart** (for development testing):
   ```bash
   helm template nutanix-hcp ../charts/nutanix-capx-hcp -f values-local.yaml --namespace kcm-system
   ```

3. **Deploy cluster using ClusterDeployment**:
   ```bash
   # Edit clusterdeployment.yaml and replace CHANGE_ME values
   # Update template reference to: nutanix-k0s-hcp-0-1-0
   kubectl apply -f clusterdeployment.yaml
   ```

4. **Monitor deployment**:
   ```bash
   kubectl get clusterdeployment -n kcm-system
   kubectl get cluster -n kcm-system
   
   # Check HCP control plane (should run in management cluster)
   kubectl get pods -n kcm-system | grep k0smotron
   
   # Check worker machines (should create Nutanix VMs)
   kubectl get machine -n kcm-system
   kubectl get nutanixmachine -n kcm-system
   ```

### Standalone Mode Test

1. **Update values file**:
   ```bash
   cd smoke/standalone/
   cp values.yaml values-local.yaml  
   # Edit values-local.yaml and replace all CHANGE_ME values
   ```

2. **Test with the new Standalone chart** (for development testing):
   ```bash
   helm template nutanix-standalone ../charts/nutanix-capx-standalone -f values-local.yaml --namespace kcm-system
   ```

3. **Deploy cluster using ClusterDeployment**:
   ```bash
   # Edit clusterdeployment.yaml and replace CHANGE_ME values
   # Update template reference to: nutanix-k0s-standalone-0-1-0
   kubectl apply -f clusterdeployment.yaml
   ```

4. **Monitor deployment**:
   ```bash
   kubectl get clusterdeployment -n kcm-system
   kubectl get cluster -n kcm-system
   
   # Check control plane machines (should create Nutanix VMs)
   kubectl get k0scontrolplane -n kcm-system
   kubectl get machine -n kcm-system
   kubectl get nutanixmachine -n kcm-system
   ```

## What to Look For

### HCP Mode Success Indicators:
- ✅ **k0smotron control plane pods** running in management cluster (`kcm-system` namespace)
- ✅ **NO control plane machines** in workload cluster (machine list only shows workers)
- ✅ **Worker VMs created** on Nutanix and joined to cluster
- ✅ **Cluster accessible** via `clusterctl get kubeconfig`

### Standalone Mode Success Indicators:
- ✅ **Control plane VMs created** on Nutanix (should match `controlPlaneNumber` setting)
- ✅ **Worker VMs created** on Nutanix (should match `workersNumber` setting)
- ✅ **All nodes joined** and showing Ready status
- ✅ **Cluster accessible** via `clusterctl get kubeconfig`

## Differences from Legacy Chart

The new split charts provide several improvements:

### Simplified Configuration
- **No mode switching**: Each chart focuses on one deployment mode
- **No XOR validation**: No need to ensure only one mode is enabled
- **Cleaner values**: Removed mode-specific conditionals

### Better Discoverability
- **Separate provider packs**: HCP and Standalone appear as distinct options in k0rdent/KCM
- **Clear naming**: Chart names directly indicate their purpose
- **Upstream alignment**: Follows the same patterns as Hetzner and KubeVirt providers

### Template References
- **Consistent naming**: Template names follow the same patterns as the legacy chart
- **ClusterClass compatibility**: Existing examples work with minor template name updates

## Troubleshooting

### Common Issues:

1. **Provider pack not found**: 
   - Ensure you installed the correct provider pack (`nutanix-pp-hcp` or `nutanix-pp-standalone`)
   - Check `kubectl get clustertemplate -A` shows the expected template

2. **VM creation failures**: 
   - Verify Prism Central credentials
   - Check image/cluster/subnet names exist
   - Ensure sufficient resources available

3. **Network issues**:
   - Verify `controlPlaneEndpoint.host` is outside DHCP range
   - Check firewall rules allow port 6443
   - Ensure VMs can reach internet for k0s downloads

4. **Join failures**:
   - Check k0s service logs on VMs: `journalctl -u k0s*`
   - Verify control plane endpoint is reachable from workers

### Debug Commands:

```bash
# Cluster status
clusterctl describe cluster <cluster-name> -n kcm-system

# Machine details
kubectl describe machine <machine-name> -n kcm-system
kubectl describe nutanixmachine <machine-name> -n kcm-system

# Control plane status (standalone)
kubectl describe k0scontrolplane <cp-name> -n kcm-system

# Get cluster kubeconfig
clusterctl get kubeconfig <cluster-name> -n kcm-system > cluster.kubeconfig
kubectl --kubeconfig=cluster.kubeconfig get nodes -o wide
```

## Cleanup

```bash
# Delete cluster
kubectl delete clusterdeployment <cluster-name> -n kcm-system

# Wait for cleanup
kubectl get machine -n kcm-system  # Should show no machines

# Verify VMs deleted in Nutanix Prism
```

## Next Steps

After successful smoke testing:

1. **Install CCM/CSI**: Add Nutanix cloud controller manager and CSI driver for full functionality
2. **Production Hardening**: Review security settings, resource limits, backup strategies
3. **Monitoring**: Set up cluster monitoring and alerting
4. **Scaling Tests**: Test horizontal and vertical scaling scenarios

## Migration from Legacy Tests

If you have existing smoke tests using the legacy `nutanix-capx` chart:

1. **Update ClusterDeployment templates**: Change template references from combined chart to split chart names
2. **Remove mode configuration**: No need to set `modes.hcp.enabled` or `modes.standalone.enabled`
3. **Update values files**: Remove mode-specific settings
4. **Use appropriate provider pack**: Install `nutanix-pp-hcp` or `nutanix-pp-standalone` instead of the legacy `nutanix-pp`