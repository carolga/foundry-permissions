# Project Context

- **Owner:** Carol Garcha
- **Project:** One Microsoft Foundry resource with two isolated projects and matching Entra groups
- **Stack:** Microsoft Foundry, Microsoft Entra ID, Azure RBAC, Bicep or Terraform
- **Created:** 2026-07-30T22:44:47.921-05:00

## Learnings

- `hoa-group` and `One-to-Four-Residential-Contract` must each be scoped only to the corresponding Foundry project.
- Project-scoped Foundry User remains the only approved grant; inherited, transitive, PIM, and parent Reader access must be audited and denied if it exposes siblings.
