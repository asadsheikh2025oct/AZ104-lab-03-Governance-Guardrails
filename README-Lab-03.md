# Mini-Lab 03 — Azure Governance Guardrails

## KEY LEARNINGS

> **Status:** Completed 16 October 2026 · **Practical:** 8/8 · **AZ-104 quiz:** 5/5 · **Expected incremental resource cost:** £0 (billing not independently checked)

1. **Policy definition vs assignment:** A built-in definition describes the rule; an assignment applies it at a chosen scope. Keep restrictive policies scoped to disposable lab resource groups before considering wider rollout.
2. **Policy conditions and effects:** `allOf` requires every condition to match; `not`, `in`, and `notIn` test configurations. `Deny` blocks requests, `Audit` reports violations, and `Disabled` stops evaluation.
3. **Multiple guardrails work together:** This lab required `CostCentre = Engineering`, permitted only `uksouth`/`ukwest`, and allowed only the storage SKU `Standard_LRS`.
4. **Test negative AND positive cases:** Deliberately validate bad configurations to prove Azure rejects them, then good ones to prove legitimate deployments remain possible. Read `RequestDisallowedByPolicy` details to identify the exact rule.
5. **Validate without provisioning:** `az deployment group validate --validation-level Provider` tested a Bicep storage account against the policies without creating a storage account. `az bicep build` checks local template compilation but not Azure policy enforcement.
6. **Locks differ:** `CanNotDelete` stops deletion; `ReadOnly` stops both deletion and write operations. Azure returned `ScopeLocked` for our deliberate failures.
7. **Management group permissions differ from subscription permissions:** Subscription Owner does not automatically grant management-group administration. We inspected what was visible without elevating permissions or moving the subscription.
8. **Clean up in safe order:** Remove locks, remove lab policy assignments, delete the disposable resource group, then verify. Never delete unrelated, existing policy assignments.
9. **CLI troubleshooting matters:** `list` returns arrays, `show` returns one object; JMESPath queries are case-sensitive. Use JSON files (`@params.json`) to avoid quoting issues in Windows Command Prompt.
10. **Coverage gaps:** We tested **storage account** SKUs instead of **VM** size SKUs. We also inspected the management-group hierarchy but did **not create a management group or assign policy at management-group scope**, because our account lacked the necessary access. Both remain follow-up exercises; any access elevation requires explicit approval and a rollback plan.

## Business scenario

Northstar Financial Services needed guardrails to stop developers deploying infrastructure in unapproved regions, choosing disallowed SKUs, omitting required cost-allocation tags, or deleting important resources accidentally. The objective was to enforce and prove restrictions with minimal cost and clean teardown.

## Objectives and AZ-104 relevance

- Inspect management-group hierarchy and recognise permissions boundaries.
- Apply built-in Azure policies at **resource-group scope** and read rejection details.
- Restrict required tags, locations, and storage SKUs.
- Compare `CanNotDelete` and `ReadOnly` resource locks.
- Prove compliance using Bicep deployment validation, then clean up safely.

Relevant AZ-104 areas: Azure governance, policy, locks, resource groups, tags and management groups (inspection only). Additional workplace skills: fault isolation, positive/negative tests and cleanup discipline.

## Architecture / scope

```text
Tenant Root Group (read-only investigation; no changes)
└── Existing Azure subscription
    └── rg-az104-governance-lab (temporary; UK South; tag minilab=03)
        ├── Policy assignment: az104-03                  (CostCentre = Engineering)
        ├── Policy assignment: az104-03-allowedLocations (uksouth, ukwest)
        ├── Policy assignment: az104-03-allowedSKUs      (Standard_LRS)
        └── Lock: az104-rgTestLock (CanNotDelete → ReadOnly → removed)
```

**No storage account, VM, disk, network interface or public IP was deployed for the test.** All assignments and the lab resource group were removed at completion. A pre-existing subscription-level `SecurityCenterBuiltIn` assignment was preserved.

## Implementation

### 1. Inspect management-group permissions

A standard management-group read returned `AuthorizationFailed` for `Microsoft.Management/managementGroups/read`. An entity-listing operation revealed the Tenant Root Group and the subscription's placement, but did **not** establish permission to administer management groups. **No management group was created and no policy was assigned at management-group scope.** No elevated permissions or subscription moves were attempted. A follow-up lab would require explicit approval, an impact assessment and a rollback plan before making privileged or tenant-wide changes.

