# k0rdent/kcm (out-of-tree), Remote cluster

## Install `k0rdent/kcm` into Kubernetes cluster

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

## Install Remote provider

```bash
kubectl create -f - <<EOF
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: oot-repo
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/managed: "true"
  annotations:
    helm.sh/resource-policy: keep
spec:
  type: oci
  url: "oci://ghcr.io/k0rdent-oot/oot/charts"
  interval: 10m0s

---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterTemplate
metadata:
  name: remote-cluster-standalone-cp-1.1.1
  namespace: kcm-system
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: remote-cluster-standalone-cp
      version: 1.1.1
      interval: 10m0s
      sourceRef:
        kind: HelmRepository
        name: oot-repo
EOF
```

## Optionally use custom `k0smotron` `ProviderTemplate`

```bash
kubectl create -f - <<EOF
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ProviderTemplate
metadata:
  annotations:
    helm.sh/resource-policy: keep
  labels:
    k0rdent.mirantis.com/component: kcm
  name: cluster-api-provider-k0sproject-k0smotron
spec:
  helm:
    chartSpec:
      chart: cluster-api-provider-k0sproject-k0smotron
      interval: 10m0s
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: oot-repo
      version: 9999.42.0
EOF

kubectl patch management kcm --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/providers",
    "value": [
      {
        "name": "cluster-api-provider-k0sproject-k0smotron",
        "template": "cluster-api-provider-k0sproject-k0smotron"
      },
      {
        "name": "projectsveltos"
      }
    ]
  }
]'
```

## Wait for `Management` object readiness

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Create SSH Key for Nodes

```bash
ssh-keygen -t ed25519 -f /tmp/id_ed25519 -N ""

kubectl -n kcm-system create secret generic remote-machine-ssh \
--from-file=value=/tmp/id_ed25519 \
--from-file=public-key=/tmp/id_ed25519.pub
```

> Note: put generated public key into Nodes manualy

## Create `Remote` child cluster

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: remote-config
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/component: "kcm"
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: remote-cluster-identity-cred
  namespace: kcm-system
spec:
  description: KubeVirt credentials
  identityRef:
    apiVersion: v1
    kind: Secret
    name: remote-config
    namespace: kcm-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: remote-config-resource-template
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
  name: remote-cluster-standalone-demo
  namespace: kcm-system
spec:
  template: remote-cluster-standalone-cp-1.1.1
  credential: remote-cluster-identity-cred
  config:
    clusterNetwork:
      apiServerHost: 10.42.71.102
    controlPlaneNumber: 1
    workersNumber: 1
    # See https://docs.k0smotron.io/stable/resource-reference/infrastructure.cluster.x-k8s.io-v1beta1/#pooledremotemachinespecmachine
    remoteMachines:
      controlPlane:
        - name: cp-1
          address: 10.42.71.102
          sshKeyRef:
            name: remote-machine-ssh
      worker:
        - name: worker-1
          address: 10.42.71.103
          sshKeyRef:
            name: remote-machine-ssh
EOF
```

## Steps to debug child cluster deployment:

### Describe cluster status.

```bash
clusterctl describe cluster remote-cluster-standalone-demo -n kcm-system
```

### Get `ClusterDeployment` objects.

```bash
kubectl get cld -A
```

### Get `Machine` object.

```bash
kubectl get machine -A
```

### Get child cluster `kubeconfig` where `remote-cluster-standalone-demo` is the cluster name.

```bash
clusterctl get kubeconfig remote-cluster-standalone-demo -n kcm-system > remote-cluster-standalone-demo.kubeconfig
```

### Test `kubeconfig`.

```bash
kubectl --kubeconfig=remote-cluster-standalone-demo.kubeconfig get nodes -o wide
```
