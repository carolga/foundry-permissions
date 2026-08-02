# Squad Team

> foundry-permissions

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| Danny | Lead / Solution Architect | .squad/agents/danny/charter.md | Active |
| Rusty | Azure Foundry Architect | .squad/agents/rusty/charter.md | Active |
| Basher | Infrastructure-as-Code Engineer | .squad/agents/basher/charter.md | Active |
| Livingston | Identity & RBAC Specialist | .squad/agents/livingston/charter.md | Active |
| Linus | Validation Engineer | .squad/agents/linus/charter.md | Active |
| Reuben | Loan Origination & Residential Documents SME | .squad/agents/reuben/charter.md | Active |
| Scribe | Session Logger & Decision Manager | .squad/agents/scribe/charter.md | Silent |
| Ralph | Work Monitor | .squad/agents/ralph/charter.md | Monitor |
| Rai | RAI Reviewer | .squad/agents/Rai/charter.md | Background |

## Project Context

- **Project:** foundry-permissions
- **Created:** 2026-07-30
- **Owner:** Carol Garcha
- **Goal:** Deploy one Microsoft Foundry resource with two isolated Foundry projects and matching Microsoft Entra groups.
- **Access model:** `hoa-group` is scoped to the HOA project; `One-to-Four-Residential-Contract` is scoped to its corresponding project. Members can create agents and evaluations only in their assigned project.
- **Stack:** Microsoft Foundry, Microsoft Entra ID, Azure RBAC, Bicep or Terraform
- **Domain:** Loan origination, HOA documentation, and one-to-four family residential contracts