### 2. Create an isolated resource group

```cmd
az group create -g rg-az104-governance-lab -l uksouth --tags minilab=03
az resource list -g rg-az104-governance-lab
```

Resource group creation returned `Succeeded`; resource inventory returned `[]`.

### 3. Required tag policy

Built-in **Require a tag and its value on resources** (`1e30110a-5ceb-460c-a204-c1c3969c6d62`). It checks resources inside the resource group, not the resource group itself.

`params.json`:

```json
{
  "tagName": { "value": "CostCentre" },
  "tagValue": { "value": "Engineering" }
}
```

```cmd
az policy assignment create --name az104-03 --policy 1e30110a-5ceb-460c-a204-c1c3969c6d62 --resource-group rg-az104-governance-lab --params @params.json
```

### 4. Allowed locations policy

Built-in **Allowed locations** (`e56962a6-4747-49cd-b67b-bf8b01975c4c`). Certain resources and `global` locations are excluded by the definition.

`allowedLocations.json`:

```json
{
  "listOfAllowedLocations": {
    "value": ["uksouth", "ukwest"]
  }
}
```

```cmd
az policy assignment create --name az104-03-allowedLocations --policy e56962a6-4747-49cd-b67b-bf8b01975c4c --resource-group rg-az104-governance-lab --params @allowedLocations.json
```

### 5. Allowed storage SKUs policy

Built-in **Storage accounts should be limited by allowed SKUs** (`7433c107-6db4-4ad1-b57a-a76dce0154a1`). The effect defaulted to `Deny`.

`allowedSKUs.json`:

```json
{
  "listOfAllowedSKUs": { "value": ["Standard_LRS"] }
}
```

```cmd
az policy assignment create --name az104-03-allowedSKUs --policy 7433c107-6db4-4ad1-b57a-a76dce0154a1 --resource-group rg-az104-governance-lab --params @allowedSKUs.json
```

### 6. Bicep and policy verification

A minimal `storage.bicep` described a `Microsoft.Storage/storageAccounts` resource with a deterministic unique name, UK South location, `CostCentre = Engineering`, `StorageV2` kind and `Standard_LRS` SKU. For negative tests, **one property at a time** was changed to `Finance`, `eastus`, or `Standard_GRS`.

```cmd
az bicep build -f storage.bicep
az deployment group validate --resource-group rg-az104-governance-lab --template-file storage.bicep --validation-level Provider
az resource list -g rg-az104-governance-lab
```

| Case | Expected outcome | Observed |
|---|---|---|
| `CostCentre = Finance` | Tag policy rejects | `RequestDisallowedByPolicy` |
| `CostCentre = Engineering` | Tag policy permits | `Succeeded`, `error: null` |
| `eastus`, correct tag | Locations policy rejects | `RequestDisallowedByPolicy` |
| `uksouth`, correct tag | Locations policy permits | `Succeeded`, `error: null` |
| `Standard_GRS`, correct tag and region | SKU policy rejects | `RequestDisallowedByPolicy` |
| `Standard_LRS`, correct tag and region | All three policies permit | `Succeeded`, `error: null` |

Every resource inventory check returned `[]`; no proposed storage account was created.

### 7. Test resource locks

```cmd
az lock create --lock-type CanNotDelete --name az104-rgTestLock --resource-group rg-az104-governance-lab
az group delete -g rg-az104-governance-lab
```

The command prompted `Are you sure you want to perform this operation? (y/n):`; the test continued only after entering `y`. Azure then refused deletion with `ScopeLocked`. Next:

```cmd
az lock update --name az104-rgTestLock --resource-group rg-az104-governance-lab --lock-type ReadOnly
az group update -g rg-az104-governance-lab --tags CostCentre=Engineering
```

Azure refused the tag change with `ScopeLocked`, specifically reporting a blocked **write** operation.

## Verification evidence (redacted excerpts)

The following short excerpts are taken from the observed Azure CLI responses. Account, subscription and object identifiers are omitted.

**Required-tag policy — wrong value (`Finance`):**

```text
code: RequestDisallowedByPolicy
policyAssignmentName: az104-03
policyDefinitionDisplayName: Require a tag and its value on resources
expression: tags[CostCentre]
expressionValue: Finance
requiredValue: Engineering
```

