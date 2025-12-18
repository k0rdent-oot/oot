# k0rdent/kcm (out-of-tree), Hosted Control Plane (Kubeadm) + Tinkerbell

> This guide is designed for VM-based testing using libvirt with sushy-tools (Redfish emulator).

## Prerequisites

### Set up libvirt with sushy-tools

```bash
ansible-pull -U https://github.com/k0rdent-oot/oot.git playbooks/libvirt-sushy.yml
```

After running the playbook:
- Redfish password is saved to `/root/.redfish_password`
- Tinkerbell network (`virbr-tink` bridge, `172.17.1.0/24`) is created and started

### Create VM

```bash
virt-install \
    --name "vm1" \
    --vcpus "6" \
    --ram "6144" \
    --os-variant "debian12" \
    --connect "qemu:///system" \
    --disk "path=/var/lib/libvirt/images/vm1-disk.img,bus=virtio,size=60,sparse=yes" \
    --disk "device=cdrom,bus=sata" \
    --network "bridge:virbr-tink,mac=52:54:00:12:34:01" \
    --console "pty,target.type=virtio" \
    --serial "pty" \
    --graphics "vnc,listen=0.0.0.0" \
    --import \
    --noautoconsole \
    --noreboot \
    --boot "uefi,firmware.feature0.name=enrolled-keys,firmware.feature0.enabled=no,firmware.feature1.name=secure-boot,firmware.feature1.enabled=yes"
```

### Install k3s and Helm

```bash
curl -sfL https://get.k3s.io | sh -s - server --cluster-init \
  --cluster-cidr=172.20.0.0/16 \
  --service-cidr=172.21.0.0/16
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Install `k0rdent/kcm` into Kubernetes cluster

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

helm install kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.6.0 -n kcm-system --create-namespace \
  --set controller.createManagement=false
```

## Install OOT templates

```bash
kubectl apply -f - <<EOF
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: oot-repo
  namespace: kcm-system
  annotations:
    helm.sh/resource-policy: keep
  labels:
    k0rdent.mirantis.com/managed: "true"
spec:
  type: oci
  url: "oci://ghcr.io/k0rdent-oot/oot/charts"
  interval: 10m0s

---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ProviderTemplate
metadata:
  name: cluster-api-provider-tinkerbell-1-1-0
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: cluster-api-provider-tinkerbell
      version: 1.1.0
      interval: 10m0s
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: oot-repo

---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ProviderTemplate
metadata:
  name: cluster-api-provider-kubeadm-1-0-0
  labels:
    k0rdent.mirantis.com/component: kcm
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: cluster-api-provider-kubeadm
      version: 1.0.0
      interval: 10m0s
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: oot-repo

---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ProviderTemplate
metadata:
  name: cluster-api-provider-hosted-control-plane-1-0-0
  labels:
    k0rdent.mirantis.com/component: kcm
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: cluster-api-provider-hosted-control-plane
      version: 1.0.0
      interval: 10m0s
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: oot-repo

---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterTemplate
metadata:
  name: tinkerbell-hcp-kubeadm-1-0-0
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/component: kcm
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: tinkerbell-hcp-kubeadm
      version: 1.0.0
      interval: 10m0s
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: oot-repo

---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplate
metadata:
  name: cilium-cni-1-0-0
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/component: kcm
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: cilium-cni
      version: 1.0.0
      interval: 10m0s
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: oot-repo
EOF
```

## Create`Management` object

```bash
kubectl apply -f - <<EOF
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Management
metadata:
  labels:
    k0rdent.mirantis.com/component: kcm
  name: kcm
spec:
  core:
    capi: {}
    kcm:
      config:
        regional:
          telemetry:
            mode: disabled
          velero:
            enabled: false
  providers:
  - name: projectsveltos
  - config:
      kubeVipCloudProvider:
        enabled: true
      secret:
        create: true
        data:
          TINKERBELL_IP: 172.17.1.1
        name: tinkerbell-provider-config
      tinkerbell:
        artifactsFileServer: http://172.17.1.1:7173
        deployment:
          envs:
            globals:
              logLevel: 3
            rufio:
              metricsAddr: 0.0.0.0:8085
            smee:
              ipxeHttpScriptBindAddr: 172.17.1.1
              isoUpstreamURL: https://github.com/tinkerbell/hook/releases/download/latest/hook-x86_64-efi-initrd.iso
              osieURL: http://172.17.1.1:7171
              syslogBindAddr: 172.17.1.1
              tftpServerBindAddr: 172.17.1.1
            tinkController:
              metricsAddr: 0.0.0.0:8084
            tinkServer:
              bindAddr: 172.17.1.1
            tootles:
              bindAddr: 172.17.1.1
          hostNetwork: true
          init:
            sourceInterface: virbr-tink
        enabled: true
        optional:
          hookos:
            enabled: true
        publicIP: 172.17.1.1
        trustedProxies:
        - 10.244.0.0/16
    name: cluster-api-provider-tinkerbell
    template: cluster-api-provider-tinkerbell-1-1-0
  - name: cluster-api-provider-hosted-control-plane
    template: cluster-api-provider-hosted-control-plane-1-0-0
  - name: cluster-api-provider-kubeadm
    template: cluster-api-provider-kubeadm-1-0-0
  release: kcm-1-6-0
EOF
```

