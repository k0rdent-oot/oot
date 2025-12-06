# Cluster API Provider Tinkerbell

A Helm chart for deploying the Cluster API Provider Tinkerbell (CAPT) with optional Tinkerbell stack.

## Installation

### CAPT Provider Only (Tinkerbell stack managed separately)

```bash
helm install cluster-api-provider-tinkerbell \
  oci://ghcr.io/k0rdent-oot/oot/charts/cluster-api-provider-tinkerbell \
  --namespace kcm-system \
  --create-namespace
```

### CAPT Provider with Tinkerbell Stack

Create a values file `tinkerbell-values.yaml`:

```yaml
tinkerbell:
  enabled: true
  publicIP: "172.18.0.100"
  artifactsFileServer: "http://172.18.0.101:7173"
  trustedProxies:
    - "10.244.0.0/16"
  optional:
    hookos:
      enabled: true
  deployment:
    envs:
      smee:
        isoUpstreamURL: "https://github.com/tinkerbell/hook/releases/download/latest/hook-x86_64-efi-initrd.iso"
        osieURL: "http://172.18.0.100:7171"
      globals:
        logLevel: 3
```

Install with values:

```bash
helm install cluster-api-provider-tinkerbell \
  oci://ghcr.io/k0rdent-oot/oot/charts/cluster-api-provider-tinkerbell \
  --namespace kcm-system \
  --create-namespace \
  --wait \
  -f tinkerbell-values.yaml
```

## References

- [CAPT Repository](https://github.com/tinkerbell/cluster-api-provider-tinkerbell)
- [Tinkerbell Helm Chart](https://github.com/tinkerbell/tinkerbell/tree/main/helm/tinkerbell)
- [HookOS Releases](https://github.com/tinkerbell/hook/releases)
