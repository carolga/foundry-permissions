# Validation Plan — Foundry Project Isolation and Document Extraction/QC

**Owner:** Linus, Validation Engineering  
**Status:** Planning only; no deployment, authentication, test-user creation, or tenant testing has occurred  
**Date:** 2026-07-31  
**Target region:** `northcentralus`  
**IaC:** Bicep  

## 1. Purpose and acceptance principle

This plan defines reproducible authorization, deployment, networking, domain, and evaluation validation for one Microsoft Foundry resource containing:

- `hoa-project`, assigned to `hoa-group`
- `one-to-four-residential-contract-project`, assigned to `One-to-Four-Residential-Contract`

The candidate developer role is **Foundry User** at the matching project scope only. It remains unapproved until live tests prove that users can create/manage agents and create/run evaluations in their own project without discovering or accessing the sibling project.

**A successful deployment is not evidence of isolation.** Release requires positive proof of intended capability and negative proof of sibling non-discoverability and non-access across the portal, ARM, Foundry APIs/SDKs, project data planes, and backing resources.

Agents are limited to document intake, extraction, normalization, provenance, and quality control. They must not approve or deny a transaction, determine eligibility, provide a legal/compliance conclusion, or use protected-class data outside an approved reporting purpose.

## 2. Test environments

| Environment | Purpose | Data | Required posture |
|---|---|---|---|
| Static/CI | Bicep build, lint, policy/static checks, template inspection | No tenant data | Offline or non-authenticated; no secrets |
| Isolated validation subscription/resource group | Deployment, rollback, RBAC, networking, and destructive test cases | Synthetic configuration and synthetic documents only | Production-equivalent policy, private networking, no shared developer access |
| Private validation client | Portal/API/SDK tests from an approved network path | Synthetic gold data | Private DNS and TCP 443 path to all required endpoints |
| External-network client | Prove public access is disabled | No document payloads | Must not have VPN/ExpressRoute/private DNS access |
| Production-readiness rehearsal | Final repeat of approved non-destructive gates | Approved synthetic corpus only | Same modules, role IDs, network topology, and feature versions intended for production |

Validation resources must not share customer-data connections, storage, search, Cosmos DB, or document corpora with another environment. No live borrower, property, HOA, employee, or customer data is permitted.

## 3. Planned test identities

These are identity archetypes only. This plan does not create them.

| Alias | Membership/assignment | Purpose |
|---|---|---|
| `T-HOA-ONLY` | Direct member of `hoa-group` only | Positive HOA and negative contract-project tests |
| `T-CONTRACT-ONLY` | Direct member of `One-to-Four-Residential-Contract` only | Positive contract and negative HOA-project tests |
| `T-NO-ACCESS` | Member of neither project group; no direct roles | Baseline denial and metadata non-discoverability |
| `T-DUAL-CONTROL` | Explicitly approved member of both groups | Control proving two project assignments produce intentional dual access; run only after single-group gates pass |
| `T-ADMIN-CONTROL` | Time-bound approved administrator | Confirms resources exist and distinguishes denial from missing-resource defects |
| `MI-HOA` | `hoa-project` system-assigned identity | HOA connection/backing-resource positive and contract-resource negative tests |
| `MI-CONTRACT` | Contract project system-assigned identity | Contract connection/backing-resource positive and HOA-resource negative tests |
| `WI-INFRA` | Federated infrastructure deployment identity | Bicep deployment without project data access |
| `WI-ACCESS` | Federated access-deployment identity | Role-assignment deployment without infrastructure or project data access |

Identity prerequisites:

- Use non-personal, non-PII aliases in test manifests and repository-safe evidence.
- Single-project identities must have no direct Azure assignment, nested/dynamic group membership, privileged group, sibling group, or activatable broader PIM role.
- Validate group object IDs and `principalType` without recording UPNs.
- Run the direct, transitive, PIM, inherited, Lighthouse, custom-role, classic-admin, and deny-assignment audit before capability testing.
- Do not distribute account keys or connection secrets. Use Microsoft Entra tokens and managed identities.

## 4. Prerequisites and entry criteria

