# Loan Document Requirements — Domain Plan

**Owner:** Reuben (Loan Origination & Residential Documents SME)
**Status:** Draft for team review — feeds Rusty (Foundry/agent design), Rai (RAI controls), Linus (validation)
**Scope:** Domain requirements only. No agents are built by this document. No legal advice, underwriting decisions, or eligibility determinations are made here or by any agent this plan describes.

## 0. How to read this document

- Two isolated use cases are in scope: `hoa-project` and `one-to-four-residential-contract-project`. Every schema below is tagged by which project(s) it applies to. Fields are **not** shared across project data stores even where the underlying concept (e.g., "party name") is similar — see Danny's design review isolation rule.
- The initial agent boundary is **document intake, extraction, and quality control (QC) only**. Agents built from this plan must never issue an approval/denial, a credit or eligibility decision, or a legal/compliance determination. Anywhere a judgment call is required, the correct output is a flag routed to a named human-review owner, not a conclusion.
- Jurisdictions, authoritative form versions, the HOA source corpus, the loan-field standard, and human approvers are **TBD** and owned by Carol. This document defines the *shape* of the requirements and the checklist to fill in those specifics — it does not assert that any single national field list is legally sufficient. See §7 (onboarding checklist) and §8 (risks/non-goals).
- Where an authoritative public source exists, it is cited. Field descriptions are paraphrased category-level requirements, not reproductions of copyrighted form text (e.g., no verbatim URLA/GSE/state form language).

---

## 1. Loan-origination lifecycle boundaries (intake / extraction / QC scope)

The residential mortgage origination lifecycle is broader than what this project's agents may touch. The table below marks the stages relevant to `one-to-four-residential-contract-project` document work and draws an explicit line around what the agents may and may not do.

