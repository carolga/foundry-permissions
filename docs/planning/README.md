# Planning Artifact Index

Start with the [root solution README](../../README.md) for the deployed validation environment, current exceptions, cost notes, and resource rationale. The [canonical integrated project plan](project-plan.md) remains the planning baseline and resolves planning conflicts.

| Artifact | Purpose |
|---|---|
| [Deployed solution README](../../README.md) | Current deployed architecture, validation findings, cost notes, and resource-by-resource rationale |
| [Architecture diagram](../architecture/foundry-permissions.drawio) | diagrams.net source with Azure resource icons, network paths, and permissions overlays |
| [Canonical integrated project plan](project-plan.md) | Approved-with-conditions architecture and execution baseline |
| [Foundry topology](foundry-topology.md) | Resource, project, network, data, and capability design |
| [Identity and RBAC](identity-rbac.md) | Group lifecycle, scopes, inheritance, and non-discoverability tests |
| [Loan document requirements](loan-document-requirements.md) | HOA/contract taxonomies, field schema, sources, and gold cases |
| [Responsible AI controls](responsible-ai-controls.md) | Privacy, fair-lending, safety, escalation, and Yellow advisory |
| [Validation plan](validation-plan.md) | Positive/negative tests, evidence schema, and release thresholds |
| [Bicep deployment plan](bicep-deployment-plan.md) | Future module boundaries, sequencing, CI/CD, and rollback |
| [Azure plan summary](../../.azure/deployment-plan.md) | Azure workflow status and pointer |

## Specialist decision summaries

- [Initial architecture review](../../.squad/decisions/inbox/danny-design-review.md)
- [Foundry topology decision](../../.squad/decisions/inbox/rusty-foundry-topology.md)
- [Identity/RBAC decision](../../.squad/decisions/inbox/livingston-rbac-plan.md)
- [Bicep boundary decision](../../.squad/decisions/inbox/basher-bicep-plan.md)
- [Domain requirements decision](../../.squad/decisions/inbox/reuben-domain-plan.md)
- [Responsible AI decision](../../.squad/decisions/inbox/rai-controls-plan.md)
- [Validation decision](../../.squad/decisions/inbox/linus-validation-plan.md)
- [Integrated planning decision](../../.squad/decisions/inbox/danny-integrated-plan.md)

**Current verdict:** Approve with conditions. The next work package is the tenant capability and strict-isolation preflight defined in the canonical plan.
