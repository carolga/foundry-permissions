# Project Context

- **Owner:** Carol Garcha
- **Project:** One Microsoft Foundry resource with two isolated projects and matching Entra groups
- **Stack:** Microsoft Foundry, Microsoft Entra ID, Azure RBAC, Bicep or Terraform
- **Created:** 2026-07-30T22:44:47.921-05:00

## Learnings

- The design must prove that each group can create agents and evaluations only in its assigned project.
- Canonical plan is approved with conditions: one Foundry resource, two isolated projects, and no implementation before live tenant and isolation proof.
