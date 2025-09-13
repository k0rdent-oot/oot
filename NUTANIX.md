# k0rdent/kcm (out-of-tree), Nutanix Provider

The Nutanix provider for k0rdent enables deployment of Kubernetes clusters on Nutanix infrastructure using Cluster API Provider Nutanix (CAPX). This provider supports two deployment modes:

- **🏗️ Hosted Control Plane (HCP)**: Control plane runs as pods in the management cluster using k0smotron
- **🖥️ Standalone**: Control plane runs on dedicated Nutanix VMs

## Chart Selection Guide

Choose the appropriate chart based on your deployment requirements:

| Mode | Chart | Provider Pack | Use Case | When to Choose |
|------|-------|---------------|----------|----------------|
| **🏗️ HCP** | [`nutanix-capx-hcp`](charts/nutanix-capx-hcp/) | [`nutanix-pp-hcp`](charts/nutanix-pp-hcp/) | Managed control plane, faster scaling, shared management | ✅ **Development/Testing**<br/>✅ **Multi-tenant environments**<br/>✅ **Fast worker scaling needs**<br/>✅ **Minimal VM resource usage** |
| **🖥️ Standalone** | [`nutanix-capx-standalone`](charts/nutanix-capx-standalone/) | [`nutanix-pp-standalone`](charts/nutanix-pp-standalone/) | Full VM-based cluster, traditional deployment | ✅ **Production workloads**<br/>✅ **Network isolation requirements**<br/>✅ **Traditional k8s cluster model**<br/>✅ **Full control over control plane** |

### Decision Matrix

**Choose HCP when:**
- Control plane pods in management cluster are acceptable
- You need fast worker node scaling (no VM boot time for CP)
- Resource efficiency is important (shared CP overhead)
- You're running development/testing workloads

**Choose Standalone when:**
- You need complete cluster isolation (including control plane)
- Network policies require VM-to-VM control plane communication
- Production workloads require traditional cluster architecture
- You want full control over control plane sizing and placement

> **⚠️ Important**: The combined `nutanix-capx` chart is deprecated. Use the dedicated charts above for new deployments.

