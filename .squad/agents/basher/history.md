# Project Context

- **Owner:** Carol Garcha
- **Project:** One Microsoft Foundry resource with two isolated projects and matching Entra groups
- **Stack:** Microsoft Foundry, Microsoft Entra ID, Azure RBAC, Bicep or Terraform
- **Created:** 2026-07-30T22:44:47.921-05:00

## Learnings

- Group provisioning and project-scoped role assignments must be repeatable through IaC.
- Keep group lifecycle outside the core ARM deployment; Bicep should consume verified object IDs and only encode narrow project-scope assignments.