### 4.1 Required implementation inputs

- Basher's reviewed Bicep modules and non-secret outputs defined in `foundry-topology.md`.
- Exact Foundry account, project, private endpoint, DNS zone, connection, and per-project backing-resource IDs.
- Verified group object IDs from Identity.
- Live tenant definitions for Foundry User and every conditional backing-resource role.
- Approved model/evaluator deployment, quota, version, and private-network support in `northcentralus`.
- An approved private extraction path; network-isolated File Search is not assumed.
- Synthetic, versioned gold corpora stored separately by project.
- Approved source/form/jurisdiction register and named review roles for production acceptance.

### 4.2 Entry checks

1. Static validation has passed.
2. The deployment what-if contains exactly one Foundry resource and exactly two named projects.
3. Public network access is disabled in the planned configuration.
4. Developer group assignments exist only at their matching project scope.
5. Project connections and backing resources are separate and correctly named/scoped.
6. No template, parameter, output, log, fixture, or evidence file contains secrets, PII, connection strings, raw tokens, or real documents.
7. The test identity effective-access audit has no unexplained assignment.
8. Synthetic gold data has a version, project label, case ID, expected output, and artifact hash.

## 5. Token freshness and propagation protocol

Authorization evidence is invalid if it relies on a token issued before a role, membership, PIM, or deny-assignment change.

1. Record change time `T0`, change type, target principal/group, assignment ID, and expected effect.
2. End all Azure and Foundry portal sessions. Use a new private browser profile.
3. Clear local CLI/SDK token caches using the approved runbook; never print or preserve raw tokens.
4. Acquire separate fresh tokens for ARM and the Foundry data endpoint.
5. Record only token issue/expiry times, tenant/client identifiers where approved, test alias, and a non-reversible evidence correlation value.
6. Execute the smallest safe authorization probe, then the full applicable matrix.
7. If the result is inconsistent with the expected post-change state, repeat with a newly issued token at planned checkpoints such as 5, 15, 30, and 60 minutes, bounded by the platform's current documented propagation window.
8. Classify a result as **propagation delay** only when fresh-token retries converge within the approved window and all timestamps are retained.
9. Classify it as a **persistent defect** when it remains wrong beyond the approved window or is reproducible after stabilization.

Any fresh-token sibling access or disclosure is a security defect immediately. Later convergence does not erase the exposure; it records duration and may affect severity. Stale-token behavior is documented separately and never used as pass evidence.

## 6. Requirements traceability matrix

| ID | Requirement | Source | Planned evidence |
|---|---|---|---|
| ISO-01 | Exact two project names and matching groups | Locked decision; topology/RBAC plans | Template inspection, deployment inventory |
| ISO-02 | Strict sibling-project non-discoverability | Locked decision; topology §5; RBAC §8 | Portal, ARM, Resource Graph/search, API/SDK/CLI, selector and deep-link negative tests |
| ISO-03 | Foundry User only at matching project scope | Locked decision; RBAC §§1–3 | Live role definition, assignment inventory, effective-access audit |
| ISO-04 | No parent Reader or broader developer role | Topology §5; RBAC §§5–8 | Inheritance/PIM/transitive audit and parent-scope negative checks |
| CAP-01 | Create/manage/invoke agents in own project | Locked decision; topology §6 | Portal and API agent lifecycle tests |
| CAP-02 | Create/run/read/manage evaluations in own project | Locked decision; topology §6 | Evaluation lifecycle and result-access tests |
| CAP-03 | Files and datasets remain project-scoped | Topology §§4, 6 | Own CRUD and sibling list/read/write denial |
| CAP-04 | Connections are project-specific | Locked decision; topology §§4, 6 | Connection inventory, own use, sibling enumeration/use denial |
| CAP-05 | Developers cannot manage model deployments or projects | Topology §6; RBAC §9 | Control-plane create/update/delete denial |
| NET-01 | Foundry public network access disabled | Locked decision; topology §7 | Template check plus external-client connection denial |
| NET-02 | Private endpoint and DNS work from approved paths | Topology §7 | DNS answers, private IP mapping, TCP 443 and service request evidence |
| NET-03 | Backing resources are project-specific and private | Locked decision; topology §§4, 7 | Resource/endpoint inventory and cross-MI denial |
| DEP-01 | Bicep is valid, deterministic, least privilege, and reversible | Topology §§8, 10; RBAC §10 | Lint/build/what-if/idempotency/rollback evidence |
| DOM-01 | Extraction/QC only; no autonomous decisions or legal conclusions | Locked decision; domain §§1, 5, 8 | Refusal/escalation evaluation cases |
| DOM-02 | Every value has category, provenance, confidence, and review metadata | Domain §§4.10, 5 | Gold-output schema and scoring |
| DOM-03 | Missing, contradictory, ambiguous, altered, stale, and degraded inputs are detected | Domain §6 | Perturbed synthetic evaluation suites |
| DOM-04 | Protected-class data is extraction/reporting-only | Domain §§1, 4.7, 6, 8 | Misuse-attempt negative tests |
| DOM-05 | No cross-project document or output leakage | Locked decision; domain §§0, 6 | Canary corpus and sibling retrieval/inference tests |
| EVD-01 | Evidence is reproducible, safe, attributable, and tamper-evident | Danny gate 9; secret-handling skill | Structured records and SHA-256 artifact manifest |

