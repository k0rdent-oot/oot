# k0rdent/kcm (out-of-tree), Hetzner Provider

## Install `k0rdent/kcm` into Kubernetes cluster

```bash
helm install kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.1.1 -n kcm-system --create-namespace \
  --set controller.enableTelemetry=false \
  --set velero.enabled=false
```

## Wait for `Management` object readiness

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Install `Hetzner` chart

> Note: can also create manifests directly, see `hetzner-pp` Helm Chart

```bash
helm install hetzner-pp oci://ghcr.io/k0rdent-oot/oot/charts/hetzner-pp -n kcm-system --take-ownership
```

## Wait for `Management` object readiness

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Create a `Hetzner` child cluster secrets

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: hetzner-config
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/component: "kcm"
stringData:
  hcloud: ***TOKEN***
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: hetzner-cluster-identity-cred
  namespace: kcm-system
spec:
  description: Hetzner credentials
  identityRef:
    apiVersion: v1
    kind: Secret
    name: hetzner-config
    namespace: kcm-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: hetzner-config-resource-template
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/component: "kcm"
  annotations:
    projectsveltos.io/template: "true"
EOF
```

## Create a `Hetzner` child cluster

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: hetzner-demo
  namespace: kcm-system
spec:
  template: hetzner-hask
  credential: hetzner-cluster-identity-cred
  config:
    region: "fsn1"
    ccmVersion: "1.25.1"
    controlPlaneImageName: "ubuntu-24.04"
    controlPlaneServerType: "cpx31"
    controlPlaneNumber: 1
    workerImageName: "ubuntu-24.04"
    workerServerType: "cpx21"
    workerNumber: 1
    k0sVersion: "v1.31.10+k0s.0"
    sshKeyName: "id_ed25519"
    objects:
      - |
        apiVersion: cluster.x-k8s.io/v1beta1
        kind: Cluster
        metadata:
          name: "{{ .Values.cluster.name | default .Release.Name }}"
          namespace: "{{ .Release.Namespace }}"
        spec:
          clusterNetwork:
            pods:
              cidrBlocks:
                - 10.244.0.0/16
          controlPlaneRef:
            apiVersion: controlplane.cluster.x-k8s.io/v1beta1
            kind: K0sControlPlane
            name: '{{ printf "%s-cp" (.Values.cluster.name | default .Release.Name) }}'
            namespace: "{{ .Release.Namespace }}"
          infrastructureRef:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: HetznerCluster
            name: "{{ .Values.cluster.name | default .Release.Name }}"
            namespace: "{{ .Release.Namespace }}"
      - |
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: HetznerCluster
        metadata:
          name: "{{ .Values.cluster.name | default .Release.Name }}"
          namespace: "{{ .Release.Namespace }}"
        spec:
          controlPlaneEndpoint:
            host: ""
            port: 6443
          controlPlaneLoadBalancer:
            region: "{{ .Values.region }}"
          controlPlaneRegions:
            - "{{ .Values.region }}"
          hcloudPlacementGroups:
            - name: control-plane
              type: spread
            - name: worker
              type: spread
          hetznerSecretRef:
            key:
              hcloudToken: hcloud
            name: hetzner-config
          sshKeys:
            hcloud:
              - name: "{{ .Values.sshKeyName }}"
      - |
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: HCloudMachineTemplate
        metadata:
          name: '{{ printf "%s-cp-mt" (.Values.cluster.name | default .Release.Name) }}'
          namespace: "{{ .Release.Namespace }}"
        spec:
          template:
            spec:
              imageName: "{{ .Values.controlPlaneImageName }}"
              placementGroupName: control-plane
              type: "{{ .Values.controlPlaneServerType }}"
      - |
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: HCloudMachineTemplate
        metadata:
          name: '{{ printf "%s-worker-mt" (.Values.cluster.name | default .Release.Name) }}'
          namespace: "{{ .Release.Namespace }}"
        spec:
          template:
            spec:
              imageName: "{{ .Values.workerImageName }}"
              placementGroupName: worker
              type: "{{ .Values.workerServerType }}"
      - |
        apiVersion: controlplane.cluster.x-k8s.io/v1beta1
        kind: K0sControlPlane
        metadata:
          name: '{{ printf "%s-cp" (.Values.cluster.name | default .Release.Name) }}'
          namespace: "{{ .Release.Namespace }}"
        spec:
          replicas: {{ .Values.controlPlaneNumber }}
          version: "{{ .Values.k0sVersion }}"
          k0sConfigSpec:
            files:
              - path: /etc/resolv.conf
                content: |
                  nameserver 1.1.1.1
                  nameserver 1.0.0.1
                  nameserver 2606:4700:4700::1111
                permissions: "0744"
            preStartCommands:
              - systemctl disable --now systemd-resolved
              - systemctl mask --now systemd-resolved
              - sed -i '/swap/d' /etc/fstab
              - swapoff -a
              - snap list | awk '!/^Name|^core|^snapd|^lxd/ {print $1}' | xargs -r snap remove --purge || true
              - snap list | awk '/^lxd/ {print $1}' | xargs -r snap remove --purge || true
              - snap list | awk '/^core/ {print $1}' | xargs -r snap remove --purge || true
              - snap list | awk '/^snapd/ {print $1}' | xargs -r snap remove --purge || true
              - snap list | awk '!/^Name/ {print $1}' | xargs -r snap remove --purge || true
              - apt-get -y remove --purge lxd lxd-agent-loader lxd-installer snapd || true
              - apt-get -y autoremove && apt-get -y clean all
            args:
              - --enable-worker
              - --enable-cloud-provider
              - --kubelet-extra-args="--cloud-provider=external"
              - --disable-components=konnectivity-server
              - --no-taints
            k0s:
              apiVersion: k0s.k0sproject.io/v1beta1
              kind: ClusterConfig
              metadata:
                name: k0s
              spec:
                telemetry:
                  enabled: false
                api:
                  extraArgs:
                    anonymous-auth: "true"
                    kubelet-preferred-address-types: "ExternalIP,Hostname,InternalDNS,ExternalDNS"
                network:
                  provider: calico
                  calico:
                    mode: vxlan
                extensions:
                  helm:
                    repositories:
                      - name: hcloud
                        url: https://charts.hetzner.cloud
                    charts:
                      - name: hccm
                        chartname: hcloud/hcloud-cloud-controller-manager
                        namespace: kube-system
                        version: "{{ .Values.ccmVersion }}"
                        order: 1
                        values: |
                          env:
                            HCLOUD_TOKEN:
                              valueFrom:
                                secretKeyRef:
                                  name: hetzner-config
                                  key: hcloud
          machineTemplate:
            infrastructureRef:
              apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
              kind: HCloudMachineTemplate
              name: '{{ printf "%s-cp-mt" (.Values.cluster.name | default .Release.Name) }}'
              namespace: "{{ .Release.Namespace }}"
      - |
        apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
        kind: K0sWorkerConfigTemplate
        metadata:
          name: '{{ printf "%s-worker-config" (.Values.cluster.name | default .Release.Name) }}'
          namespace: "{{ .Release.Namespace }}"
        spec:
          template:
            spec:
              version: "{{ .Values.k0sVersion }}"
              files:
                - path: /etc/resolv.conf
                  content: |
                    nameserver 1.1.1.1
                    nameserver 1.0.0.1
                    nameserver 2606:4700:4700::1111
                  permissions: "0744"
              preStartCommands:
                - systemctl disable --now systemd-resolved
                - systemctl mask --now systemd-resolved
                - sed -i '/swap/d' /etc/fstab
                - swapoff -a
                - snap list | awk '!/^Name|^core|^snapd|^lxd/ {print $1}' | xargs -r snap remove --purge || true
                - snap list | awk '/^lxd/ {print $1}' | xargs -r snap remove --purge || true
                - snap list | awk '/^core/ {print $1}' | xargs -r snap remove --purge || true
                - snap list | awk '/^snapd/ {print $1}' | xargs -r snap remove --purge || true
                - snap list | awk '!/^Name/ {print $1}' | xargs -r snap remove --purge || true
                - apt-get -y remove --purge lxd lxd-agent-loader lxd-installer snapd || true
                - apt-get -y autoremove && apt-get -y clean all
              args:
                - --enable-cloud-provider
                - --kubelet-extra-args="--cloud-provider=external"
      - |
        apiVersion: cluster.x-k8s.io/v1beta1
        kind: MachineDeployment
        metadata:
          name: '{{ printf "%s-worker" (.Values.cluster.name | default .Release.Name) }}'
          namespace: "{{ .Release.Namespace }}"
          labels:
            nodepool: '{{ printf "%s-worker" (.Values.cluster.name | default .Release.Name) }}'
        spec:
          clusterName: "{{ .Values.cluster.name | default .Release.Name }}"
          replicas: {{ .Values.workerNumber }}
          selector:
            matchLabels:
              cluster.x-k8s.io/cluster-name: "{{ .Values.cluster.name | default .Release.Name }}"
          template:
            metadata:
              labels:
                cluster.x-k8s.io/cluster-name: "{{ .Values.cluster.name | default .Release.Name }}"
                nodepool: '{{ printf "%s-worker" (.Values.cluster.name | default .Release.Name) }}'
            spec:
              version: "{{ regexReplaceAll "\\+k0s.+$" .Values.k0sVersion "" }}"
              clusterName: "{{ .Values.cluster.name | default .Release.Name }}"
              failureDomain: "{{ .Values.region }}"
              bootstrap:
                configRef:
                  apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
                  kind: K0sWorkerConfigTemplate
                  name: '{{ printf "%s-worker-config" (.Values.cluster.name | default .Release.Name) }}'
                  namespace: "{{ .Release.Namespace }}"
              infrastructureRef:
                apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
                kind: HCloudMachineTemplate
                name: '{{ printf "%s-worker-mt" (.Values.cluster.name | default .Release.Name) }}'
                namespace: "{{ .Release.Namespace }}"
EOF
```

## Steps to debug child `Hetzner` cluster deployment:

#### Describe cluster status.

```bash
clusterctl describe cluster hetzner-demo -n kcm-system
```

#### Get `ClusterDeployment` objects.

```bash
kubectl get cld -A
```

#### Get `Machine` object.

```bash
kubectl get machine -A
```

#### Get child cluster `kubeconfig` where `hetzner-demo` is the cluster name.

```bash
clusterctl get kubeconfig hetzner-demo -n kcm-system > hetzner-demo.kubeconfig
```

#### Test `kubeconfig`.

```bash
kubectl --kubeconfig=./hetzner-demo.kubeconfig get nodes -o wide
```
