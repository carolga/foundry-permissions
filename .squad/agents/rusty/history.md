# Project Context

- **Owner:** Carol Garcha
- **Project:** One Microsoft Foundry resource with two isolated projects and matching Entra groups
- **Stack:** Microsoft Foundry, Microsoft Entra ID, Azure RBAC, Bicep or Terraform
- **Created:** 2026-07-30T22:44:47.921-05:00

## Learnings

- Members need project-local permissions to create agents and evaluations without sibling-project access.
- Treat strict sibling non-discoverability as a deployment gate; keep one Foundry resource with two isolated projects and project-specific data connections.
