# k0rdent/kcm (out-of-tree), KubeVirt Provider

## Install `k0rdent/kcm` into Kubernetes cluster

> Note: for the `KinD` based cluster use [setup script](/scripts/kind.sh), to use image registry proxy `export REGISTRY_PROXY=image.proxy.net`

> Note: if using `cilium` [without `kube-proxy`](https://github.com/cilium/cilium/blob/main/Documentation/network/kubernetes/kubeproxy-free.rst), run `cilium config set bpf-lb-sock-hostns-only true`, or use [Helm chart](https://github.com/cilium/cilium/blob/main/Documentation/network/kubernetes/kubeproxy-free.rst#socket-loadbalancer-bypass-in-pod-namespace) option

```bash
# export KUBECONFIG=/var/lib/k0s/pki/admin.conf

helm install kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.4.0 -n kcm-system --create-namespace \
  --set controller.enableTelemetry=false \
  --set regional.velero.enabled=false
```

## Wait for `Management` object readiness

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Install `KubeVirt` chart

> Note: can also create manifests directly, see `kubevirt-pp` Helm Chart

```bash
helm install kubevirt-pp oci://ghcr.io/k0rdent-oot/oot/charts/kubevirt-pp -n kcm-system --take-ownership
```

## Custom KubeVirt Installation with Overrides

If you need to install KubeVirt with custom configuration overrides, you should install `kubevirt-pp` without the bundled KubeVirt and then install the KubeVirt chart separately.

### Install kubevirt-pp without KubeVirt

```bash
helm install kubevirt-pp oci://ghcr.io/k0rdent-oot/oot/charts/kubevirt-pp -n kcm-system --take-ownership \
  --set kubevirt.enabled=false
```

### Install KubeVirt chart separately with custom overrides

#### Using command line overrides

```bash
helm install kubevirt oci://ghcr.io/k0rdent-oot/oot/charts/kubevirt -n kubevirt --take-ownership --create-namespace \
  --set-string spec.configuration.developerConfiguration.useEmulation=true
```

#### Using values file for complex overrides

```bash
# Create values override file
cat > kubevirt-values.yaml << EOF
kubevirt:
  virtOperator:
    replicas: 1
    env:
      - name: VIRT_OPERATOR_IMAGE
        value: quay.io/kubevirt/virt-operator:v1.6.0
      - name: WATCH_NAMESPACE
        valueFrom:
          fieldRef:
            apiVersion: v1
            fieldPath: metadata.annotations['olm.targetNamespaces']
      - name: KUBEVIRT_VERSION
        value: v1.6.0
      - name: KV_IO_EXTRA_ENV_LAUNCHER_QEMU_TIMEOUT
        value: "9000"
      - name: VIRT_CONTROLLER_IMAGE
        value: ghcr.io/s3rj1k/virt-controller:latest
      - name: VIRT_LAUNCHER_IMAGE
        value: ghcr.io/s3rj1k/virt-launcher:latest
      - name: VIRT_HANDLER_IMAGE
        value: ghcr.io/s3rj1k/virt-handler:latest
      - name: KV_IO_EXTRA_ENV_GOTRACEBACK
        value: all
EOF

# Install with custom values
helm install kubevirt oci://ghcr.io/k0rdent-oot/oot/charts/kubevirt -n kubevirt --take-ownership --create-namespace \
  -f kubevirt-values.yaml
```

> Note: Replace the values with your specific configuration requirements. Refer to the KubeVirt documentation for available configuration options.

## Update `Management` object to enable `KubeVirt` provider

```bash
kubectl patch mgmt kcm \
  --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/providers/-",
      "value": {
        "name": "cluster-api-provider-kubevirt",
        "template": "cluster-api-provider-kubevirt-1-5-0",
      }
    }
  ]'
```

## Wait for `Management`, `KubeVirt` objects readiness

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
kubectl wait -n kubevirt kv kubevirt --for=condition=Available --timeout=10m
```

## [OPTIONAL] Install `KubeVirt` CLI

> Note: needed for manual VM management

```bash
KUBEVIRT_VERSION=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.observedKubeVirtVersion}")
ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/')
sudo curl -L -o /usr/local/bin/virtctl https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-${ARCH}
sudo chmod +x /usr/local/bin/virtctl
```

## Create a `KubeVirt` child cluster

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: kubevirt-config
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/component: "kcm"
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: kubevirt-cluster-identity-cred
  namespace: kcm-system
spec:
  description: KubeVirt credentials
  identityRef:
    apiVersion: v1
    kind: Secret
    name: kubevirt-config
    namespace: kcm-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubevirt-config-resource-template
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/component: "kcm"
  annotations:
    projectsveltos.io/template: "true"
EOF

kubectl apply -f - <<EOF
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: kubevirt-demo
  namespace: kcm-system
spec:
  template: kubevirt-standalone-cp-1-5-0
  credential: kubevirt-cluster-identity-cred
  config:
    controlPlaneNumber: 1
    workersNumber: 1
    controlPlane:
      preStartCommands:
        - passwd -u root
        - echo "root:root" | chpasswd
    worker:
      preStartCommands:
        - passwd -u root
        - echo "root:root" | chpasswd
EOF
```

## Steps to debug child `KubeVirt` cluster deployment:

#### Describe cluster status.

```bash
clusterctl -n kcm-system describe cluster kubevirt-demo
```

#### Get `ClusterDeployment` objects.

```bash
kubectl get cld -A
```

#### Get `Cluster`, `Machine` objects.

```bash
kubectl get cluster,machine -A
```

#### Get `K0sControlPlane`, `KubevirtCluster` objects.

```bash
kubectl get K0sControlPlane,KubevirtCluster -A
```

#### Get `KubeVirt` VM objects.

```bash
kubectl get vm,vmi -A
```

#### Get into the Machine console where `kubevirt-demo-cp-0` is `Machine` name.

```bash
virtctl -n kcm-system console kubevirt-demo-cp-0
```

#### Set console size.

```bash
stty rows 40 cols 1000
```

#### Get child cluster `kubeconfig` where `kubevirt-demo` is the cluster name.

```bash
clusterctl -n kcm-system get kubeconfig kubevirt-demo > kubevirt-demo.kubeconfig
```

##### Note: when using `KinD` you may need to add a route manually.

```bash
ip r replace \
  $(kubectl -n kcm-system get cluster kubevirt-demo -o json | \
    jq -r '.spec.controlPlaneEndpoint.host') \
  via \
  $(docker network inspect -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' kind)
```

#### Test `kubeconfig`.

```bash
kubectl --kubeconfig=kubevirt-demo.kubeconfig get nodes -o wide
```
