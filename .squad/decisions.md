# Squad Decisions

## Active Decisions

### 2026-07-31 — Canonical integrated plan approved with conditions
- One Microsoft Foundry resource hosts two isolated projects: `hoa-project` and `one-to-four-residential-contract-project`.
- Exact Entra groups: `hoa-group` and `One-to-Four-Residential-Contract`.
- Foundry User is granted only at the matching project scope; no broader parent-scope access is approved without live proof that sibling non-discoverability still holds.
- Agents remain extraction/QC only; no autonomous approval, denial, underwriting, legal, or compliance decisions.
- Implementation stays blocked until tenant capability, inherited-access, domain provenance, and RAI gates are proven.

### 2026-07-31 — RBAC isolation gate
- Require fresh-token portal/API tests for positive access in the assigned project and explicit denial in the sibling project.
- Audit direct, transitive-group, PIM-active/eligible, and inherited assignments from management group through project scope.
- Do not grant parent Reader or any broader role unless required by the platform and verified not to expose sibling project access.

### 2026-07-31 — Topology and infrastructure gate
- Keep the Foundry topology to one resource and two projects.
- Prefer project-specific data connections and separate backing resources where possible.
- Pre-provision `hoa-group` and `One-to-Four-Residential-Contract` through identity governance; core Bicep must consume verified object IDs, not create or discover groups.

### 2026-07-31 — Domain provenance gate
- Reuben's requirements define the HOA and one-to-four family residential contract taxonomies, canonical field dictionary, source register, and synthetic/gold cases.
- Jurisdiction/form-dependent fields remain `unknown — human-review-required` until Carol names authoritative sources and approvers.

### 2026-07-31 — Responsible AI gate
- Rai's controls keep the system extraction/QC only, with provenance, confidence, escalation, privacy, and leakage protections.
- The RAI plan remains advisory until authoritative jurisdiction/source/approver inputs are named.

### 2026-07-31 — Validation gate
- Linus must prove positive capability plus strict negative isolation with fresh ARM and Foundry tokens after every role/group/PIM change.
- Evidence must exclude raw tokens, secrets, UPNs, PII, and live documents.
- Live authorization/network tests await tenant access; domain acceptance awaits authoritative inputs.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