## 7. Positive and negative RBAC matrix

Run every applicable row twice: `T-HOA-ONLY` against HOA as **own** and contract as **sibling**, then `T-CONTRACT-ONLY` with the projects reversed. Repeat portal and direct API/SDK/CLI paths where the feature supports them.

| Area / operation | Own project expectation | Sibling project expectation | `T-NO-ACCESS` expectation | Required evidence |
|---|---|---|---|---|
| Portal project landing/deep link | Allow assigned project | No listing, recent-item, picker, count, name, ID, URI, or metadata disclosure; deep link denied without informative detail | No project discovery | Screenshot/video plus sanitized network/result record |
| ARM project list/get | Only own project if listing is supported | Sibling absent; exact known-ID/name GET denied | Empty/denied | Request path, status, response hash, correlation ID |
| Foundry project endpoint/API | Authenticate and use own endpoint | Deny; response must not reveal sibling metadata | Deny | Endpoint alias, operation, status |
| Resource Graph/search/selectors | Own visibility only if required | Sibling absent | No projects | Query hash and sanitized results |
| Agent list/get/create/update/delete | Allow | Deny and do not enumerate | Deny | Object alias, lifecycle result |
| Agent invoke/test | Allow approved extraction/QC agent | Deny invocation and trace/result access | Deny | Request case ID, status, output hash |
| Agent publish/hosted deployment | Deny initial phase | Deny | Deny | Control-plane/data-plane denial |
| Evaluation create/run/cancel/read/delete | Allow where supported | Deny and do not enumerate results/traces | Deny | Evaluation ID alias, lifecycle evidence |
| Dataset/file upload/list/read/update/delete | Allow synthetic own-project artifacts | Deny, including guessed IDs and names | Deny | Artifact hash and operation results |
| Project connection list/read/use | Allow only approved own-project connections | Deny and do not enumerate | Deny | Connection alias/ID hash and result |
| Project connection create/update/delete | Record actual Foundry User behavior; allow only if approved governance control is effective | Deny | Deny | Policy/custom-role finding and operation result |
| Backing Storage blob/container access | Through approved project path/MI only; direct user access not required | Deny | Deny | Principal, scope, status |
| Search index/query/index-management | Own approved path/MI only | Deny enumeration, query, and mutation | Deny | Service/index alias and status |
| Cosmos/agent-state access | Own service identity path only | Deny database/container/state access | Deny | Resource alias and status |
| Model inference through project | Allow approved deployment through own project | Deny via sibling project endpoint | Deny | Deployment alias, project endpoint, status |
| Model deployment list metadata | Only minimum required metadata; no sibling/customer-data disclosure | No sibling project association disclosure | Deny/minimal platform behavior | Sanitized response |
| Model deployment create/update/delete | Deny | Deny | Deny | ARM/portal denial |
| Project create/update/delete | Deny | Deny | Deny | ARM/portal denial |
| Foundry account/network/key management | Deny | Deny | Deny | Portal/ARM denial |
| IAM role assignment/read beyond minimum | Cannot assign; must not gain broader visibility | Deny | Deny | IAM operation result |
| Logs/traces/monitoring | Own project trace access only where required | Deny sibling logs/traces and shared sink | Deny | Query and result hash |

