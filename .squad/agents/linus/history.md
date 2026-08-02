# Project Context

- **Owner:** Carol Garcha
- **Project:** One Microsoft Foundry resource with two isolated projects and matching Entra groups
- **Stack:** Microsoft Foundry, Microsoft Entra ID, Azure RBAC, Bicep or Terraform
- **Created:** 2026-07-30T22:44:47.921-05:00

## Learnings

- Acceptance requires allowed actions in the assigned project and explicit denial in the sibling project.
- Validation must use fresh tokens and prove both positive capability and strict negative isolation after every role, group, or PIM change.
