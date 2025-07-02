# k0rdent/kcm (out-of-tree)

## Debug charts

### Pull

```bash
helm pull oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.0.0 --untar --untardir ./TEMP/.
```

### Render

```bash
helm template test oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.0.0 -n kcm-system --output-dir ./TEMP/.

helm template test oci://ghcr.io/k0rdent-oot/oot/charts/kubevirt --version 1.0.0 \
  -n kcm-system \
  --set kubevirt.configuration.developerConfiguration.featureGates="{useEmulation=true}" \
  --output-dir ./TEMP/.
```

### Generate `values.schema.json`:

Use `https://github.com/losisin/helm-values-schema-json` to (re)generate schemas manually.

Inside chart folder run `helm schema -input values.yaml`, see example [valules.yaml](https://github.com/k0rdent/kcm/blob/main/templates/cluster/gcp-standalone-cp/values.yaml)