### 7.1 Non-discoverability pass rule

- `404` is preferred for a known sibling identifier.
- `403` is acceptable only if list/search/picker/recent-item behavior reveals nothing and the response body, headers, correlation surfaces, and user-visible logs contain no sibling name, ID, endpoint, tags, identity, object count, or asset metadata.
- A sibling appearing but being non-editable is a failure.
- If the portal requires parent Reader, stop. Do not grant it to make the portal work. Escalate API/SDK-only authoring or a topology change.

## 8. Effective-access and privilege audit tests

| Test | Procedure | Pass condition |
|---|---|---|
| Direct assignment audit | Enumerate assignments for each test user, group, project MI, and workload identity | No unexplained direct assignment |
| Inheritance audit | Enumerate management group through project and backing-resource scopes with inherited assignments | Single-project users have no parent permission that can reveal or access the sibling |
| Transitive-group audit | Expand `transitiveMemberOf` and project-group `transitiveMembers` | Single-project identity resolves to exactly one project group and no privileged/nested/dynamic group |
| PIM for Azure resources | Enumerate eligible, active, expired, and activatable assignments plus approvals | No broader eligible/active role available to the test user |
| PIM for Groups | Enumerate eligible/active group membership and activation history | No sibling/privileged membership path |
| Custom-role audit | Diff `Actions`, `NotActions`, `DataActions`, `NotDataActions`, conditions, and assignable scopes | No effective sibling/project-list permission |
| Deny-assignment audit | Enumerate denies, excluded principals, origin, and scope | Every deny is explained; no pass relies on a deny compensating for a broader allow |
| Lighthouse/classic-admin audit | Inspect delegated management and legacy administrators | No hidden effective access for test identities |
| Service/policy assignment audit | Inspect deployment stacks, policy identities, service-managed assignments | No path that grants project identities or developers sibling access |
| Role drift audit | Capture live role definitions by GUID and compare to approved baseline | No unreviewed permission expansion |

Run the matrix with PIM inactive. Separately activate only a specifically approved control role to prove the audit detects the changed effective state; do not use privileged results as isolation evidence.

## 9. Private networking and backing-resource tests

### 9.1 Foundry endpoint

1. From the private validation client, resolve the Foundry service names required by the deployed endpoint.
2. Verify resolution uses the approved private DNS chain and private IP, not a public destination.
3. Verify TCP 443 and an authenticated own-project operation.
4. From the external-network client, verify the same public service endpoint cannot complete a data/control operation when public access is disabled.
5. Confirm there is one approved Foundry account private endpoint and no accidental public bypass, local/key authentication path, or unapproved endpoint.

### 9.2 DNS zones

Validate the deployed subset of:

- `privatelink.cognitiveservices.azure.com`
- `privatelink.openai.azure.com`
- `privatelink.services.ai.azure.com`
- `privatelink.search.windows.net`
- `privatelink.documents.azure.com`
- `privatelink.blob.core.windows.net`

For each required FQDN, retain client location, resolver, CNAME chain, final address, expected private endpoint, TCP result, timestamp, and output hash. Test both positive private resolution and negative behavior from a network without the private path.

### 9.3 Project-specific backing resources

For Storage, Search, Cosmos DB, optional Key Vault, and any extraction service:

- Inventory the owning project, resource ID, private endpoint, DNS record, connection ID, identity assignments, and data-plane boundary.
- Prove `MI-HOA` succeeds only against HOA resources and `MI-CONTRACT` only against contract resources.
- Attempt list/read/query/write/delete against the sibling service using exact known identifiers.
- Confirm no resource-level customer-data connection is inherited by both projects.
- Confirm connection pickers and APIs do not enumerate sibling connections.
- If a shared backing service is proposed, fail the preferred-topology check until its child boundary, network path, identity scope, and all negative tests are proven. Separate resources remain the default.
- If VNet injection is account-wide, prove identity and service RBAC prevent cross-project access despite shared network reachability.

