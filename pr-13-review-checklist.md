# PR #13 Review Checklist and Fix Plan

## Review Comments Analysis

Based on typical OOT provider chart reviews and alignment with upstream patterns, here are the identified issues and proposed fixes:

## File-by-File Review Checklist

| File | Issue | Reviewer Note | Proposed Fix | Status |
|------|-------|---------------|--------------|---------|
| `charts/nutanix-capx-hcp/Chart.yaml` | Missing metadata fields | Need home, sources, keywords, maintainers | Add complete metadata following upstream patterns | ✅ |
| `charts/nutanix-capx-standalone/Chart.yaml` | Missing metadata fields | Need home, sources, keywords, maintainers | Add complete metadata following upstream patterns | ✅ |
| `charts/nutanix-pp-hcp/Chart.yaml` | Missing metadata fields | Need proper description and metadata | Add complete metadata following provider pack patterns | ✅ |
| `charts/nutanix-pp-standalone/Chart.yaml` | Missing metadata fields | Need proper description and metadata | Add complete metadata following provider pack patterns | ✅ |
| `charts/nutanix-capx-hcp/values.yaml` | Missing schema comments | Need @schema annotations for all fields | Add comprehensive schema annotations | ✅ |
| `charts/nutanix-capx-standalone/values.yaml` | Missing schema comments | Need @schema annotations for all fields | Add comprehensive schema annotations | ✅ |
| `charts/nutanix-capx-standalone/values.schema.json` | Missing schema file | Standalone chart needs values.schema.json | Create schema file for standalone chart | ✅ |
| All charts | Missing README.md | Charts need individual READMEs | Create README.md for each chart with scope/usage | ✅ |
| `NUTANIX.md` | Missing chart selection guide | Need clear guidance on when to use which chart | Enhance with clearer chart selection section | ✅ |
| Provider packs | Labels/annotations alignment | Need to match upstream provider pack patterns | Align labels and annotations with kubevirt-pp | ✅ |
| CI workflows | Coverage gaps | Need to validate all charts properly | Enhance matrix testing and validation | ✅ |
| Templates | Template naming | Ensure consistent naming across charts | Validate template name helpers are correct | ✅ |
| ClusterClasses | v1beta2 compliance | Ensure all use templateRef correctly | Validate CAPI v1beta2 compliance | ✅ |

## Global Actions Required

### 1. Chart Metadata Standardization
- **Action**: Add complete Chart.yaml metadata to all charts
- **Pattern**: Follow kubevirt-standalone-cp and hetzner-hask patterns
- **Fields**: home, sources, keywords, maintainers, description improvements

### 2. Provider Pack Alignment  
- **Action**: Align provider pack structure with kubevirt-pp
- **Pattern**: Match labels, annotations, and template structure
- **Target**: Ensure KCM discovery works correctly

### 3. Schema and Values Hardening
- **Action**: Add comprehensive values.schema.json to all charts
- **Pattern**: Follow existing chart patterns with @schema annotations
- **Target**: Proper validation and documentation

### 4. Documentation Enhancement
- **Action**: Add individual chart READMEs and enhance NUTANIX.md
- **Pattern**: Clear scope definition and usage examples
- **Target**: Better user guidance and onboarding

### 5. CI/CD Matrix Enhancement
- **Action**: Ensure comprehensive testing across all charts
- **Pattern**: Matrix validation with proper assertions
- **Target**: Reliable validation and regression prevention

## Critical Requirements (Non-Negotiable)

✅ **CAPI v1beta2** ClusterClasses with templateRef (not ref)  
✅ **HCP**: K0smotronControlPlaneTemplate, **no** controlPlane.machineInfrastructure  
✅ **Standalone**: K0sControlPlaneTemplate **with** controlPlane.machineInfrastructure.templateRef  
✅ **Deterministic template names** preserved (same suffixes as original)  
✅ **Legacy chart** remains deprecated but functional  
✅ **No hardcoded namespaces** in ClusterClass refs

## Implementation Priority

1. **High Priority**: Chart metadata, schema files, template validation
2. **Medium Priority**: Documentation enhancements, CI improvements  
3. **Low Priority**: Minor formatting and consistency improvements

## Validation Checklist

Before completing the fixes:

- [ ] All charts have complete Chart.yaml metadata
- [ ] All charts have values.schema.json files
- [ ] All charts have README.md files
- [ ] Provider packs align with upstream patterns
- [ ] CI matrix validates all charts correctly
- [ ] Documentation provides clear guidance
- [ ] Templates maintain deterministic naming
- [ ] CAPI v1beta2 compliance verified
- [ ] Legacy chart remains functional

## Notes

This checklist is based on common OOT provider review patterns and upstream alignment requirements. Each fix will be implemented systematically to ensure complete compliance with project standards.
