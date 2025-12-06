# k0rdent/kcm (out-of-tree), Tinkerbell Provider

> This guide is designed for VM-based testing using libvirt with sushy-tools (Redfish emulator).

## Prerequisites

### Set up libvirt with sushy-tools

Set up the libvirt environment with sushy-tools Redfish emulator:

```bash
ansible-playbook playbooks/libvirt-sushy.yml
# or using ansible-pull from remote repository
ansible-pull -U https://github.com/k0rdent-oot/oot.git playbooks/libvirt-sushy.yml
```

After running the playbook:
- Redfish password is saved to `/root/.redfish_password`
- Tinkerbell network (`virbr-tink` bridge, `172.17.1.0/24`) is created and started

### Create VMs

Create VMs for testing:

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

virt-install \
    --name "vm2" \
    --vcpus "6" \
    --ram "6144" \
    --os-variant "debian12" \
    --connect "qemu:///system" \
    --disk "path=/var/lib/libvirt/images/vm2-disk.img,bus=virtio,size=60,sparse=yes" \
    --disk "device=cdrom,bus=sata" \
    --network "bridge:virbr-tink,mac=52:54:00:12:34:02" \
    --console "pty,target.type=virtio" \
    --serial "pty" \
    --graphics "vnc,listen=0.0.0.0" \
    --import \
    --noautoconsole \
    --noreboot \
    --boot "uefi,firmware.feature0.name=enrolled-keys,firmware.feature0.enabled=no,firmware.feature1.name=secure-boot,firmware.feature1.enabled=yes"
```

### Install k0s and Helm

```bash
curl -sSfL https://get.k0s.sh | sudo sh

k0s install controller \
    --enable-dynamic-config \
    --disable-components=konnectivity-server \
    --enable-worker \
    --no-taints \
    --kubelet-root-dir=/var/lib/kubelet \
    --verbose

systemctl enable --now k0scontroller

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Install `k0rdent/kcm` into Kubernetes cluster

```bash
export KUBECONFIG=/var/lib/k0s/pki/admin.conf

helm install kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.5.0 -n kcm-system --create-namespace \
  --set regional.telemetry.mode=disabled \
  --set regional.velero.enabled=false
```

## Wait for `Management` object readiness

```bash
k0s kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Install `Tinkerbell` provider objects

```bash
k0s kubectl apply -f - <<EOF
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
  name: cluster-api-provider-tinkerbell-1-0-0
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: cluster-api-provider-tinkerbell
      version: 1.0.0
      interval: 10m0s
      sourceRef:
        kind: HelmRepository
        name: oot-repo

---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterTemplate
metadata:
  name: tinkerbell-standalone-cp-0-1-0
  namespace: kcm-system
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: tinkerbell-standalone-cp
      version: 0.1.0
      interval: 10m0s
      sourceRef:
        kind: HelmRepository
        name: oot-repo
EOF
```

## Update `Management` object to enable `Tinkerbell` provider

```bash
k0s kubectl patch mgmt kcm \
  --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/providers/-",
      "value": {
        "name": "cluster-api-provider-tinkerbell",
        "template": "cluster-api-provider-tinkerbell-1-0-0",
        "config": {
          "secret": {
            "create": true,
            "name": "tinkerbell-provider-config",
            "data": {
              "TINKERBELL_IP": "172.17.1.1"
            }
          },
          "tinkerbell": {
            "enabled": true,
            "publicIP": "172.17.1.1",
            "artifactsFileServer": "http://172.17.1.1:7173",
            "trustedProxies": ["10.244.0.0/16"],
            "optional": {
              "hookos": {
                "enabled": true
              }
            },
            "deployment": {
              "hostNetwork": true,
              "init": {
                "sourceInterface": "virbr-tink"
              },
              "envs": {
                "smee": {
                  "isoUpstreamURL": "https://github.com/tinkerbell/hook/releases/download/latest/hook-x86_64-efi-initrd.iso",
                  "osieURL": "http://172.17.1.1:7171",
                  "tftpServerBindAddr": "172.17.1.1",
                  "syslogBindAddr": "172.17.1.1",
                  "ipxeHttpScriptBindAddr": "172.17.1.1"
                },
                "tinkController": {
                  "metricsAddr": "0.0.0.0:8084"
                },
                "rufio": {
                  "metricsAddr": "0.0.0.0:8085"
                },
                "tootles": {
                  "bindAddr": "172.17.1.1"
                },
                "tinkServer": {
                  "bindAddr": "172.17.1.1"
                },
                "globals": {
                  "logLevel": 3
                }
              }
            }
          }
        }
      }
    }
  ]'