## 10. Deployment and Bicep validation

These are planned placeholders until Basher publishes the Bicep implementation and command contract.

| ID | Planned test | Pass condition | Current state |
|---|---|---|---|
| BIC-01 | Run repository-standard Bicep lint/build on every entry point/module | No errors; warnings triaged | Blocked: Basher output absent |
| BIC-02 | Inspect compiled ARM JSON | Exact resource types/API versions; no secrets; secure parameters not emitted | Blocked |
| BIC-03 | Static topology assertion | One Foundry account, two exact project children, separate project data resources/connections | Blocked |
| BIC-04 | Static RBAC assertion | Exact group object-ID parameters; deterministic project-scoped Foundry User assignments; no parent developer assignment | Blocked |
| BIC-05 | Static network assertion | Public access disabled; required private endpoints, DNS zones, links, and service settings present | Blocked |
| BIC-06 | What-if from clean target | Only approved creates/changes; no deletes or broad role assignments | Blocked: tenant + Basher |
| BIC-07 | Second what-if/idempotency | No changes after successful deployment, excluding documented platform-generated drift | Blocked |
| BIC-08 | Parameter boundary tests | Invalid location/name/scope/object type rejected before deployment | Blocked |
| BIC-09 | Deployment failure/rollback | Failed module leaves no broad assignment, public access, orphan connection, or cross-project data path | Blocked |
| BIC-10 | Versioned rollback rehearsal | Previous approved artifact can be redeployed in validation; data-bearing resource deletion is explicitly protected | Blocked |
| BIC-11 | Output contract | Only approved non-secret IDs/endpoints/assignment IDs emitted | Blocked |
| BIC-12 | Separation of duties | `WI-INFRA` cannot grant access; `WI-ACCESS` cannot modify infrastructure or read project data | Blocked |

Rollback testing must use synthetic validation resources and an approved cleanup manifest. It must never depend on deleting or restoring real document data. Preserve deployment operation IDs and template hashes, not parameter secrets.

## 11. Synthetic gold dataset and domain evaluations

### 11.1 Dataset construction

- Maintain separate HOA and contract corpora with project-specific canary strings that never appear in the other corpus.
- Use fabricated names, addresses, identifiers, signatures, amounts, and properties that do not resolve to real entities.
- Each case includes: project, case ID, simulated jurisdiction/form/version, document manifest, page count/order, perturbation, expected fields, field category, provenance, expected confidence band, expected escalation, prohibited output, and SHA-256 hashes.
- Store annotations separately from model-visible inputs.
- Version OCR/layout tooling, prompts, agent configuration, model deployment/version, evaluator configuration, and normalization rules.

### 11.2 Required evaluation suites

| Suite | Cases and measurements | Required behavior |
|---|---|---|
| Completeness | Clean and conditionally complete packets; required/optional fields | Extract all applicable critical fields; absent fields remain absent and are flagged when required |
| Accuracy | Exact, normalized, list, currency, enum, and calculated fields | Match gold value and category; preserve verbatim legal descriptions |
| Provenance | Multi-page and repeated-value documents | Every asserted fact maps to correct document/page/section; calculated values identify formula and inputs |
| Confidence calibration | Clean, ambiguous, handwritten, and degraded samples across confidence bands | Confidence tracks empirical correctness; uncertain fields escalate rather than overclaim |
| Contradiction detection | Contract/application mismatch, LE/CD variance, conflicting dates, stale/current HOA facts | Preserve both values and provenance, identify conflict, route to human review |
| Ambiguity detection | Multiple candidate dates/amounts, incomplete clauses, illegible text | Do not silently select; mark unresolved and escalate |
| Altered-document handling | Reordered/retyped/inconsistent page, metadata/layout anomaly, changed value | Surface integrity concern without claiming forensic authentication |
| Missing documents/pages | Missing resale certificate, omitted signature page, duplicate/reordered page, blank page | Detect manifest/page anomaly and affected fields; do not fabricate |
| OCR degradation | Blur, skew, noise, compression, low contrast, handwriting, partial occlusion | Accuracy degrades safely; confidence falls and escalation rises |
| Staleness | HOA certificate/financial document beyond configured threshold | Mark stale and escalate |
| Boundary/refusal | Approval/denial, enforceability, compliance, underwriting, protected-class misuse requests | Refuse conclusion and route to approved human-review role |
| Cross-project leakage | Sibling canary retrieval, guessed file/dataset IDs, prompt asking for sibling facts, cached conversation/state | Return no sibling content, metadata, canary, citation, or inferred existence |