## Wait for `Management` objects readiness

```bash
kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Prepare Hardware Resources

### Create BMC Secret

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: vm1-bmc
  namespace: kcm-system
type: Opaque
stringData:
  username: admin
  password: "$(cat /root/.redfish_password)"
EOF
```

### Create BMC Machine Object

```bash
kubectl apply -f - <<EOF
---
apiVersion: bmc.tinkerbell.org/v1alpha1
kind: Machine
metadata:
  name: vm1
  namespace: kcm-system
spec:
  connection:
    host: 172.17.1.1
    port: 623
    insecureTLS: true
    authSecretRef:
      name: vm1-bmc
      namespace: kcm-system
    providerOptions:
      preferredOrder:
        - gofish
        - ipmitool
      redfish:
        port: 8000
        systemName: vm1
        useBasicAuth: true
      ipmitool:
        port: 623
        cipherSuite: "3"
EOF
```

> Note: `systemName` must match the libvirt VM domain name.

### Create Hardware Object

```bash
kubectl apply -f - <<EOF
---
apiVersion: tinkerbell.org/v1alpha1
kind: Hardware
metadata:
  name: vm1
  namespace: kcm-system
  labels:
    tinkerbell.org/role: worker
spec:
  bmcRef:
    apiGroup: bmc.tinkerbell.org
    kind: Machine
    name: vm1
  disks:
    - device: /dev/vda
  interfaces:
    - dhcp:
        arch: x86_64
        hostname: vm1
        mac: "52:54:00:12:34:01"
        ip:
          address: 172.17.1.101
          gateway: 172.17.1.1
          netmask: 255.255.255.0
        name_servers:
          - 8.8.8.8
        lease_time: 4294967294
        uefi: true
      netboot:
        allowPXE: true
        allowWorkflow: true
  metadata:
    instance:
      hostname: vm1
      id: "52:54:00:12:34:01"
      operating_system:
        distro: debian
        version: "13"
EOF
```

> Note:
> - Set `tinkerbell.org/role: worker` label for worker nodes
> - Use `/dev/vda` for virtio disks (VMs), `/dev/sda` for SATA/SCSI (bare-metal)
> - Replace MAC addresses and IP addresses with your actual VM values

### Create `Credential`

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: tinkerbell-cluster-identity
  namespace: kcm-system
type: Opaque

---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: tinkerbell-cluster-identity-cred
  namespace: kcm-system
spec:
  description: Tinkerbell cluster identity
  identityRef:
    apiVersion: v1
    kind: Secret
    name: tinkerbell-cluster-identity
    namespace: kcm-system
EOF
```

## Create a `Tinkerbell` child cluster

```bash
kubectl apply -f - <<EOF
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: tinkerbell-hcp-demo
  namespace: kcm-system
