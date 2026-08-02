# Project Context

- **Owner:** Carol Garcha
- **Project:** Foundry deployment supporting isolated HOA and one-to-four family residential contract use cases
- **Stack:** Microsoft Foundry, Microsoft Entra ID, Azure RBAC, Bicep or Terraform
- **Created:** 2026-07-31T00:45:59.396-05:00

## Learnings

- Define loan fields with source provenance, confidence, required/optional status, validation rules, and human-review triggers.
- HOA and residential contract schemas must account for jurisdictional and lender-specific variation.
- The domain boundary stays extraction/QC only, with synthetic gold cases and jurisdiction/form-dependent fields marked human-review-required until authoritative sources are named.
