# Nutanix CAPX Chart - DEPRECATED

⚠️ **This chart is deprecated and will be removed in a future release.**

## Migration Path

This combined chart has been split into two dedicated charts:

### For Hosted Control Plane (HCP) clusters:
- **New chart**: [`nutanix-capx-hcp`](../nutanix-capx-hcp/)
- **Provider pack**: [`nutanix-pp-hcp`](../nutanix-pp-hcp/)

### For Standalone clusters:
- **New chart**: [`nutanix-capx-standalone`](../nutanix-capx-standalone/)
- **Provider pack**: [`nutanix-pp-standalone`](../nutanix-pp-standalone/)

## Why the split?

- **Follows upstream OOT patterns**: Aligns with how other providers (Hetzner, KubeVirt) structure their charts
- **Cleaner separation**: Each chart focuses on a single deployment mode
- **Better discoverability**: KCM/k0rdent shows HCP and Standalone as separate options
- **Simplified configuration**: No more complex mode switching or XOR validation

## Migration Guide

See [NUTANIX.md](../../NUTANIX.md) for detailed migration instructions and updated deployment examples.

## Legacy Support

This chart will continue to work as before for existing users, but no new features will be added. Please migrate to the new split charts at your earliest convenience.