> **💡 Migration**: See the [Migration Guide](#migration-from-legacy-chart) below for moving from the legacy combined chart.

## Prerequisites

Before deploying Kubernetes clusters on Nutanix, ensure the following requirements are met:

### Nutanix Infrastructure
- **Prism Central**: Accessible endpoint with administrative privileges
- **Prism Element Cluster**: At least one PE cluster registered with Prism Central
- **VM Images**: Ubuntu/CentOS images prepared with cloud-init and k0s requirements
- **Networking**: VLAN/subnet configured with DHCP (optional) or static IP allocation
- **Storage**: Sufficient storage capacity for VM disks
- **Projects** (optional): Nutanix projects for resource organization
- **Categories** (optional): Nutanix categories for VM tagging

### Image Requirements
The VM images should include:
- Cloud-init package installed and configured
- SSH server enabled
- Container runtime prerequisites (kernel modules, etc.)
- Network tools (curl, wget, etc.)

### Network Considerations
- **Control Plane Endpoint**: Reserve a static IP outside DHCP/IPAM range for the control plane endpoint
- **Load Balancer**: Ensure the control plane endpoint IP can reach all control plane nodes
- **Outbound Access**: VMs need internet access for k0s binary download and container image pulls

## Install k0rdent/kcm into Kubernetes cluster

```bash
helm install kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.2.0 -n kcm-system --create-namespace \
  --set controller.enableTelemetry=false \
  --set velero.enabled=false
```

Wait for management object readiness:

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Credentials Configuration

There are three options for providing Nutanix credentials to CAPX:

### Option 1: Global Credentials (Recommended)

Create a global credential secret that will be used by all clusters. This is auto-injected by CAPX:

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

### Option 2: Per-Cluster Credentials

Create a credential secret for each cluster deployment and configure the chart to use it:

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

**To use per-cluster credentials**, set these values in your deployment:

```yaml
nutanix:
  prismCentral:
    usePerClusterCredential: true
    credentialSecretName: "nutanix-cluster-creds"
```

### Option 3: Additional Trust Bundle (for Custom CA)

If using custom CA certificates for Prism Central:

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nutanix-ca-bundle
  namespace: kcm-system
data:
  ca-bundle.crt: |
    -----BEGIN CERTIFICATE-----
    # Your custom CA certificate here
    -----END CERTIFICATE-----
EOF
```

Then configure:

```yaml
nutanix:
  prismCentral:
    additionalTrustBundleConfigMapName: "nutanix-ca-bundle"
```

## 🏗️ Hosted Control Plane (HCP) Deployment

The HCP mode runs the control plane using k0smotron in the management cluster, while worker nodes run on Nutanix VMs.

### Install Provider Pack

```bash
helm install nutanix-pp-hcp oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-pp-hcp -n kcm-system --take-ownership
```

Wait for readiness:

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

### Deploy HCP Cluster

Create a cluster configuration file:

```yaml
# hcp-cluster.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: nutanix-hcp-cluster
  namespace: kcm-system
spec:
  template: nutanix-k0s-hcp-0-1-0  # Matches the provider pack version
  config:
    # Nutanix infrastructure settings
    nutanix:
      prismCentral:
        address: "10.1.1.100"         # Your Prism Central IP
        port: 9440
        insecure: false
        # usePerClusterCredential: true  # Uncomment if using per-cluster creds
      
      controlPlaneEndpoint:
        host: "10.1.1.200"            # VIP outside DHCP range
        port: 6443

    # Machine configuration
    machineDefaults:
      image:
        type: name
        name: "ubuntu-22.04-k0s"      # Your prepared image
      cluster:
        type: name
        name: "PE-Cluster-01"         # Your Prism Element cluster
      subnets:
        - type: name
          name: "VM-Network"          # Your network subnet
      bootType: legacy
      vcpusPerSocket: 1
      vcpuSockets: 2
      memorySize: "4Gi"
      systemDiskSize: "40Gi"

    # Worker node configuration
    worker:
      vcpuSockets: 2
      memorySize: "4Gi"
      systemDiskSize: "40Gi"

    # k0s configuration
    k0s:
      version: "v1.29.2+k0s.0"
      worker:
        labels:
          node-role.kubernetes.io/worker: ""

    # Cluster networking
    clusterNetwork:
      pods:
        cidrBlocks: ["10.243.0.0/16"]
      services:
        cidrBlocks: ["10.95.0.0/16"]

    # Scaling
    workersNumber: 2
```

Deploy the cluster:

```bash
kubectl apply -f hcp-cluster.yaml
```

### Monitor HCP Deployment

```bash
# Check cluster deployment status
kubectl get clusterdeployment -n kcm-system

# Check worker machines (no control plane machines in HCP mode)
kubectl get machine -n kcm-system

# Check k0smotron control plane pods in management cluster
kubectl get pods -n kcm-system | grep k0smotron
```

## 🖥️ Standalone Deployment

The Standalone mode runs both control plane and worker nodes on Nutanix VMs.

### Install Provider Pack

```bash
helm install nutanix-pp-standalone oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-pp-standalone -n kcm-system --take-ownership
```

Wait for readiness:

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

### Deploy Standalone Cluster

Create a cluster configuration file:

```yaml
# standalone-cluster.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: nutanix-standalone-cluster
  namespace: kcm-system
spec:
  template: nutanix-k0s-standalone-0-1-0  # Matches the provider pack version
  config:
    # Nutanix infrastructure settings
    nutanix:
      prismCentral:
        address: "10.1.1.100"         # Your Prism Central IP
        port: 9440
        insecure: false
      
      controlPlaneEndpoint:
        host: "10.1.1.201"            # Different VIP from HCP
        port: 6443

    # Machine configuration
    machineDefaults:
      image:
        type: name
        name: "ubuntu-22.04-k0s"      # Your prepared image
      cluster:
        type: name
        name: "PE-Cluster-01"         # Your Prism Element cluster
      subnets:
        - type: name
          name: "VM-Network"          # Your network subnet
      bootType: legacy
      vcpusPerSocket: 1
      vcpuSockets: 2
      memorySize: "4Gi"
      systemDiskSize: "40Gi"

    # Control plane configuration
    controlPlane:
      vcpuSockets: 4
      memorySize: "8Gi"
      systemDiskSize: "80Gi"

    # Worker node configuration
    worker:
      vcpuSockets: 2
      memorySize: "4Gi"
      systemDiskSize: "40Gi"

    # k0s configuration
    k0s:
      version: "v1.29.2+k0s.0"
      controlPlane:
        replicas: 3
      worker:
        labels:
          node-role.kubernetes.io/worker: ""

    # Cluster networking
    clusterNetwork:
      pods:
        cidrBlocks: ["10.243.0.0/16"]
      services:
        cidrBlocks: ["10.95.0.0/16"]

    # Scaling
    controlPlaneNumber: 3
    workersNumber: 2
```

Deploy the cluster:

```bash
kubectl apply -f standalone-cluster.yaml
```

### Monitor Standalone Deployment

```bash
# Check cluster deployment status
kubectl get clusterdeployment -n kcm-system

# Check all machines (both control plane and workers)
kubectl get machine -n kcm-system

# Check k0s control plane
kubectl get k0scontrolplane -n kcm-system
```

## Template Resources Created

Each chart creates deterministic template names for ClusterClass references:

### HCP Templates:
- `K0smotronControlPlaneTemplate`: `<release-name>-hcp-cp`
- `K0sWorkerConfigTemplate`: `<release-name>-hcp-worker-bootstrap` 
- `NutanixMachineTemplate` (workers): `<release-name>-hcp-worker-mt`
- `NutanixCluster`: `<release-name>-cluster`

### Standalone Templates:
- `K0sControlPlaneTemplate`: `<release-name>-standalone-cp`
- `NutanixMachineTemplate` (control plane): `<release-name>-standalone-cp-mt`
- `K0sWorkerConfigTemplate`: `<release-name>-standalone-worker-bootstrap`
- `NutanixMachineTemplate` (workers): `<release-name>-standalone-worker-mt`
- `NutanixCluster`: `<release-name>-cluster`

ClusterClasses reference these templates via `templateRef.name` (not `ref`), following CAPI v1beta2 best practices.

### **Object Graph per Mode**

**HCP Mode Resources Created:**
- `ClusterClass` (nutanix-k0s-hcp)
- `K0smotronControlPlaneTemplate` (hosted control plane)
- `K0sWorkerConfigTemplate` (worker bootstrap)
- `NutanixMachineTemplate` (worker VMs only)
- `NutanixCluster` (cluster infrastructure)
- `ProviderTemplate` + `ProviderInterface` (CAPX installation)

**Standalone Mode Resources Created:**
- `ClusterClass` (nutanix-k0s-standalone)
- `K0sControlPlaneTemplate` (VM-based control plane)
- `NutanixMachineTemplate` (control plane VMs)
- `K0sWorkerConfigTemplate` (worker bootstrap)
- `NutanixMachineTemplate` (worker VMs)
- `NutanixCluster` (cluster infrastructure)
- `ProviderTemplate` + `ProviderInterface` (CAPX installation)

**⚠️ Important:** The `controlPlaneEndpoint.host` must be reachable from all nodes and **must not collide with DHCP/IPAM pools**. Reserve this IP outside your Nutanix IPAM range.

## Getting Cluster Access

Once the cluster is deployed, retrieve the kubeconfig:

```bash
# Get cluster kubeconfig
clusterctl get kubeconfig <cluster-name> -n kcm-system > cluster.kubeconfig

# Check cluster nodes
kubectl --kubeconfig=cluster.kubeconfig get nodes -o wide

# Check cluster status
kubectl --kubeconfig=cluster.kubeconfig cluster-info
```

## Nutanix Cloud Controller Manager (CCM) and CSI Driver

**⚠️ Don't Forget:** After cluster deployment, you **must** install Nutanix-specific components for full functionality:

### CCM for Load Balancer Services
The Nutanix CCM provides load balancer integration for Kubernetes services and enables proper node management.

### CSI Driver for Persistent Volumes
The Nutanix CSI driver enables dynamic provisioning of persistent volumes backed by Nutanix storage.

### Installation Options

**Option 1: Via k0s configuration in ClusterDeployment**
Add to your ClusterDeployment spec.config:

```yaml
k0s:
  config:
    spec:
      extensions:
        helm:
          repositories:
            - name: nutanix
              url: https://nutanix.github.io/helm/
          charts:
            - name: nutanix-csi-storage
              chartname: nutanix/nutanix-csi-storage
              namespace: ntnx-system
              version: "3.0.0"
            - name: nutanix-cloud-controller-manager
              chartname: nutanix/nutanix-cloud-controller-manager  
              namespace: kube-system
              version: "0.3.0"
```

**Option 2: Post-deployment via Helm**
```bash
helm repo add nutanix https://nutanix.github.io/helm/
helm install nutanix-csi nutanix/nutanix-csi-storage -n ntnx-system --create-namespace
helm install nutanix-ccm nutanix/nutanix-cloud-controller-manager -n kube-system
```

These components can also be installed via ServiceTemplate resources for consistent management.

## Version Compatibility

### Known Good Versions (Tested in CI)

| Component | Version | Notes |
|-----------|---------|-------|
| CAPI Core | v1.8.4 | Required for v1beta2 ClusterClass support |
| CAPX | v1.7.0 | Nutanix infrastructure provider |
| k0smotron | v1.0.6 | For K0smotronControlPlaneTemplate support |
| k0s | v1.33.4+k0s.0 | Configurable via values.yaml |
| Kubernetes | v1.29.x | Cluster version (derived from k0s) |

**Use these versions together; mixing other minors may work but is not tested by this chart's CI.**

### Template API Versions Used

- ClusterClass: `cluster.x-k8s.io/v1beta2`
- K0smotronControlPlaneTemplate: `controlplane.cluster.x-k8s.io/v1beta1`
- K0sControlPlaneTemplate: `controlplane.cluster.x-k8s.io/v1beta1`
- K0sWorkerConfigTemplate: `bootstrap.cluster.x-k8s.io/v1beta1`
- NutanixMachineTemplate: `infrastructure.cluster.x-k8s.io/v1beta1`
- NutanixCluster: `infrastructure.cluster.x-k8s.io/v1beta1`

Always check the [CAPX compatibility matrix](https://github.com/nutanix-cloud-native/cluster-api-provider-nutanix/blob/main/docs/compatibility.md) for the latest supported versions.

## Migration from Legacy Chart

If you're currently using the deprecated `nutanix-capx` chart, here's how to migrate:

### Migration Steps

1. **Determine your mode**: Check your current values to see if you're using HCP or Standalone mode
2. **Choose new chart**: Select `nutanix-capx-hcp` or `nutanix-capx-standalone`
3. **Update values**: Map your configuration to the new chart format
4. **Deploy new provider pack**: Install the appropriate provider pack
5. **Deploy with new chart**: Create clusters using the new dedicated charts

### Values Mapping

| Legacy Chart Setting | HCP Chart | Standalone Chart |
|---------------------|-----------|------------------|
| `modes.hcp.enabled: true` | ✅ Default behavior | ❌ N/A |
| `modes.standalone.enabled: true` | ❌ N/A | ✅ Default behavior |
| `class.name.hcp` | `class.name` | ❌ N/A |
| `class.name.standalone` | ❌ N/A | `class.name` |
| `controlPlane.*` | ❌ N/A (no CP VMs) | ✅ Same |
| `worker.*` | ✅ Same | ✅ Same |
| `k0s.controlPlane.*` | ❌ N/A | ✅ Same |

### Legacy Chart Commands

```bash
# OLD (deprecated)
helm install nutanix-capx oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-capx

# NEW (recommended)
# For HCP:
helm install nutanix-pp-hcp oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-pp-hcp

# For Standalone:
helm install nutanix-pp-standalone oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-pp-standalone
```

## Troubleshooting

### Common Issues

1. **VM creation failures**: 
   - Verify Prism Central credentials
   - Check image/cluster/subnet names exist
   - Ensure sufficient resources available

2. **Network issues**:
   - Verify `controlPlaneEndpoint.host` is outside DHCP range
   - Check firewall rules allow port 6443
   - Ensure VMs can reach internet for k0s downloads

3. **Join failures**:
   - Check k0s service logs on VMs: `journalctl -u k0s*`
   - Verify control plane endpoint is reachable from workers

4. **Provider pack not found**:
   - Ensure the correct provider pack is installed for your mode
   - Check `kubectl get clustertemplate -A` for available templates

### Debug Commands

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

### Cleanup

```bash
# Delete cluster
kubectl delete clusterdeployment <cluster-name> -n kcm-system

# Wait for cleanup
kubectl get machine -n kcm-system  # Should show no machines

# Verify VMs deleted in Nutanix Prism
```

## Security Considerations

- Use dedicated service accounts with minimal required permissions
- Rotate Nutanix credentials regularly
- Enable TLS verification (`insecure: false`) in production
- Use network policies to restrict cluster communication
- Regular security updates for VM images