```

## Wait for `Management`, `Tinkerbell` objects readiness

```bash
k0s kubectl wait --for=condition=Ready=True management/kcm --timeout=300s
```

## Prepare Hardware Resources

Before creating a cluster, you need to register your VMs with Tinkerbell.

### Create BMC Secrets

Create secrets with the sushy-tools Redfish credentials:

```bash
k0s kubectl apply -f - <<EOF
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

---
apiVersion: v1
kind: Secret
metadata:
  name: vm2-bmc
  namespace: kcm-system
type: Opaque
stringData:
  username: admin
  password: "$(cat /root/.redfish_password)"
EOF
```

### Create BMC Machine Objects

```bash
k0s kubectl apply -f - <<EOF
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

---
apiVersion: bmc.tinkerbell.org/v1alpha1
kind: Machine
metadata:
  name: vm2
  namespace: kcm-system
spec:
  connection:
    host: 172.17.1.1
    port: 623
    insecureTLS: true
    authSecretRef:
      name: vm2-bmc
      namespace: kcm-system
    providerOptions:
      preferredOrder:
        - gofish
        - ipmitool
      redfish:
        port: 8000
        systemName: vm2
        useBasicAuth: true
      ipmitool:
        port: 623
        cipherSuite: "3"
EOF
```

> Note: `systemName` must match the libvirt VM domain name.

### Create Hardware Objects

```bash
k0s kubectl apply -f - <<EOF
---
apiVersion: tinkerbell.org/v1alpha1
kind: Hardware
metadata:
  name: vm1
  namespace: kcm-system
  labels:
    tinkerbell.org/role: control-plane
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

---
apiVersion: tinkerbell.org/v1alpha1
kind: Hardware
metadata:
  name: vm2
  namespace: kcm-system
  labels:
    tinkerbell.org/role: worker
spec:
  bmcRef:
    apiGroup: bmc.tinkerbell.org
    kind: Machine
    name: vm2
  disks:
    - device: /dev/vda
  interfaces:
    - dhcp:
        arch: x86_64
        hostname: vm2
        mac: "52:54:00:12:34:02"
        ip:
          address: 172.17.1.102
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
      hostname: vm2
      id: "52:54:00:12:34:02"
      operating_system:
        distro: debian
        version: "13"
EOF
```

> Note:
> - Set `tinkerbell.org/role: control-plane` label for control plane nodes
> - Set `tinkerbell.org/role: worker` label for worker nodes
> - Use `/dev/vda` for virtio disks (VMs), `/dev/sda` for SATA/SCSI (bare-metal)
> - Replace MAC addresses and IP addresses with your actual VM values

### Create Credential

```bash
k0s kubectl apply -f - <<EOF
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
k0s kubectl apply -f - <<EOF
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: tinkerbell-demo
  namespace: kcm-system
