# KubeVirt Helm Chart

This Helm chart deploys KubeVirt on a Kubernetes cluster.

## Installation

```bash
helm install kubevirt oci://ghcr.io/k0rdent-oot/oot/charts/kubevirt \
  --namespace kubevirt
```

## Configuration

The chart supports configurable deployment options through values.yaml.

## Helm Upgrade Example

To upgrade an existing KubeVirt deployment with custom configuration:

```bash
# Create values override file
cat > kubevirt-values.yaml << EOF
kubevirt:
  virtOperator:
    replicas: 1
    env:
      - name: VIRT_OPERATOR_IMAGE
        value: quay.io/kubevirt/virt-operator:v1.6.2
      - name: WATCH_NAMESPACE
        valueFrom:
          fieldRef:
            apiVersion: v1
            fieldPath: metadata.annotations['olm.targetNamespaces']
      - name: KUBEVIRT_VERSION
        value: v1.6.2
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

# Upgrade with custom values
helm upgrade kubevirt oci://ghcr.io/k0rdent-oot/oot/charts/kubevirt \
  --namespace kubevirt \
  --take-ownership \
  -f kubevirt-values.yaml
```