**Allowed Storage SKU policy — disallowed `Standard_GRS`:**

```text
code: RequestDisallowedByPolicy
policyAssignmentName: az104-03-allowedSKUs
policyDefinitionDisplayName: Storage accounts should be limited by allowed SKUs
expressionValue: Standard_GRS
allowedValues: [Standard_LRS]
```

**Resource locks — deletion and modification attempts:**

```text
code: ScopeLocked
operation: delete     # CanNotDelete lock
code: ScopeLocked
operation: write      # ReadOnly lock
```

These excerpts are condensed from the responses (not verbatim JSON). Positive validation returned `error: null` and `provisioningState: Succeeded`; subsequent resource listing returned `[]`.

## Troubleshooting and lessons from errors

| Symptom | Explanation / learning |
|---|---|
| `AuthorizationFailed` on management groups | Higher-level permissions aren't implied by subscription Owner |
| `UnsupportedFilter` | Azure CLI service-side filters have constrained syntax |
| `null` or `[]` from queries | Wrong path, wrong shape, no match or case mismatch |
| `InvalidTemplateDeployment` + `RequestDisallowedByPolicy` | Provider validation detected a specific deny rule; inspect evaluation details |
| `ScopeLocked` when deleting | CanNotDelete lock successfully blocked deletion |
| `ScopeLocked` when changing tags | ReadOnly lock successfully blocked writes |
| `SecurityCenterBuiltIn` appeared during cleanup | Existing subscription policy; preserve it |

## Cost optimisation

All three deny/allow policy experiments used **validation**, not deployment. No storage account or VM was provisioned. Expected incremental billable resource usage: **£0**. This is not an independently verified subscription bill or evidence about unrelated existing resources.

## Cleanup and evidence

The following cleanup operations were executed and checked:

```cmd
az lock delete --name az104-rgTestLock --resource-group rg-az104-governance-lab
az lock list -o table
az policy assignment delete --resource-group rg-az104-governance-lab --name az104-03
az policy assignment delete --resource-group rg-az104-governance-lab --name az104-03-allowedLocations
az policy assignment delete --resource-group rg-az104-governance-lab --name az104-03-allowedSKUs
az policy assignment list -o table
az group delete -g rg-az104-governance-lab --yes
az group list -o table
```

Evidence: lock list empty; lab assignments absent; unrelated subscription security assignment still present; resource-group list empty. Alice Engineer (a reusable test identity) was not modified.

## What I would do in production

For an organisation with many subscriptions, I would evaluate applying common policies at **management-group scope** rather than repeating assignments across resource groups. I would group related policies into an **initiative** (a named set of policies), document and narrowly scope any **exemptions**, and manage definitions and assignments as reviewed **policy-as-code** using version control and deployment automation. I would start in audit mode where appropriate, assess existing resources and rollout impact, then move to enforcement with change approval and monitoring. Management-group access changes or subscription moves would require a specific impact review, approval and rollback plan.

## Exam results and interview talking point

**AZ-104 scenario quiz: 5/5 (100%).** Topics: CanNotDelete vs ReadOnly, management-group policy inheritance, SKU rejection, Audit effect, and Provider-level validation.

> I implemented resource-group scoped governance controls using built-in Azure Policy definitions, tested compliant and non-compliant Bicep configurations without provisioning billable infrastructure, investigated policy denial and resource lock errors, and safely cleaned up the lab.

## Further study

- Practice the **Allowed virtual machine size SKUs** policy separately. This lab deliberately replaced that exercise with storage SKUs.
- Complete a separate management-group creation and management-group-scoped policy exercise when authorised. This was **not performed** in this lab; any privileged access change requires explicit approval and a rollback plan.
- Review management-group permissions and inherited policies without elevating tenant-wide access.
- Next lab: **Mini-Lab 04 — Azure Cost Controls** (budget alerts, tag-based cost analysis, Azure Advisor).

## References

- [Azure Policy overview](https://learn.microsoft.com/en-us/azure/governance/policy/overview)
- [Manage Azure resource locks](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/lock-resources)
- [Azure CLI policy assignments](https://learn.microsoft.com/en-us/cli/azure/policy/assignment)
- [Azure CLI deployment validation](https://learn.microsoft.com/en-us/cli/azure/deployment/group)