spec:
  template: tinkerbell-standalone-cp-0-1-0
  credential: tinkerbell-cluster-identity-cred
  config:
    controlPlaneNumber: 1
    workersNumber: 1
    controlPlaneEndpoint:
      host: "172.17.1.101"
      port: 6443
    controlPlane:
      bootMode: netboot
      hardwareAffinity:
        matchLabels:
          tinkerbell.org/role: control-plane
      templateOverride: |
        version: "0.1"
        name: cp-provision
        global_timeout: 9000
        tasks:
          - name: "cp-provision"
            worker: "{{.device_1}}"
            volumes:
              - /dev:/dev
              - /dev/console:/dev/console
              - /lib/firmware:/lib/firmware:ro
            actions:
              - name: "Stream Debian Image"
                image: quay.io/tinkerbell/actions/image2disk:latest
                timeout: 3000
                environment:
                  DEST_DISK: {{ index .Hardware.Disks 0 }}
                  IMG_URL: https://cdimage.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.raw
                  COMPRESSED: false
              - name: "Grow Partition"
                image: quay.io/tinkerbell/actions/cexec:latest
                timeout: 90
                environment:
                  BLOCK_DEVICE: {{ index .Hardware.Disks 0 }}1
                  FS_TYPE: ext4
                  CHROOT: y
                  DEFAULT_INTERPRETER: "/bin/sh -c"
                  CMD_LINE: "growpart {{ index .Hardware.Disks 0 }} 1 && resize2fs {{ index .Hardware.Disks 0 }}1"
              - name: "Add Cloud-Init Config"
                image: quay.io/tinkerbell/actions/writefile:latest
                timeout: 90
                environment:
                  DEST_DISK: {{ formatPartition ( index .Hardware.Disks 0 ) 1 }}
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
                  DEST_DISK: {{ formatPartition ( index .Hardware.Disks 0 ) 1 }}
                  FS_TYPE: ext4
                  DEST_PATH: /etc/cloud/ds-identify.cfg
                  UID: 0
                  GID: 0
                  MODE: 0600
                  DIRMODE: 0700
                  CONTENTS: |
                    datasource: Ec2
              - name: "Reboot into installed OS"
                image: ghcr.io/jacobweinstock/waitdaemon:latest
                timeout: 90
                pid: host
                command: ["reboot"]
                environment:
                  IMAGE: alpine
                  WAIT_SECONDS: 10
                volumes:
                  - /var/run/docker.sock:/var/run/docker.sock
    worker:
      bootMode: isoboot
      isoURL: "http://172.17.1.1:7171/iso/hook.iso"
      hardwareAffinity:
        matchLabels:
          tinkerbell.org/role: worker
      templateOverride: |
        version: "0.1"
        name: worker-provision
        global_timeout: 9000
        tasks:
          - name: "worker-provision"
            worker: "{{.device_1}}"
            volumes:
              - /dev:/dev
              - /dev/console:/dev/console
              - /lib/firmware:/lib/firmware:ro
            actions:
              - name: "Stream Debian Image"
                image: quay.io/tinkerbell/actions/image2disk:latest
                timeout: 3000
                environment:
                  DEST_DISK: {{ index .Hardware.Disks 0 }}
                  IMG_URL: https://cdimage.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.raw
                  COMPRESSED: false
              - name: "Grow Partition"
                image: quay.io/tinkerbell/actions/cexec:latest
                timeout: 90
                environment:
                  BLOCK_DEVICE: {{ index .Hardware.Disks 0 }}1
                  FS_TYPE: ext4
                  CHROOT: y
                  DEFAULT_INTERPRETER: "/bin/sh -c"
                  CMD_LINE: "growpart {{ index .Hardware.Disks 0 }} 1 && resize2fs {{ index .Hardware.Disks 0 }}1"
              - name: "Add Cloud-Init Config"
                image: quay.io/tinkerbell/actions/writefile:latest
                timeout: 90
                environment:
                  DEST_DISK: {{ formatPartition ( index .Hardware.Disks 0 ) 1 }}
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
                  DEST_DISK: {{ formatPartition ( index .Hardware.Disks 0 ) 1 }}
                  FS_TYPE: ext4
                  DEST_PATH: /etc/cloud/ds-identify.cfg
                  UID: 0
                  GID: 0
                  MODE: 0600
                  DIRMODE: 0700
                  CONTENTS: |
                    datasource: Ec2
              - name: "Reboot into installed OS"
                image: ghcr.io/jacobweinstock/waitdaemon:latest
                timeout: 90
                pid: host
                command: ["reboot"]
                environment:
                  IMAGE: alpine
                  WAIT_SECONDS: 10
                volumes:
                  - /var/run/docker.sock:/var/run/docker.sock
    k0s:
      version: v1.33.4+k0s.0
EOF
```

## Watch Kubernetes objects

```bash
watch k0s kubectl get cld,tinkerbellcluster,k0scontrolplane,tinkerbellmachine,workflow -A
```

## Troubleshooting

### Workflow stuck at reboot action (VM only)

If the workflow is stuck at the "Reboot into installed OS" action, the VM may not have properly triggered the reboot event. This is a **VM-specific issue** that does not occur on bare-metal hardware.

**Workaround**: Manually trigger the reboot via virsh:

```bash
virsh reboot <vm-name>
```

The libvirt reboot monitor service will catch the reboot event and perform a cold reboot (destroy+start) to ensure the boot order is reset to disk-first.

## Extract child cluster kubeconfig

Once the cluster deployment is ready, you can extract the kubeconfig to access the child cluster:

```bash
k0s kubectl get secret tinkerbell-demo-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > tinkerbell-demo.kubeconfig
```

Test connectivity to the child cluster:

```bash
kubectl --kubeconfig=tinkerbell-demo.kubeconfig get nodes
```

## References

- [CAPT Repository](https://github.com/tinkerbell/cluster-api-provider-tinkerbell)
- [Tinkerbell Actions](https://github.com/tinkerbell/actions)
- [HookOS Releases](https://github.com/tinkerbell/hook/releases)
- [Sushy Tools](https://docs.openstack.org/sushy-tools/)