| Stage | In scope for extraction/QC agents? | Notes |
|---|---|---|
| 1. Pre-qualification / pre-approval intake | Partial — extract borrower-provided application data as document-derived facts | No creditworthiness judgment |
| 2. Purchase contract execution (one-to-four family) | Yes — full contract taxonomy (§3) | Extraction + completeness/consistency QC |
| 3. Loan application (URLA/Form 1003 and equivalents) | Yes — field extraction and normalization | See §4.1–4.6; CFPB/Fannie Mae/Freddie Mac forms are the reference structure ([URLA overview](https://singlefamily.fanniemae.com/originating-underwriting/uniform-residential-loan-application), [Freddie Mac ULAD](https://sf.freddiemac.com/tools-learning/uniform-mortgage-data-program/ulad)) |
| 4. Disclosures (Loan Estimate, initial TRID) | Yes — extraction and cross-check against contract/application, flag mismatches | Reg Z §1026.37 defines LE content ([eCFR §1026.37](https://www.ecfr.gov/current/title-12/chapter-X/part-1026/section-1026.37)); agents extract/compare, never certify compliance |
| 5. Verification (income, employment, assets, appraisal, title) | Partial — extract values from verification documents; no independent verification performed | Human/automated underwriting systems remain authoritative |
| 6. Underwriting decision (credit/eligibility/DTI/LTV determination) | **Out of scope — excluded by design** | Agents may surface extracted values that feed underwriting; agents never compute or state a decision |
| 7. Closing Disclosure and closing | Yes — extraction and cross-check against Loan Estimate and contract (Reg Z §1026.38, [eCFR §1026.38](https://www.ecfr.gov/current/title-12/chapter-X/part-1026/section-1026.38)) | Timing/tolerance rule compliance is a human/compliance-system responsibility |
| 8. Post-closing / servicing handoff | Out of scope for this plan | Not part of either named project |
| HOA document review (any stage where HOA/condo property is involved) | Yes — full HOA taxonomy (§2) | Runs in `hoa-project`, cross-referenced into the contract project via an addendum reference field, not a shared data store |

**Boundary statement (binding on agent design):**
1. Agents extract, normalize, and quality-check document content. They **never** approve, deny, conditionally approve, price, or recommend approval/denial of a loan or a contract contingency.
2. Agents **never** issue a legal opinion (e.g., "this HOA restriction is enforceable," "this contract clause is valid in this state"). They surface the clause/fact and its source; a licensed/qualified human makes the determination.
3. Agents **never** make a fair-lending-relevant inference from protected-class data (e.g., URLA Section 8 demographic fields) beyond verbatim extraction for the specific, government-mandated reporting purpose; no agent may use these fields to influence any other extraction, scoring, or QC outcome.
4. Any field whose interpretation depends on jurisdiction, investor overlay, or lender policy is marked `human-review-required` by default until the source-authority onboarding (§7) supplies an authoritative rule.

---

## 2. HOA document taxonomy (`hoa-project`)

HOA/condominium disclosure content is governed primarily by **state statute** plus the association's own governing documents; there is no single federal form. Typical categories (state statutes vary on which are mandatory, turnaround time, and who pays) ([HOA resale package overview](https://www.rowcal.com/news/hoa-resale-package/), [state-by-state disclosure survey](https://buildmylisting.com/hoa-disclosure-requirements-2026), [industry legal overview](https://rexera.com/blog/hoa-state-legislation/)):

| Category | Typical contents | Jurisdiction-dependent? |
|---|---|---|
| **Declarations / CC&Rs** (Covenants, Conditions & Restrictions) | Recorded foundational restrictions, use limitations, architectural standards, easements, amendment history | Yes — recording jurisdiction and amendment recency vary |
| **Bylaws** | Governance structure, board powers, voting/quorum rules, officer terms, meeting requirements | Yes |
| **Rules & regulations** | Day-to-day operational rules (parking, pets, rentals, exterior modification approvals) | Yes — frequently amended, version-sensitive |
| **Budgets / financial statements** | Annual operating budget, reserve study/fund status, audited or reviewed financials | Yes — audit requirement thresholds vary by state |
| **Assessments** | Regular assessment amount/frequency, special assessment history and approved-but-not-yet-imposed items, delinquency status for the specific unit | Unit-specific; always requires per-property lookup |
| **Resale / status certificates (estoppel)** | Point-in-time confirmation of dues paid, violations, pending assessments, transfer fees | Yes — statutory turnaround windows (commonly 5–14 business days) differ by state |
| **Insurance** | Master policy coverage summary, fidelity bond, what the association vs. unit owner must insure | Yes |
| **Litigation** | Pending or threatened litigation involving the association | Always must be current as of certificate date |
| **Meeting records** | Minutes of board/annual meetings bearing on the unit or pending changes | Optional in many jurisdictions |
| **Management / contact details** | Managing agent name, contact info, association contact, fee schedule for document requests | Not sensitive; still project-scoped data |
| **Jurisdiction-specific equivalents** | E.g., condominium-specific statutory disclosure packages, co-op equivalents (proprietary lease, stock certificate, recognition agreement), state addenda | Requires per-state/per-property-type mapping — TBD in §7 |

**Extraction/QC note:** Every HOA fact is unit-specific and time-sensitive (assessments/litigation/insurance can change). The pipeline must capture and display the **as-of date** of each source document and flag anything older than a configurable staleness threshold (initial default: 60 days, TBD pending source-authority sign-off) for human review rather than silently reusing stale data.

---

## 3. One-to-four family residential contract taxonomy (`one-to-four-residential-contract-project`)

Residential purchase contracts are state/association-specific forms (e.g., state Realtor association or brokerage commission forms); no universal federal contract exists. The categories below are the common structural elements found across jurisdictions' one-to-four family contracts, described generically (no copyrighted form text reproduced):

| Category | Elements |
|---|---|
| **Parties** | Buyer(s), seller(s), agents/brokers, entity vs. individual capacity, representation disclosures |
| **Property / legal description** | Street address, legal description (lot/block/subdivision or metes-and-bounds), parcel/APN, included/excluded fixtures and personal property |
| **Price / earnest money** | Purchase price, earnest money amount, holder/escrow agent, deposit deadlines, refund conditions |
| **Financing** | Financing contingency type (conventional/FHA/VA/USDA/cash), loan amount/LTV assumptions, financing deadline, appraisal contingency |
| **Title / survey** | Title commitment/policy requirements, survey requirement and type, title objection period and cure process |
| **Inspections** | Inspection period/deadline, inspection types (general, wood-destroying insect, environmental, well/septic), repair negotiation/termination rights |
| **Disclosures** | Seller property condition disclosure, lead-based paint (pre-1978 federal requirement), natural hazard/environmental disclosures, HOA disclosures, other state-mandated disclosures |
| **HOA / addenda** | HOA addendum reference, resale certificate delivery/review period, transfer fee allocation — cross-references `hoa-project` output by reference ID, not shared storage |
| **Closing / possession** | Closing date, possession date/time, occupancy-after-closing terms |
| **Prorations** | Property tax, HOA dues, utilities, rents proration method and effective date |
| **Defaults / remedies** | Buyer/seller default consequences, specific performance vs. liquidated damages (earnest money), notice-to-cure requirements |
| **Notices** | Required notice method, addresses for notice, timing rules |
| **Signatures** | Execution dates, all-party signature status, counterpart/electronic signature acknowledgment |
| **Deadlines** | Consolidated deadline/contingency table (financing, inspection, appraisal, title objection, closing) with computed vs. stated dates |
| **Form / jurisdiction metadata** | Form publisher, form version/edition date, state/jurisdiction, addenda attached, amendment history |

**Extraction/QC note:** Deadlines are the highest-value/highest-risk field family — they are frequently defined relative to another event ("10 days after effective date") rather than as an absolute date. The pipeline must extract both the **stated rule** and a **calculated absolute date**, tag the calculated date as `calculated`, and flag any internal inconsistency (e.g., calculated closing date precedes calculated financing deadline) for human review.

---

## 4. Canonical field dictionary

This is a **structural standard**, not a finished field list — the authoritative loan-field standard (e.g., MISMO alignment) is TBD (§7). Every field entry in the eventual schema must record the eight attributes below. Field families are grouped as requested; each family includes representative fields with these attributes filled in as illustrative examples.

### 4.0 Required attributes per field (schema contract)

Every canonical field must declare:
1. **Datatype** — string, enum, date, currency/decimal, boolean, structured object, or document reference.
2. **Requiredness model** — not a blind `required: true`. Use a conditional expression, e.g., `required_if(loan_purpose == "purchase")`, `required_if(property_type == "condo")`, or `optional_but_flag_if_absent`. Default posture for any field lacking an approved rule: `unknown — human-review-required`.
3. **Source document(s)** — which document type(s) this field may be extracted from, in priority order if more than one document could supply it.
4. **Extraction/normalization rules** — parsing/matching approach and canonical format (e.g., ISO 8601 dates, ISO 4217 currency, E.164 phone).
5. **Validation checks** — format checks, cross-field consistency checks, cross-document consistency checks.
6. **Sensitivity class** — `public`, `internal`, `confidential-PII`, `confidential-financial`, or `restricted-protected-class`.
7. **Escalation trigger** — the condition that routes the field to human review, and to whom (role, not name, pending §7).

### 4.1 Borrower / party

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Full legal name | string | required for all named parties | URLA/1003 §1; contract signature block | Split given/middle/family; normalize suffixes | Cross-check spelling consistency across application vs. contract vs. ID | confidential-PII | Name mismatch across documents → human review |
| Marital status | enum (married/unmarried/separated) | required_if(jurisdiction is community-property state) | URLA/1003 §1 | Map to controlled vocabulary | Must be consistent with co-borrower relationship field | confidential-PII | Ambiguous/unlisted status → review |
| Contact info (address/phone/email) | structured object | required | URLA/1003 §1; contract | Normalize address (USPS-style), E.164 phone | Address parses to valid postal format | confidential-PII | Undeliverable/invalid format → review |
| Entity party (non-natural person buyer/seller) | structured object | optional_but_flag_if_absent when contract names an entity | Contract signature block, authority documents | Extract entity name, type, signatory authority | Signatory authority document present? | confidential-PII / internal | Missing authority evidence → review |
| Representation (agent/broker) disclosure | structured object | required_if(jurisdiction mandates written disclosure) | Contract | Extract agent name, license #, brokerage, represented party | License # format check | internal | Missing required disclosure → review |

### 4.2 Property

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Property address | string | required | Contract, URLA/1003 §4, HOA cert | Normalize to standardized postal format | Must match across contract/application/HOA cert | internal | Mismatch across documents → review |
| Legal description | string | required | Contract, title docs | Preserve verbatim (legal descriptions are not paraphrasable) | Present and non-empty | internal | Missing/illegible → review |
| Parcel / APN | string | required_if(jurisdiction assigns APN) | Contract, tax records | Normalize per county format | Checksum/format validity if county publishes one | internal | Invalid/missing format → review |
| Property type (SFR/condo/co-op/2-4 unit) | enum | required | Contract, URLA/1003 §4 | Map to controlled vocabulary | Must be consistent with HOA-required flag | internal | Ambiguous type → review |
| Included/excluded fixtures | list<string> | optional | Contract | Extract itemized list | None beyond presence check | internal | n/a |
| HOA-governed flag | boolean | required_if(property_type in condo/PUD) | Contract, HOA addendum | Derived from property type + addendum presence | Must trigger `hoa-project` cross-reference when true | internal | Flag true but no HOA addendum found → review |

### 4.3 Transaction / contract

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Purchase price | currency | required | Contract | ISO 4217 currency, 2 decimal places | Must be positive; compare to appraisal/LE loan amount ratio | confidential-financial | Price absent or non-numeric → review |
| Earnest money amount/holder | structured object | required | Contract | Extract amount + holder identity | Holder must be a named, licensed entity per contract terms | confidential-financial | Holder not identified → review |
| Financing contingency type | enum | required_if(loan_purpose == "purchase") | Contract | Map to conventional/FHA/VA/USDA/cash | Must be consistent with URLA loan type field | internal | Mismatch vs. application loan type → review |
| Contingency deadlines (financing/inspection/appraisal/title) | date (calculated + stated rule) | required | Contract | Extract stated rule; compute absolute date from effective date | Internal date-ordering consistency (see §3 note) | internal | Ordering conflict or unresolvable relative rule → review |
| Closing date | date | required | Contract | ISO 8601 | Must not precede any contingency deadline | internal | Conflict → review |
| Default/remedy clause | structured object / enum | optional_but_flag_if_absent | Contract | Extract remedy type (specific performance/liquidated damages) | Presence check only — no legal interpretation performed | internal | n/a — never auto-interpreted |

### 4.4 Loan terms

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Loan amount | currency | required | URLA/1003 §4, Loan Estimate (Reg Z §1026.37) | ISO 4217 | Compare against purchase price/LTV assumption | confidential-financial | Missing or inconsistent with contract price → review |
| Interest rate type (fixed/ARM) | enum | required | Loan Estimate | Controlled vocabulary | Must match AIR table presence if ARM | internal | n/a |
| Loan term (months) | integer | required | Loan Estimate | Integer months | Positive, plausible range (e.g., 60–480) | internal | Out-of-range → review |
| Loan purpose (purchase/refi/construction) | enum | required | URLA/1003 §4 | Controlled vocabulary | Must be consistent with contract presence (purchase requires a contract on file) | internal | Mismatch → review |
| Loan Estimate vs. Closing Disclosure figures | structured comparison | required_if(both documents present) | LE (§1026.37), CD (§1026.38) | Field-by-field diff | Flag any figure exceeding expected tolerance banding | confidential-financial | Any diff beyond configured threshold → compliance review (human) — agent never certifies TRID tolerance compliance |

### 4.5 Income / employment

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Employer name/address | string | required_if(employment_type == "employed") | URLA/1003 §1 | Normalize | Presence check | confidential-PII | n/a |
| Income type (base/bonus/commission/self-employed/other) | enum | required | URLA/1003 §1 | Controlled vocabulary | Self-employed flag must route to additional-document requirement (not evaluated here) | confidential-financial | Self-employed + missing supporting docs → review |
| Stated income amount | currency | required | URLA/1003 §1; verification docs (paystub/W-2/1099) if present | ISO 4217 | Cross-check stated vs. document-derived amount | confidential-financial | Variance beyond threshold → review (never auto-adjusted) |

### 4.6 Assets / liabilities

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Asset type/institution/balance | structured object | required_if(asset declared) | URLA/1003 §2 | Normalize institution name; ISO 4217 balance | Balance non-negative | confidential-financial | n/a |
| Liability type/creditor/balance/payment | structured object | required_if(liability declared) | URLA/1003 §2 | Normalize | Balance/payment non-negative | confidential-financial | n/a |
| Real estate owned (REO) | structured object | required_if(borrower owns other real estate) | URLA/1003 §3 | Normalize address, value, debt, rental income | Cross-check against liabilities list | confidential-financial | n/a |

### 4.7 Declarations / consents

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Declarations (bankruptcy/foreclosure/lawsuit/etc.) | boolean set | required | URLA/1003 §5 | Extract yes/no + explanation text verbatim | Any "yes" requires explanation text present | confidential-PII | "Yes" with no explanation → review |
| Acknowledgments/agreements consent | boolean | required | URLA/1003 §6 | Extract signed/unsigned status | Must be signed before downstream processing | internal | Unsigned → review |
| Demographic information (race/ethnicity/sex) | structured object | required_if(mandated by 12 CFR Part 1003 Appendix B) | URLA/1003 §8 | Verbatim extraction only | **No use beyond the specific government reporting purpose** ([Reg C Appendix B](https://www.consumerfinance.gov/rules-policy/regulations/1003/b/#b-1)) | restricted-protected-class | Any downstream use outside mandated reporting → blocked; escalate to Rai/compliance |

### 4.8 HOA (`hoa-project`)

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Regular assessment amount/frequency | currency + enum | required | Resale certificate, budget | ISO 4217, controlled frequency vocabulary | Non-negative | internal | n/a |
| Special assessment (approved, not yet imposed) | structured object | optional_but_flag_if_absent | Resale certificate | Extract amount, purpose, imposition date | Presence check | confidential-financial | Present but undated → review |
| Delinquency status (this unit) | boolean + currency | required | Resale certificate | Extract status + amount owed | Must be as of a stated certificate date | confidential-financial | Certificate date beyond staleness threshold → review |
| Pending litigation | structured object | required_if(disclosed) | Resale certificate, meeting minutes | Extract case description, status | Presence + currency of disclosure | internal | Any litigation disclosed → route to human review, never summarized as risk conclusion |
| Insurance coverage summary | structured object | required | Insurance certificate | Extract coverage type/limits | Presence check | internal | n/a |
| CC&R / bylaw amendment date | date | required | Declarations, bylaws | ISO 8601 | Must be the most recent recorded version available | internal | Version older than latest known recording → review |

### 4.9 Dates

| Field | Datatype | Requiredness | Source doc | Extraction/normalization | Validation | Sensitivity | Escalation trigger |
|---|---|---|---|---|---|---|---|
| Document effective date | date | required | All contract/HOA documents | ISO 8601 | Must be a valid calendar date | internal | Missing/invalid → review |
| Document as-of / certificate date | date | required for time-sensitive documents (HOA cert, financials) | HOA cert, budget, verification docs | ISO 8601 | Staleness threshold check (§2) | internal | Stale → review |
| Calculated deadline dates | date (derived) | required where contract states relative deadlines | Contract | Computed from effective date + stated offset | Must reconcile with any explicitly stated absolute date | internal | Conflict between stated and calculated date → review |

### 4.10 Provenance, confidence, validation status, human-review owner (cross-cutting metadata)

Every extracted field — regardless of family — must carry this metadata envelope:

| Metadata field | Datatype | Purpose |
|---|---|---|
| `source_document_id` | reference | Points to the specific ingested document and page/section the value was extracted from |
| `extraction_method` | enum (`ocr`, `layout-model`, `manual-entry`, `calculated`, `carried-forward`) | Distinguishes how the value was produced |
| `confidence_score` | decimal [0,1] | Model/pipeline confidence in the extraction |
| `validation_status` | enum (`unvalidated`, `passed`, `failed`, `human-overridden`) | Result of automated validation checks |
| `human_review_owner` | role reference (TBD in §7) | The role responsible for reviewing this field if escalated — never a hardcoded individual |
| `escalation_reason` | string/enum | Why the field was flagged, if applicable |
| `last_verified_at` | timestamp | Supports staleness checks |

---

## 5. Field-category distinctions (binding on all agent output)

Agent output must tag every value with exactly one of these four categories. Mixing categories without labeling is a design defect.

1. **Application fields** — self-reported by the borrower/party on an intake form (e.g., URLA declarations, stated income). Not independently verified by the agent.
2. **Document-derived facts** — values extracted verbatim or via direct normalization from a specific source document (e.g., purchase price from the contract, assessment amount from a resale certificate). Always carries `source_document_id`.
3. **Calculated values** — values the pipeline derives via a defined, auditable formula from one or more document-derived facts or application fields (e.g., a computed contingency deadline, an LE-vs-CD variance). Always carries the formula/method and inputs used.
4. **Analyst / legal conclusions** — judgments about enforceability, compliance, risk, or eligibility. **Agents never produce this category.** Any output that would fall here must instead be represented as a flagged, unresolved question routed to a named human-review role.

---

## 6. Synthetic / gold dataset plan and evaluation cases

**Principle:** No live borrower records, no real PII, no real HOA/contract documents from actual transactions. All gold data is synthetically generated or drawn from public specimen/sample forms, then intentionally varied to create evaluation cases.

### 6.1 Dataset construction
- Build synthetic document sets per project (`hoa-project`, `one-to-four-residential-contract-project`) using fabricated names, addresses, and figures that do not resolve to real people or properties.
- Cover at least: one clean baseline case per document type, and multiple perturbed variants (below) per document type.
- Store gold expected-output annotations (field values + category tag + expected escalation) alongside each synthetic document set, versioned with the form/jurisdiction metadata they simulate.
- Tag every synthetic case with a simulated jurisdiction/form version so evaluations can be filtered once §7's authoritative jurisdiction list is set.

### 6.2 Required evaluation case types

| Case type | Example | Expected agent behavior |
|---|---|---|
| **Clean/complete** | Fully populated contract + all HOA disclosures present and consistent | Extract all fields, no escalations |
| **Missing document** | HOA resale certificate absent but property is condo | Flag `HOA-governed flag = true` with missing source; escalate, do not fabricate values |
| **Missing field within a present document** | Contract present but closing date blank | Field marked absent, requiredness rule evaluated, escalate if required |
| **Contradictory documents** | Loan Estimate loan amount ≠ Closing Disclosure loan amount beyond tolerance; contract purchase price ≠ URLA purchase price | Flag cross-document mismatch, output both values with provenance, escalate — never silently pick one |
| **Ambiguous/illegible content** | Low-confidence OCR on legal description or handwritten date | Low `confidence_score`, `validation_status = failed` or `unvalidated`, escalate |
| **Modified/altered document** | Re-typed or edited page inconsistent with original formatting/metadata | Flag integrity concern, escalate — agent does not attempt authentication/forensic determination itself, only surfaces the anomaly |
| **Stale HOA certificate** | Certificate as-of date beyond staleness threshold | Escalate per §2/§4.8/§4.9 |
| **Relative-date resolution conflict** | "10 days after effective date" contradicts an explicitly stated absolute date elsewhere in the contract | Escalate per §3 note |
| **Protected-class field misuse attempt** | Prompt or downstream logic attempts to use demographic fields (§4.7) for a non-reporting purpose | Must be blocked; report to Rai |
| **Out-of-boundary request** | Any prompt asking the agent to approve/deny, or give a legal opinion | Must refuse and redirect to human review — this is a required negative test, not just a positive-path test |

### 6.3 Ownership
Reuben supplies the schema and initial gold-case designs; Linus builds the reproducible test harness/evidence pack; Rai supplies adversarial/fairness-oriented cases layered on top of these.

---

## 7. Source-authority onboarding checklist (blocks finalization — owned by Carol per open decisions §4 of Danny's design review)

Until each item below is answered by a named, authoritative human, the corresponding fields/rules stay in the default `unknown — human-review-required` posture:

- [ ] **Jurisdictions in scope** — which state(s)/counties will the pilot cover for HOA and contract documents? (Determines which statutes and form publishers apply.)
- [ ] **Authoritative contract form(s)** — which state/association-published one-to-four family contract form(s) and edition/version(s) are authoritative for the pilot?
- [ ] **HOA source corpus** — where do HOA documents come from (specific management companies, resale-certificate vendors, or association portals)? Confirms provenance and staleness-window defaults.
- [ ] **Loan-field standard** — will the canonical dictionary align to MISMO, an internal LOS schema, or another named standard? Confirms field naming/typing beyond this document's structural placeholders.
- [ ] **Human-review approvers** — named roles (not just titles) responsible for each escalation category (contract legal review, HOA compliance review, fair-lending/demographic-data governance, TRID tolerance compliance).
- [ ] **Staleness thresholds** — confirm or override the draft 60-day HOA certificate default and any equivalent thresholds for financial/verification documents.
- [ ] **Tolerance thresholds** — confirm the LE-vs-CD variance thresholds used for flagging (must reference Reg Z tolerance categories, not an arbitrary number).
- [ ] **Data residency/isolation confirmation** — confirm this schema will be implemented as two physically/logically separate project data stores per the design-review isolation rule, with no shared corpus between `hoa-project` and `one-to-four-residential-contract-project`.

---

## 8. Risks and non-goals

### 8.1 Non-goals (explicit exclusions)
- This plan does not produce or authorize an autonomous approval/denial, underwriting, or eligibility decision of any kind.
- This plan does not produce or authorize a legal opinion on enforceability, compliance, or interpretation of any clause, statute, or restriction.
- This plan does not assert a single, universal field list is sufficient across all lenders, investors, or jurisdictions — every field's applicability is conditional and subject to §7 onboarding.
- This plan does not include any real borrower, property, or HOA data; only synthetic/specimen data is in scope for evaluation.
- This plan does not define Azure/Foundry RBAC, IaC, or infrastructure — that is Rusty/Livingston/Basher's domain.

### 8.2 Risks
| Risk | Mitigation |
|---|---|
| **Fair lending** — protected-class or proxy data influencing extraction/QC outcomes | Demographic fields (§4.7) are extraction-only, reporting-purpose-only, `restricted-protected-class`; any other use is a blocked/Rai-escalated condition |
| **Privacy** — PII/financial data exposure across project boundaries | Confidential-PII/financial sensitivity classes drive per-project storage isolation (§0); no cross-project field sharing |
| **Legal interpretation drift** — agent output framed as advice by downstream consumers | Category tagging (§5) is mandatory; UI/consumer guidance (outside this doc's scope) must visibly label conclusions as unresolved/human-owned |
| **Underwriting-decision creep** — feature requests to "just flag likely denial" | Explicitly excluded in §1 boundary statement and §8.1; any such request requires a new, separately governed decision, not a silent extension of this plan |
| **Jurisdictional incompleteness** — schema built before §7 is resolved | Default-deny posture (`unknown — human-review-required`) prevents false confidence; schema versioned so onboarding updates don't silently change past evaluation results |
| **Stale/contradictory source documents** | Staleness thresholds, cross-document validation, and mandatory escalation (§4.9, §6.2) |
| **Synthetic data realism gap** | Synthetic data may not surface every real-world edge case; Linus's evidence pack should track known gaps and request additional case types as real (governed, non-PII) samples become available |

---

## References
- Fannie Mae URLA overview: https://singlefamily.fanniemae.com/originating-underwriting/uniform-residential-loan-application
- Freddie Mac Uniform Loan Application Dataset (ULAD): https://sf.freddiemac.com/tools-learning/uniform-mortgage-data-program/ulad
- CFPB Regulation C Appendix B (demographic/HMDA data collection): https://www.consumerfinance.gov/rules-policy/regulations/1003/b/#b-1
- eCFR 12 CFR §1026.37 (Loan Estimate content): https://www.ecfr.gov/current/title-12/chapter-X/part-1026/section-1026.37
- eCFR 12 CFR §1026.38 (Closing Disclosure content): https://www.ecfr.gov/current/title-12/chapter-X/part-1026/section-1026.38
- CFPB TILA-RESPA Integrated Disclosure (TRID) resources: https://www.consumerfinance.gov/compliance/compliance-resources/mortgage-resources/tila-respa-integrated-disclosures/
- CFPB Loan Estimate/Closing Disclosure forms and samples: https://www.consumerfinance.gov/compliance/compliance-resources/mortgage-resources/tila-respa-integrated-disclosures/forms-samples/
- HOA resale package overview (industry, non-authoritative — jurisdiction confirmation required): https://www.rowcal.com/news/hoa-resale-package/
- HOA disclosure requirements, state-by-state survey (industry, non-authoritative — jurisdiction confirmation required): https://buildmylisting.com/hoa-disclosure-requirements-2026
- HOA state legislation overview (industry, non-authoritative — jurisdiction confirmation required): https://rexera.com/blog/hoa-state-legislation/

> Note: Only the CFPB/eCFR/Fannie Mae/Freddie Mac sources above are treated as authoritative primary sources. HOA industry-blog sources are informational starting points only; §7 requires confirmation of an authoritative HOA source corpus per jurisdiction before these categories are treated as compliance-grade.
