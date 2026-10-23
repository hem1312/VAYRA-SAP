# VAYRA — Read-Only Integration Readiness

**Status date:** 2026-10-04 · **Phase:** 2 (Reliability, Evaluation & Hardening)

> **⚠️ SUPERSEDED (Phase 3, 2026-10-05):** as of Phase 3, VAYRA ships a strictly
> read-only SAP *observation* layer (mock adapter + GET-only OData adapter,
> deny-by-default policy engine, capability gating, normalization, audit). No
> sandbox is connected yet. The statement "there is no connection to any SAP
> system" below is now historical; the standing security statement — **no write,
> no transaction execution, no data modification, production never touched** —
> is unchanged and now enforced in code. See `SAP_INTEGRATION.md`.

## What this document is (and is not)

This document states what VAYRA is ready to do with respect to SAP systems and
what it explicitly does **not** do.

> **VAYRA does not integrate with SAP.** There is no connection to any SAP
> system, no RFC/BAPI/OData call-out, no transaction execution, and no data
> write of any kind. Nothing in this repository is an SAP integration, and
> nothing here should be read as one. This document is a *readiness*
> statement for a strictly read-only, human-mediated usage mode.

## Ready now (verified, offline, demo provider)

1. **Read-only, human-mediated consulting.** A consultant pastes what they can
   already see in their SAP GUI — error codes, dump analysis (ST22), messages,
   configuration screenshots' text, ABAP snippets — and VAYRA returns routed,
   validated analysis. Verified e2e: 4/4 consult scenarios (2026-10-04,
   `scripts/e2e_consult.py`).
2. **Deterministic routing and validation.** 101/101 golden cases pass; the
   intent router, cross-module dependency engine, ABAP/ST22 analyzers, and the
   validation layer run fully offline. See `VAYRA_RELIABILITY_REPORT.md`.
3. **Grounded answers only.** Fabricated T-codes, BAPI function modules, SAP
   Note numbers, and customer objects are flagged as unverified, never
   asserted; unevidenced configuration claims are replaced with an explicit
   insufficiency notice (`INSUFFICIENT_KNOWLEDGE_MSG`).
4. **Ask-don't-guess behavior.** Ambiguous or incomplete requests are flagged
   unreliable and answered with targeted clarifying questions, not guesses.

## Explicitly not implemented (no integration exists)

- **No SAP connectivity of any kind.** No `pyrfc`/`sapnwrfc`, no RFC SDK, no
  OData/HTTP client pointed at SAP, no credentials handling for SAP logon.
- **No transaction execution.** VAYRA can suggest which T-code a consultant
  might inspect; it can never run it, post a document, or change data.
- **No write path.** There is no code path that mutates data in any SAP or
  external system — by design, not by configuration.
- **No system-of-record access.** VAYRA's knowledge is a curated local corpus
  (19 chunks, verified) — not a live SAP system, table, or system snapshot.

## Hard guarantees (spec §20, verified 2026-10-04)

| Check | Result |
| --- | --- |
| SAP connector dependencies in `requirements.txt` | none |
| Outbound SAP hosts / RFC gateways in `app/` | none |
| LLM provider in `backend/.env` | `demo` (isolated per-test env in CI) |
| Vector store access during evaluation | forced offline (`_InertVectorStore`) |
| Write/execute paths toward SAP | none exist |

## If read-only connectivity is ever added (future work, not present)

Any future enhancement must preserve, in order: read-only access scope
(SE16N-style read or API read), explicit user consent per connection, no
credential persistence, allow-listed RFC/BAPI reads only, and the existing
validation layer as the final gate on anything returned. None of this exists
today; this section is a design constraint, not a status claim.
