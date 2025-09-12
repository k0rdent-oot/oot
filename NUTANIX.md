# k0rdent/kcm (out-of-tree), Nutanix Provider

## Prerequisites

Before deploying Kubernetes clusters on Nutanix using the CAPX provider, ensure the following requirements are met:

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

## Wait for Management object readiness

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Install Nutanix CAPX Provider

```bash
helm install nutanix-capx oci://ghcr.io/k0rdent-oot/oot/charts/nutanix-capx -n kcm-system --take-ownership
```

## Wait for Management object readiness

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Credentials Configuration

There are two options for providing Nutanix credentials to CAPX:

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
            "password": "cluster-specific-password"
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

## Cluster Deployment Modes

This provider supports two deployment modes:

### **Hosted Control Plane (HCP) Mode**
- Uses `K0smotronControlPlaneTemplate` - control plane runs in the management cluster
- Worker nodes run on Nutanix VMs via `NutanixMachineTemplate`
- No control plane VM infrastructure required
- Version upgrades handled via ClusterClass updates

### **Standalone Mode** 
- Uses `K0sControlPlaneTemplate` - control plane runs on Nutanix VMs
- Both control plane and worker nodes use `NutanixMachineTemplate`
- Full VM-based deployment on Nutanix infrastructure
- Traditional k0s cluster architecture

Both modes use CAPI v1beta2 ClusterClass with Template resources for consistent management.

### **Template Resources Created**

The chart creates the following Template resources with deterministic names:

**HCP Mode:**
- `K0smotronControlPlaneTemplate`: `<release-name>-hcp-cp`
- `K0sWorkerConfigTemplate`: `<release-name>-hcp-worker-bootstrap`
- `NutanixMachineTemplate` (workers): `<release-name>-hcp-worker-mt`
- `NutanixCluster`: `<release-name>-cluster`

**Standalone Mode:**
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

## Deploy a Hosted Control Plane (HCP) Cluster

The HCP mode runs the control plane using K0smotronControlPlaneTemplate in the management cluster, while worker nodes run on Nutanix VMs.

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: nutanix-hcp-demo
  namespace: kcm-system
spec:
  template: nutanix-k0s-hcp
  credential: nutanix-cluster-identity-cred  # Only if using per-cluster credentials
  config:
    # Nutanix Infrastructure
    nutanix:
      prismCentral:
        address: "10.1.1.100"
        port: 9440
        insecure: false
        # Uncomment for per-cluster credentials
        # usePerClusterCredential: true
        # credentialSecretName: "nutanix-cluster-creds"
      controlPlaneEndpoint:
        host: "10.1.1.200"  # Static IP outside DHCP range
        port: 6443
    
    # Machine Configuration
    machineDefaults:
      image:
        type: name
        name: "ubuntu-22.04-k0s"
      cluster:
        type: name
        name: "PE-Cluster-01"
      subnets:
        - type: name
          name: "VM-Network"
      bootType: legacy
      vcpusPerSocket: 1
      vcpuSockets: 2
      memorySize: "4Gi" 
      systemDiskSize: "40Gi"
      # project: "k0s-project"
      # additionalCategories: ["k0s", "hcp"]
    
    # Worker-specific overrides
    worker:
      vcpuSockets: 2
      memorySize: "4Gi"
      systemDiskSize: "40Gi"
    
    # k0s Configuration
    k0s:
      version: "v1.29.2+k0s.0"
      worker:
        labels:
          node-role.kubernetes.io/worker: ""
        # taints: []
    
    # Cluster Configuration
    clusterNetwork:
      pods:
        cidrBlocks: ["10.243.0.0/16"]
      services:
        cidrBlocks: ["10.95.0.0/16"]
    
    # Scaling
    workersNumber: 2
EOF
```

## Deploy a Standalone Cluster

The standalone mode runs both control plane and worker nodes on Nutanix VMs using K0sControlPlane.

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: nutanix-standalone-demo
  namespace: kcm-system
spec:
  template: nutanix-k0s-standalone
  credential: nutanix-cluster-identity-cred  # Only if using per-cluster credentials
  config:
    # Nutanix Infrastructure 
    nutanix:
      prismCentral:
        address: "10.1.1.100"
        port: 9440
        insecure: false
        # Uncomment for per-cluster credentials
        # usePerClusterCredential: true
        # credentialSecretName: "nutanix-cluster-creds"
      controlPlaneEndpoint:
        host: "10.1.1.201"  # Static IP outside DHCP range
        port: 6443
    
    # Machine Configuration
    machineDefaults:
      image:
        type: name
        name: "ubuntu-22.04-k0s"
      cluster:
        type: name
        name: "PE-Cluster-01"
      subnets:
        - type: name
          name: "VM-Network"
      bootType: legacy
      vcpusPerSocket: 1
      vcpuSockets: 2
      memorySize: "4Gi"
      systemDiskSize: "40Gi"
      # project: "k0s-project"
      # additionalCategories: ["k0s", "standalone"]
    
    # Control plane specific overrides
    controlPlane:
      vcpuSockets: 4
      memorySize: "8Gi"
      systemDiskSize: "80Gi"
    
    # Worker specific overrides
    worker:
      vcpuSockets: 2
      memorySize: "4Gi"
      systemDiskSize: "40Gi"
    
    # k0s Configuration
    k0s:
      version: "v1.29.2+k0s.0"
      worker:
        labels:
          node-role.kubernetes.io/worker: ""
        # taints: []
    
    # Cluster Configuration
    clusterNetwork:
      pods:
        cidrBlocks: ["10.243.0.0/16"]
      services:
        cidrBlocks: ["10.95.0.0/16"]
    
    # Scaling
    controlPlaneNumber: 3
    workersNumber: 2
EOF
```