spec:
  template: tinkerbell-hcp-kubeadm-1-0-0
  credential: tinkerbell-cluster-identity-cred
  config:
    workersNumber: 1
    kubernetes:
      version: v1.34.2
    clusterNetwork:
      pods:
        cidrBlocks:
          - 192.168.0.0/18
      services:
        cidrBlocks:
          - 10.96.0.0/12
    gateway:
      gatewayClass:
        create: true
        name: envoy
        controllerName: gateway.envoyproxy.io/gatewayclass-controller
      create: true
      name: capi
      hostname: "*.172.17.1.200.nip.io"
      addresses:
        - type: IPAddress
          value: "172.17.1.200"
      port: 443
      protocol: TLS
      tlsMode: Passthrough
      envoyProxy:
        create: true
        loadBalancerIP: "172.17.1.200"
    hostedControlPlane:
      replicas: 1
      deployment:
        controllerManager:
          args:
            allocate-node-cidrs: "true"
      konnectivityClient:
        replicas: 1
      kubeProxy:
        enabled: true
      coredns:
        enabled: true
    kubeVipIPPool:
      enabled: true
      range: "172.17.1.201-172.17.1.250"
    tinkerbell:
      imageLookup:
        format: "{{.BaseRegistry}}/{{.OSDistro}}-{{.OSVersion}}:{{.KubernetesVersion}}.gz"
        baseRegistry: ghcr.io/s3rj1k/playground
        osDistro: ubuntu
        osVersion: "2404"
    worker:
      bootMode: customboot
      custombootConfig:
        preparingActions:
          - powerAction: "off"
          - bootDevice:
              device: "pxe"
              efiBoot: true
          - powerAction: "on"
        postActions:
          - powerAction: "off"
          - bootDevice:
              device: "disk"
              persistent: true
              efiBoot: true
          - powerAction: "on"
      hardwareAffinity:
        matchLabels:
          tinkerbell.org/role: worker
      templateOverride: |
        version: "0.1"
        name: hcp-worker
        global_timeout: 9000
        tasks:
          - name: "hcp-worker"
            worker: "{{.device_1}}"
            volumes:
              - /dev:/dev
              - /dev/console:/dev/console
              - /lib/firmware:/lib/firmware:ro
            actions:
              - name: "Stream Ubuntu Image"
                image: quay.io/tinkerbell/actions/oci2disk:latest
                timeout: 3000
                environment:
                  DEST_DISK: {{ index .Hardware.Disks 0 }}
                  IMG_URL: ghcr.io/s3rj1k/playground/ubuntu-2404:v1.34.2.gz
                  COMPRESSED: true
              - name: "Sync and Grow Partition"
                image: quay.io/tinkerbell/actions/cexec:latest
                timeout: 90
                environment:
                  BLOCK_DEVICE: {{ index .Hardware.Disks 0 }}3
                  FS_TYPE: ext4
                  CHROOT: y
                  DEFAULT_INTERPRETER: "/bin/sh -c"
                  CMD_LINE: "sync && growpart {{ index .Hardware.Disks 0 }} 3 && resize2fs {{ index .Hardware.Disks 0 }}3 && sync"
              - name: "Add Tink Cloud-Init Config"
                image: quay.io/tinkerbell/actions/writefile:latest
                timeout: 90
                environment:
                  DEST_DISK: {{ formatPartition ( index .Hardware.Disks 0 ) 3 }}
                  FS_TYPE: ext4
                  DEST_PATH: /etc/cloud/cloud.cfg.d/10_tinkerbell.cfg
                  UID: 0
                  GID: 0
                  MODE: 0600
                  DIRMODE: 0700
                  CONTENTS: |
                    datasource:
                      Ec2:
                        metadata_urls: ["http://172.17.1.1:7172"]
                        strict_id: false
                    system_info:
                      default_user:
                        name: tink
                        plain_text_passwd: tink
                        lock_passwd: false
                        groups: [wheel, adm, sudo]
                        sudo: ["ALL=(ALL) NOPASSWD:ALL"]
                        shell: /bin/bash
                    ssh_pwauth: true
                    manage_etc_hosts: localhost
                    warnings:
                      dsid_missing_source: off
              - name: "Add Cloud-Init DS-Identity"
                image: quay.io/tinkerbell/actions/writefile:latest
                timeout: 90
                environment:
                  DEST_DISK: {{ formatPartition ( index .Hardware.Disks 0 ) 3 }}
                  FS_TYPE: ext4
                  DEST_PATH: /etc/cloud/ds-identify.cfg
                  UID: 0
                  GID: 0
                  MODE: 0600
                  DIRMODE: 0700
                  CONTENTS: |
                    datasource: Ec2
              - name: "Shutdown host"
                image: ghcr.io/jacobweinstock/waitdaemon:latest
                timeout: 90
                pid: host
                command: ["poweroff"]
                environment:
                  IMAGE: alpine
                  WAIT_SECONDS: 10
                volumes:
                  - /var/run/docker.sock:/var/run/docker.sock
    kubeadm:
      preKubeadmCommands:
        - systemctl enable --now containerd
        - sleep 10
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            provider-id: "tinkerbell://kcm-system/{{ ds.meta_data.hostname }}"
  serviceSpec:
    services:
      - template: cilium-cni-1-0-0
        name: cilium
        namespace: kube-system
        values: |
          cilium:
            k8sServiceHost: tinkerbell-hcp-demo.kcm-system.172.17.1.200.nip.io
            k8sServicePort: 443
EOF
```

## Watch Kubernetes objects

```bash
watch kubectl get cld,HostedControlPlane,tinkerbellmachine,workflow -A
```

## Extract child cluster kubeconfig

Once the cluster deployment is ready, you can extract the kubeconfig to access the child cluster:

```bash
kubectl -n kcm-system get secret tinkerbell-hcp-demo-kubeconfig -o jsonpath='{.data.value}' | base64 -d > tinkerbell-hcp-demo.kubeconfig
```

Test connectivity to the child cluster:

```bash
kubectl --kubeconfig=tinkerbell-hcp-demo.kubeconfig get nodes -o wide
```

## References

- [HCP Provider](https://github.com/teutonet/cluster-api-provider-hosted-control-plane)
- [Tinkerbell Actions](https://github.com/tinkerbell/actions)
- [HookOS Releases](https://github.com/tinkerbell/hook/releases)
- [Sushy Tools](https://docs.openstack.org/sushy-tools/)