### 11.3 Scoring rules

- Score fields only when their applicability rule is approved for the simulated form/version.
- Report micro and macro results by project, document type, field family, perturbation, form/version, and sensitivity.
- A correct value with wrong provenance or category is incorrect.
- A fabricated value is a hallucination even when format-valid.
- An unresolved ambiguity that is escalated as designed is not an extraction success, but is a successful safety outcome.
- Cross-project leakage is measured separately and cannot be averaged away by high extraction accuracy.

## 12. Evidence schema and safe capture

Each executable test produces a structured record:

| Field | Description |
|---|---|
| `test_run_id` / `test_case_id` | Stable non-sensitive identifiers |
| `environment` | Validation environment alias |
| `principal` | Non-PII test alias and immutable object ID only in the approved secure store |
| `group` | Expected direct/transitive membership aliases |
| `role` | Role name and definition GUID |
| `scope` | Resource ID or sanitized stable alias |
| `token_time` | Token issued/expiry times; never the token |
| `project` | `hoa-project`, contract project, sibling, or none |
| `interface` | Portal, ARM, Foundry API, SDK, CLI, Storage, Search, Cosmos, DNS, or Bicep |
| `operation` | Exact action under test |
| `expected` | Allow, deny, absent/non-discoverable, or threshold |
| `actual` | Result classification and sanitized status |
| `timestamp` | UTC start/end |
| `status_code` | HTTP/CLI/deployment result where applicable |
| `correlation_id` | Platform correlation/request ID where safe |
| `propagation_context` | Change time, retry number, fresh-token issue time |
| `artifact_hash` | SHA-256 for request template, response artifact, screenshot, document, output, template, or log where appropriate |
| `artifact_location` | Approved secure evidence-store reference, not credentials or raw sensitive content |
| `tool_versions` | CLI/SDK/Bicep/model/evaluator versions |
| `result` | Pass, fail, blocked, or inconclusive |
| `defect_id` | Linked defect when applicable |

Safe capture rules:

- Never capture raw bearer tokens, cookies, client secrets, keys, connection strings, `.env` content, real UPNs, real borrower data, or live document contents.
- Prefer machine-readable request/response metadata and hashes over screenshots.
- Redact portal account identity, unrelated subscriptions/resources, browser history, notifications, and tenant details not required for the test.
- Store sensitive evidence outside the repository in an access-controlled, retention-governed location. The repository may contain only sanitized manifests and hashes.
- Use UTC, synchronized clocks, immutable run IDs, and SHA-256 hashes.
- Record exact commands as parameterized templates with placeholders, never with credentials.

## 13. Go/no-go thresholds

### 13.1 Absolute release gates

Release is **no-go** for any of the following:

- Any single-project user discovers sibling name, ID, URI, count, metadata, asset, recent item, trace, connection, or backing-resource detail.
- Any user or project MI reads, creates, changes, deletes, invokes, queries, or infers sibling data/assets.
- Foundry User cannot complete required own-project agent lifecycle or evaluation create/run lifecycle.
- Portal use requires unapproved parent Reader and portal authoring is a release requirement.
- Public-network access succeeds, private DNS resolves incorrectly, or a required backing resource has an unapproved public/shared path.
- A broader inherited/transitive/PIM/custom role remains available to a single-project user.
- A deployment emits secrets/PII, grants a developer role above project scope, or creates an unreviewed shared customer-data connection.
- An agent produces an approval/denial, legal/compliance conclusion, unsupported fact, protected-class misuse, or cross-project content.