## Monitoring Cluster Deployment

### Check cluster status

```bash
kubectl get cld -A
kubectl get cluster -A
clusterctl describe cluster nutanix-hcp-demo -n kcm-system
```

### Monitor machines

```bash
kubectl get machine -A
kubectl get nutanixmachine -A
```

### Check k0s control plane status

```bash
# For HCP mode
kubectl get k0smotroncontrolplane -A

# For standalone mode  
kubectl get k0scontrolplane -A
```

### Get cluster kubeconfig

```bash
# For HCP cluster
clusterctl get kubeconfig nutanix-hcp-demo -n kcm-system > nutanix-hcp.kubeconfig

# For standalone cluster
clusterctl get kubeconfig nutanix-standalone-demo -n kcm-system > nutanix-standalone.kubeconfig
```

### Test cluster access

```bash
kubectl --kubeconfig=./nutanix-hcp.kubeconfig get nodes -o wide
kubectl --kubeconfig=./nutanix-standalone.kubeconfig get nodes -o wide
```

## Advanced Configuration

### Using UUIDs instead of names

```yaml
machineDefaults:
  image:
    type: uuid
    uuid: "550e8400-e29b-41d4-a716-446655440000"
  cluster:
    type: uuid
    uuid: "550e8400-e29b-41d4-a716-446655440001"
  subnets:
    - type: uuid
      uuid: "550e8400-e29b-41d4-a716-446655440002"
```

### Multiple subnets

```yaml
machineDefaults:
  subnets:
    - type: name
      name: "Primary-Network"
    - type: name
      name: "Storage-Network"
```

### Projects and categories

```yaml
machineDefaults:
  project: "k0s-production"
  additionalCategories:
    - "environment:production"
    - "workload:k0s"
    - "managed-by:k0rdent"
```

### Node labels and taints

```yaml
k0s:
  worker:
    labels:
      node-role.kubernetes.io/worker: ""
      nutanix.com/cluster: "pe-cluster-01"
    taints:
      - key: "workload"
        value: "batch"
        effect: "NoSchedule"
```

## Troubleshooting

### Common Issues

#### 1. Control Plane Endpoint Unreachable
- Verify the control plane endpoint IP is accessible from worker nodes
- Check that the IP is not in DHCP range and properly reserved
- Ensure firewall rules allow traffic on port 6443

#### 2. VM Creation Failures
- Check Prism Central credentials are correct
- Verify image name/UUID exists and is accessible
- Ensure cluster name/UUID is correct
- Check subnet name/UUID exists
- Verify sufficient resources (CPU, memory, storage) are available

#### 3. Image Issues
- Ensure the VM image has cloud-init installed and configured
- Verify the image has required packages (SSH, curl, etc.)
- Check image permissions in Nutanix

#### 4. Network Connectivity
- Verify VMs can reach the internet for k0s binary download
- Check DNS resolution is working
- Ensure container registries are accessible

#### 5. k0s Join Issues
- Check if k0s token generation is working in control plane
- Verify worker nodes can reach the control plane endpoint
- Check k0s service logs on worker nodes

### Debugging Commands

#### Check CAPX controller logs
```bash
kubectl logs -n capx-system deployment/capx-controller-manager
```

#### Check cluster-api controller logs
```bash
kubectl logs -n capi-system deployment/capi-controller-manager
```

#### Check k0smotron controller logs (for HCP mode)
```bash
kubectl logs -n k0smotron-system deployment/k0smotron-controller-manager
```

#### Get detailed machine information
```bash
kubectl describe nutanixmachine <machine-name> -n kcm-system
```

#### Check cluster status
```bash
kubectl describe cluster <cluster-name> -n kcm-system
```

### Recovery Procedures

#### Reset a failed cluster deployment
```bash
kubectl delete clusterdeployment <cluster-name> -n kcm-system
# Wait for cleanup, then redeploy
```

#### Force delete stuck machines
```bash
kubectl patch nutanixmachine <machine-name> -p '{"metadata":{"finalizers":null}}' --type=merge -n kcm-system
kubectl delete nutanixmachine <machine-name> -n kcm-system
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
| k0s | v1.29.2+k0s.0 | Configurable via values.yaml |
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

## Security Considerations

- Use dedicated service accounts with minimal required permissions
- Rotate Nutanix credentials regularly
- Use per-cluster credentials for production environments
- Enable TLS verification (set `insecure: false`)
- Implement network segmentation between clusters
- Use Nutanix categories for access control and monitoring