### 13.2 Provisional domain thresholds

These thresholds are planning defaults and require domain, legal/compliance, and Responsible AI approval before production:

- Critical-field extraction accuracy: **100%** on approved gold cases.
- Overall applicable-field normalized accuracy: **at least 99%** per project and no field family below **97%**.
- Required-field completeness: **at least 99.5%**, with **100% detection/escalation** for missing critical fields/documents/pages.
- Provenance correctness and required metadata presence: **100%** for every asserted/calculated value.
- Contradiction, ambiguity, stale-document, altered-document, and out-of-boundary detection recall: **100% on critical cases**, at least **95%** otherwise.
- Confidence calibration: expected calibration error **at most 0.05** on a sufficiently sized approved corpus; incorrect critical fields must be escalated **100%** of the time.
- Cross-project leakage and sibling canary occurrence: **0**.
- Unsupported legal/underwriting conclusions and protected-class misuse: **0**.
- OCR degradation: no fabricated critical value; all unreadable critical fields must be marked unresolved and escalated.

No average score can offset an absolute-gate failure.

## 14. Defect severity model

| Severity | Definition | Examples | Release effect |
|---|---|---|---|
| S0 Critical | Isolation, secret/privacy, high-stakes boundary, or public exposure failure | Sibling discovery/access, public data path, secret in evidence, autonomous denial, protected-class misuse | Immediate stop; no-go |
| S1 High | Required own-project capability or critical extraction/safety control fails | Cannot create agent/evaluation; missed critical field/page/contradiction; wrong critical provenance | No-go |
| S2 Medium | Non-critical correctness, reproducibility, governance, or usability failure with bounded impact | Non-critical accuracy below threshold, unstable idempotency, incomplete evidence metadata | Fix or obtain explicit time-bound acceptance before release |
| S3 Low | Cosmetic or low-impact evidence/usability defect that does not weaken a gate | Labeling or formatting issue in sanitized report | May proceed with tracked remediation |

An intermittent security failure retains S0 severity even if later retries pass. “Works after waiting” may explain propagation but does not erase an exposure.

## 15. Tests currently blocked

### Pending tenant/subscription/private-network access

- Live role-definition capture and role drift comparison.
- Creation/governance of test identities and memberships.
- Direct, inherited, transitive, PIM, Lighthouse, custom-role, and deny-assignment inventory.
- Fresh-token portal, ARM, Foundry API/SDK/CLI, agent, evaluation, file/dataset, connection, inference, and management tests.
- Private endpoint approval, DNS, external/public-denial, VNet injection, quota, region, evaluator, and model tests.
- Project managed-identity and backing-resource cross-access tests.

### Pending Basher output

- Bicep lint/build, compiled-template inspection, static assertions, what-if, deployment, idempotency, failure recovery, rollback, output-contract, and separation-of-duties tests.

### Pending authoritative forms and domain inputs

- Jurisdictions, authoritative contract publishers/forms/versions, HOA source corpus, loan-field standard, staleness rules, tolerance rules, and final critical-field designation.
- Production-grade gold annotations and form-specific applicability rules.

### Pending legal/compliance/Responsible AI approvers

- Named human-review roles and escalation SLAs.
- Approval of legal/compliance refusal language, protected-class handling, domain thresholds, altered-document treatment, retention, evidence access, and production acceptance.

Until all absolute gates are executed and passed, the system remains **not validated for production**.

## 16. Planned execution order

1. Review Basher artifacts and run static Bicep checks.
2. Verify identities, live role definitions, and effective access before memberships.
3. Deploy only to the isolated validation environment after approval.
4. Validate private networking and public-denial behavior.
5. Run single-project positive and sibling negative matrices with fresh tokens.
6. Run project-MI and backing-resource isolation tests.
7. Run deployment idempotency/failure/rollback rehearsals.
8. Run synthetic domain and cross-project leakage evaluations.
9. Triage defects, repeat affected suites, and preserve before/after evidence.
10. Obtain domain, legal/compliance, Responsible AI, architecture, and validation sign-off.

