# VAYRA
## AI-Powered SAP Consulting, Diagnostic, Implementation Planning & Controlled Automation Platform

**Project report — based on the actual repository state as of 2026-10-06 (commits `0a2c182` through `bdde838`).**

Every capability described here was verified against the code, tests, and documentation in this repository. Features that are planned, mocked, or not implemented are labeled as such. Where the historical plan and the repository disagree, the repository wins.

Legend used throughout:
- **IMPLEMENTED** — exists in code, backed by tests
- **SIMULATED/MOCKED** — implemented in code, but exercised against a mock or simulator, not a real SAP system
- **PARTIALLY IMPLEMENTED** — real code exists, but incomplete in scope or not exercised end-to-end against a real system
- **PLANNED / ARCHITECTURAL** — a designed boundary or placeholder exists; the capability itself does not
- **NOT IMPLEMENTED** — does not exist in the codebase

---

## 1. Executive Summary

VAYRA is a local, web-based platform that acts as an AI-assisted SAP consultant. You describe an SAP problem in plain language — a functional issue, a configuration problem, an ABAP dump, a cross-module puzzle — and VAYRA routes the question, retrieves relevant SAP knowledge from its own curated corpus, reasons over that evidence with a large language model (LLM), validates the answer, and produces a structured diagnosis with an implementation plan. Through Phase 4 it can also take that plan through a controlled execution pipeline: impact analysis, dry run, explicit human approval, step-by-step execution, verification, rollback, and a tamper-evident audit trail.

It exists because of a simple observation: a chatbot gives you an answer, but an SAP consultant gives you something different — an answer you can act on, with the evidence, risks, dependencies, missing questions, test steps, and approval path made explicit. Generic LLMs fail at this not because they lack knowledge, but because they have no mechanism to distinguish what they know from what they invented, no awareness of what they don't know about a specific customer system, and no concept of authorization. VAYRA wraps the LLM in deterministic machinery that supplies all three.

What has been completed through Phase 4:

- **Phase 1 — Consultant + RAG + Implementation Planning.** A consultant endpoint and UI with intent routing across six modes, retrieval-augmented reasoning over a curated SAP knowledge corpus, a structured response contract with per-claim evidence states, dependency and cross-module analysis, missing-information detection, and a strict implementation-plan contract.
- **Phase 2 — Reliability, Evaluation & Hardening.** A 101-case golden scenario suite with snapshot baselines and exit-code gates, a 26-case baseline evaluation, hallucination controls (fabricated BAPI warnings, INSUFFICIENT-evidence calibration), bounded retries, prompt-injection and structured-output validation. 561 automated tests pass.
- **Phase 3 — Read-Only SAP Integration.** A strictly read-only SAP observation layer: deny-by-default policy engine, capability gating, a deterministic mock adapter plus a GET-only OData adapter, normalization with sensitive-data filtering, audit logging, rate limiting and circuit breaking. SAP data enters answers as provenance-tagged, delimited observations. No SAP system is connected yet — this is the layer that *would* talk to one.
- **Phase 4 — Controlled SAP Execution & Automation.** A controlled execution engine that can validate a plan, estimate impact, dry-run it, obtain explicit plan-hash-bound human approval, execute steps one at a time against a simulator, verify each step, roll back declared-rollback steps, cancel, and produce a hash-chained audit report. Four automation levels are operable; a fifth ("autonomous") exists only as a placeholder that fails closed.

What VAYRA can currently do: everything above, end to end, on a local machine, with any of six LLM providers (including a deterministic offline demo provider). What it deliberately does not do: it does not connect to a real SAP system yet, it cannot write to SAP at all, and it never executes anything without a plan hash, an approval token, and a human decision on record.

The central philosophy:

> **DO NOT GUESS. RETRIEVE. REASON. VALIDATE. PLAN. VERIFY.**

And the security principle that governs every design decision:

> **"The LLM is responsible for reasoning; it is not responsible for authorization."**

The model proposes. Deterministic policy, human approval, and the execution engine decide what actually happens.

---

## 2. Project Origin

VAYRA started (commit `0a2c182`, 2026-10-01) as a transformation of an existing SAP *error diagnostic* agent — a tool that took an SAP error message and produced a normalized diagnosis — into something broader: an SAP functional + technical consultant platform.

The original idea was to help with the kinds of problems an SAP consultant actually gets asked about:

- **Functional problems** — pricing not appearing, billing documents not determining accounts, goods movements failing valuation.
- **Configuration issues** — missing condition records, closed posting periods, wrong account assignment in OBYC.
- **Technical problems** — ABAP runtime errors (ST22 dumps), performance problems, broken custom code.
- **ABAP-related issues** — code review of SELECT statements, nested loops, internal table handling.
- **Cross-module problems** — an SD billing issue that is really an FI account determination issue; a procurement issue that surfaces in accounting.
- **SAP implementation guidance** — not "what is SAP," but "what steps, in what order, with what risks, verified how?"

The founding limitation was recognized early: **a normal LLM can provide an answer, but an SAP consultant needs much more than an answer.** A consultant has to:

understand the business requirement; identify the affected SAP module; retrieve relevant knowledge; identify dependencies; distinguish facts from assumptions; identify missing information; diagnose the issue; propose configuration or technical changes; assess cross-module impact; define testing; verify the result; control execution; and maintain an audit trail.

No chat interface does any of that. A single prompt cannot enforce it. This realization shaped VAYRA's entire architecture: the LLM is one component inside a pipeline of deterministic, testable stages, each of which can fail loudly. The product is the pipeline, not the model.

---

## 3. Project Objective

VAYRA's objective is to function as an **AI-assisted SAP consultant** — a workstation tool that helps a person work through SAP problems with evidence and discipline — rather than a generic chatbot.

**Intended functional scope** (from the intent router in `backend/app/knowledge/intent.py`, which recognizes all of the following as functional domains): SD, MM, FI, CO, PP, QM, PM, PS, WM, EWM, HCM, TM, and S/4HANA.

**Implemented vs. architectural scope, honestly split:**

| Area | Depth |
|---|---|
| SD (pricing, billing/account determination, credit management) | **Deep** — dedicated knowledge documents, error-specific cases, eval coverage |
| MM (valuation/account determination, procure-to-pay) | **Deep** — dedicated knowledge documents and cases |
| FI (posting periods, GL) | **Deep** — dedicated knowledge documents and cases |
| CO (cost elements) | **Implemented** — dedicated knowledge document |
| PP (production order process, confirmations) | **Implemented** — dedicated knowledge documents |
| QM (inspection process) | **Implemented** — dedicated knowledge document |
| PM (maintenance process) | **Implemented** — dedicated knowledge document |
| Cross-module (SD–FI, procure-to-pay) | **Implemented** — dedicated integration documents, dependency analyzer |
| PS, WM/EWM, HCM, TM, S/4HANA | **Architectural scope** — recognized by the intent router and answerable from general LLM knowledge, but with no dedicated knowledge documents or eval cases yet |

**Technical scope:**

| Area | Depth |
|---|---|
| ABAP static analysis | **Deep** — a rule-based analyzer (`backend/app/abap/analyzer.py`) detecting SELECT *, FOR ALL ENTRIES misuse, nested loops over large tables, DELETE inside LOOP, package-size issues, SELECT SINGLE without WHERE |
| ST22 dump analysis | **Implemented** — a dedicated ST22 parser plus a dump-analysis methodology document |
| Debugging | **Implemented (knowledge)** — a debugging toolbox document guiding ST05/SAT/ATC usage; tools themselves are SAP-side, not reimplemented |
| Open SQL performance | **Implemented** — dedicated knowledge document + analyzer rules |
| BAPI | **Partial** — fabricated BAPI names are detected and warned (Phase 2), but no BAPI execution exists |
| CDS, AMDP, RAP, OData (development), IDoc, RFC, function modules, classes, interfaces, BAdIs, user exits, enhancements, authorization, jobs, spool | **Architectural scope** — the LLM can discuss them from internal knowledge, and the knowledge tree is designed to accept documents on them, but no dedicated tooling or corpus documents exist yet |

The distinction matters: VAYRA does not pretend to have expert depth where it has none. Where retrieval has no evidence, the response says so.

---

## 4. Initial Architecture

The repository is a two-service local application with a native desktop wrapper.

**Frontend** (`frontend/`) — a Next.js App Router application (React, TypeScript, Tailwind CSS) with a client-only React Three Fiber status visualization. Pages: `/` (new diagnosis), `/consult` (the consultant console), `/execution` (the Phase 4 execution console), `/history`, `/graph` (knowledge graph), and `/settings`. A PowerShell/batch desktop wrapper (`run-desktop.ps1`, installed shortcut) launches both services in a native WebView2 window; a browser mode also exists.

**Backend** (`backend/`) — a FastAPI service with Pydantic contracts, running on Python 3.14. Its main building blocks:

- **LLM service abstraction** (`llm_service.py`) — a `LLMService` interface with six adapters: `demo` (deterministic, offline), `openai`, `anthropic`, `deepseek`, `kimi`, and `ollama` (any OpenAI-compatible endpoint, defaulting to a local Qwen3-14B). The demo provider selects a knowledge profile by error-code prefix so different SAP messages produce genuinely different analyses while identical input always yields identical output — required by contract tests.
- **Response schemas** (`models.py`, `consultant_models.py`) — strictly validated Pydantic contracts. The legacy `DiagnosticResponse` (error-code pipeline) is untouched; the consultant answers through `ConsultantResponse`, which carries problem analysis, resolution steps, per-claim sources, ABAP analysis blocks, ST22 analysis, missing information, and an `implementation_plan`.
- **SAP knowledge** (`app/knowledge/`) — a curated corpus of 20 markdown/JSON documents covering the seven deep modules plus cross-module integration, T-codes, and technical/ABAP topics, with an ingestion pipeline and metadata for the knowledge graph.
- **Diagnostic workflow** (`orchestrator.py`) — the original error pipeline: normalize error → retrieve → diagnose with context → validate. It still runs and is fully preserved.

**How the architecture evolved:** the first version was a diagnostic interface — one endpoint, one contract, one shape of answer. Phase 1 added a second, parallel contract (the consultant) with routing, retrieval, and planning layered on top of the same LLM abstraction, deliberately without touching the legacy pipeline. Phases 3 and 4 then added two entirely new subsystems (`app/sap/`, `app/execution_engine/`) behind the same pattern: a narrow service facade, additive fields on existing contracts, and no modification of working Phase 1/2 behavior. The legacy seams (`execution.py`, `sap_connector.py`) still exist and still pass their original tests — evolution happened by addition, not rewrite.

---

## 5. Why RAG Was Introduced

An LLM's internal knowledge has three problems for SAP work: it is frozen at a training date, it is generic (your company's condition technique problem looks like every other one), and — worst — it is delivered in exactly the same confident prose regardless of whether the model actually knows.

Retrieval-Augmented Generation (RAG) is simple in idea: instead of asking the model to answer from memory, you first *retrieve* relevant documents from a corpus you control, paste them into the prompt as context, and instruct the model to ground its answer in that material. The model reasons; the corpus supplies the facts.

VAYRA's retrieval flow:

```
SAP Knowledge (curated markdown/JSON corpus)
→ Parsing / Chunking (ingestion pipeline)
→ Embeddings (BAAI/bge-m3 via an EmbeddingService)
→ Vector Store (Qdrant, local instance)
→ Retrieval (ConsultantRetriever, query-aware ranking)
→ Context assembly (bounded to a character budget)
→ LLM Reasoning (prompt contains evidence + question + output contract)
```

This matters in SAP specifically because SAP knowledge is dense with things a model must get *exactly* right: configuration dependencies (a pricing procedure condition type depends on access sequences, which depend on condition tables), transaction codes (OVKK, OBYC, VF03 — near-miss collisions are common), technical objects (message classes, IDoc types, BAPI names), module relationships (SD billing → FI accounting interface → GL account determination), and implementation procedures with a strict order of operations. A one-token slip on a T-code or a BAPI name is a wrong answer, and in SAP a wrong answer can become a wrong configuration.

VAYRA adds a second guard: retrieval marks each piece of evidence with an **evidence state** (see §6), and retrieval itself is evaluated (Phase 2 checks corpus retrieval relevance per golden case). And — importantly — retrieval does not automatically guarantee correctness. A retrieved document can be misapplied, and the model can still invent beyond its context. That is exactly why the validation layer exists (Phase 2): retrieval narrows the model's room to hallucinate; validation checks whether it stayed inside.

---

## 6. Phase 1 — Consultant + RAG + Implementation Planner

Phase 1 (commits `0a2c182`, `f8383e8`, `7253a63`) turned the diagnostic tool into a consultant platform.

**Consultant orchestration** (`consultant_orchestrator.py`) runs a fixed pipeline per request: normalize the query → route intent → (Phase 3 addition: optionally collect read-only SAP observations) → retrieve evidence from the knowledge corpus → run deterministic analyzers (dependencies, cross-module chains, ABAP) → assemble a bounded context → call the LLM with a mode-specific prompt and strict output contract → validate → shape the `ConsultantResponse` → (Phase 2 additions: confidence calibration and plan validation with bounded retries).

**Intent routing** (`knowledge/intent.py`) classifies the request into a consultant mode using token-boundary-aware keyword matching (so "atc" doesn't match inside random words, and Z-object names keep their underscores):

- `AUTO` — pick the best mode automatically
- `FUNCTIONAL` — configuration/process questions, per-module
- `TECHNICAL` — transport, performance, technical objects
- `ABAP` — code and dumps
- `CROSS_MODULE` — integration questions, gated on a two-integration-signal threshold
- `IMPLEMENTATION_PLANNER` — build an implementation plan

Report-statement detection distinguishes ABAP code (`REPORT zfoo.`) from prose mentioning "report," and explicit intent selection beats incidental signals.

**RAG and SAP knowledge retrieval** as described in §5: Qdrant + bge-m3 embeddings over the curated corpus, with per-case retrieval checks in the golden evaluation.

**Structured reasoning** — the LLM must return the response contract (JSON-shaped, Pydantic-validated). Irrelevant sections stay empty; no fabricated filler is allowed.

**Implementation planning** (`implementation_planner.py`) produces a strict `ImplementationPlan` contract: ordered steps with title, detail, risk, and verification requirements; missing-information questions; and explicit `execution_status` / `approval_required` / `execution_supported` fields. The UI labels steps that are approval-required, and states plainly: *"execution NOT supported"* — because in Phase 1 there was no execution path at all (only an interface + mock seam, `backend/app/execution.py`).

**Evidence states** — every claim and evidence item carries one of:

| State | Meaning |
|---|---|
| `VERIFIED` | Grounded in retrieved corpus evidence |
| `USER_PROVIDED` | Stated by the user in the conversation |
| `INTERNAL_KNOWLEDGE` | Model background knowledge, labeled as such |
| `INFERRED` | A conclusion derived from evidence — not itself an observed fact |
| `RECOMMENDED` | An advisory suggestion |
| `UNVERIFIED` | Could not be matched to retrieval (evidence items); Phase 2 adds `INSUFFICIENT` as the *response-level* status when there is no supportable evidence at all |

These states are the backbone of the anti-hallucination design: a fabricated SAP Note or BAPI cannot masquerade as a verified fact, because nothing enters the response unlabeled. The UI renders the labels; the eval suite tests them.

**Missing-information detection** — the planner asks the user questions before proposing changes ("which client? which condition type? which company code?"). Dependency identification and cross-module analysis are deterministic analyzers (`knowledge/cross_module.py`, `validation.py`), not LLM guesses — they chain known module relationships (SD–FI billing interface, procure-to-pay) from the corpus.

**Risk identification and test planning** — each step carries a risk level and a verification flag; plans without verification steps are rejected by plan validation.

**Export functionality** — responses and plans export as JSON and Markdown; the diagnostic brief also exports as PDF and an Outlook draft (the original tool's specialty, preserved).

**Human approval boundary** — from day one, plans carry `approval_required` and the execution seam is interface-only. Phase 1 could *describe* a change; it could not make one. This boundary is what Phases 3 and 4 later built upon rather than removed.

**Why Phase 1 mattered:** it converted VAYRA from an answer generator into a structured consultant workflow — the difference between "here's some text about your problem" and "here is the diagnosis, the evidence behind each claim, the questions you must answer first, the ordered plan, the risks, and the tests."

---

## 7. Phase 2 — Reliability, Evaluation & Hardening

Phase 2 (commit `75887ed`) asked: *how do we know any of the above works, repeatably?* LLM outputs are probabilistic; normal software tests don't cover that.

What was added:

- **Golden SAP scenarios** (`evaluation/golden_dataset.py`) — 101 cases spanning functional, technical, cross-module, ambiguous, incomplete-information, adversarial, conflicting-evidence, and hallucination-trap scenarios. Each case asserts expected routing, expected missing-info questions, expected corpus retrieval, prohibited claims, plan strictness, and cross-module chains.
- **Evaluation snapshots** (`golden_snapshot.json`) — a per-case baseline; the golden runner compares against it and its exit code gates CI. Silent quality drift is impossible.
- **Baseline evaluation** (`evaluation/dataset.py`, 26 examples) — a fast regression suite run alongside the golden suite (26/26).
- **Hallucination testing** — hallucination-trap cases feed plausible-sounding but nonexistent SAP objects; fabricated BAPI names and unknown T-codes must surface `UNVERIFIED` warnings.
- **RAG/retrieval relevance and source grounding** — cases assert that the correct corpus documents are retrieved and cited.
- **Conflicting knowledge and confidence calibration** — when evidence is absent or contradictory, the response status becomes `INSUFFICIENT` instead of a confident wrong answer; a bounded 3-attempt retry loop lets the LLM revise against validator feedback before the system reports `INSUFFICIENT`.
- **Missing-information handling** — incomplete cases must produce questions, not guesses.
- **Implementation-plan validation** (validators 7–9) — plans must be ordered, verification-bearing, and execution-honest.
- **Cross-module and ABAP validation** — integration claims need two signals; ABAP answers must match the analyzer's deterministic findings.
- **Prompt-injection testing** — hostile text in user input cannot change routing or surface fabricated evidence.
- **Structured-output validation** — every LLM response must satisfy the Pydantic contract or the endpoint returns a 503 contract violation, never a malformed answer.
- **Routing hardening** — token-boundary matching, REPORT-statement detection, explicit-intent precedence, org-unit questions before catalog gaps, customer-object matching.
- **Readiness reporting** — `VAYRA_RELIABILITY_REPORT.md` documents acceptance gates A–J with real measured numbers.

To be precise about the claim: **VAYRA does not claim to eliminate hallucinations.** It claims to (a) ground responses in retrieved evidence, (b) detect and label unsupported claims, (c) validate every output against a strict contract, (d) refuse to answer (INSUFFICIENT) when evidence is absent, (e) test repeatability with snapshots, and (f) make unsafe execution structurally impossible. Residual hallucination risk inside labeled `INTERNAL_KNOWLEDGE` items remains — the system manages it; it does not magic it away.

**Confidence scoring in normal language:** VAYRA's confidence is not the model saying "I'm pretty sure." It is a deterministic calibration computed from the evidence basis — which claims are VERIFIED vs INFERRED vs UNVERIFIED, whether required information was present, whether validators passed. `HIGH` means verified evidence and no validation warnings; `INSUFFICIENT` means the system refuses to grade the answer at all. The model never grades its own homework.

---

## 8. Phase 3 — Read-Only SAP Integration

Phase 3 (commit `6d2697d`) answered the next obvious question: a consultant needs to *see* the actual system. The objective: let VAYRA obtain real SAP information — **without allowing it to change SAP**.

**The SAPConnector abstraction** (`app/sap/connector.py`) defines exactly eleven read-only operations, and every subclass is forced to declare `READ_ONLY = True` (enforced at class-definition time):

`connect`, `disconnect`, `health_check`, `get_system_info`, `query`, `read_object`, `read_table`, `read_metadata`, `get_error_context`, `get_document`, `get_configuration_context`

There is no write, create, post, or modify method anywhere in the layer — and the capability parser would silently drop one if it were ever added (see below).

**Integration approaches actually implemented:**

- **OData adapter** (`adapters/odata_adapter.py`) — IMPLEMENTED as code, GET-only (no other HTTP method appears in it), tested against `httpx.MockTransport` with simulated OData responses. It has **never been connected to a live SAP Gateway system**.
- **Mock adapter** (`adapters/mock_adapter.py`) — IMPLEMENTED as a deterministic in-memory SAP with failure injection (unavailable, timeout, authorization denial, rate limit, partial data). All tests and the running product use this.
- **RFC, BAPI, IDoc, middleware** — NOT IMPLEMENTED. They are documented as future adapters behind the same ABC; no code exists.

**The rest of the layer:**

- **Capability detection/gating** — seven grantable capabilities, all read (`SAP_CONNECTION`, `READ_METADATA`, `READ_CONFIGURATION`, `READ_DOCUMENT`, `READ_TABLE`, `READ_ERROR`, `READ_MASTER_DATA`). Capability parsing fails closed: unknown names, write-shaped names, and typos are dropped, never widened (`parse_capabilities("WRITE_TABLE")` returns an empty set).
- **Read-only policy** — a deny-by-default `ReadOnlyPolicy` plus `OperationClassifier`; write-shaped operations are denied by classification, with denial reasons recorded.
- **Secure credential handling** — credentials are environment-only, repr-safe (a `SapCredentials` object never leaks its secrets in logs/exceptions), with a `redact()` helper used at audit time.
- **Normalized responses and data minimization** — a normalization pipeline (parser → schemas → sensitive-data filter → truncation) bounds field counts, row counts, and string lengths, and filters sensitive-looking keys before anything reaches the LLM prompt.
- **SAP-aware diagnostics and observation labels** — observations enter answers as provenance-tagged items (`SAP_OBSERVED` vs `INFERRED`) inside `[BEGIN SAP_DATA] … [END SAP_DATA]` delimiters, so the model always knows which text is system output and which is its own reasoning. The consult UI shows a live SAP connection panel (hidden while disconnected).
- **Audit logging** — every request is appended to a local JSONL trail, redacted at record time. The trail contains request metadata, never secrets.
- **Rate limiting, timeouts, circuit breakers** — a sliding-window limiter with max-requests/minute and max-concurrency, per-operation timeouts, and a circuit breaker that opens after repeated failures (authorization failures are never retried).
- **Sandbox integration** — a connection runbook (`SAP_INTEGRATION.md` §8) documents how a real read-only sandbox would be connected (system, client, communication user with display-only authorizations, S_RFC scoping). **NOT YET EXECUTED — no sandbox is connected.**

**Clearly stated:** every SAP interaction in this repository today is against the mock adapter or `MockTransport`. Real SAP connectivity is implemented-to-the-adapter-boundary and tested to that boundary, and nothing further.

---

## 9. Phase 4 — Controlled SAP Execution & Automation

Phase 4 (commit `bdde838`) is the most consequential phase, and the most constrained.

**Why it was introduced.** Phases 1–3 let VAYRA say *"this is what should be done."* The natural next question is *"then do it."* In an SAP context, naive automation is dangerous: one mis-keyed configuration write in production can stop billing or goods movement. Phase 4's objective is therefore not "let the AI change SAP" but: **prepare, control, execute and verify an *approved* SAP change** — with the control machinery so tight that neither the model nor a bug can reach SAP outside it.

**The execution architecture, stage by stage:**

```
USER                          — describes the problem (consult page)
→ CONSULTANT                  — intent routing + RAG + reasoning (Phases 1–2)
→ IMPLEMENTATION PLAN         — strict contract: ordered steps, verification, rollback story
→ PLAN VALIDATION             — engine checks levels, sequence, declaration completeness
→ IMPACT ANALYSIS             — deterministic estimate of affected objects, risk, sequence
→ DRY RUN                     — full simulation; proves nothing changes SAP state
→ HUMAN APPROVAL              — explicit decision, bound to the exact plan hash
→ POLICY / AUTHORIZATION      — execution level, system allow-list, two-person rule
→ EXECUTION ENGINE            — one step at a time, sequence + duplicate guards
→ SAP (SIMULATOR)             — the executor seam; today the §23 simulator
→ VERIFICATION                — deterministic post-step state check vs expected result
→ ROLLBACK                    — only where the step declared rollback support
→ AUDIT                       — hash-chained, tamper-evident, secret-scrubbed record
```

- **Plan validation** (`validate_plan`): the submitted plan is fingerprinted (SHA-256 over canonical JSON — the `plan_hash`), its steps are classified for transaction safety, and any step lacking a verification method, a rollback declaration, or a sane sequence is rejected. The plan object is then frozen — mutating it invalidates the hash.
- **Impact analysis** (`estimate_impact`): a deterministic analyzer (not the LLM) reports affected objects, risk classes, execution ordering, and authorization-sensitive steps.
- **Dry run** (`dry_run`): every step is exercised against the simulator *without* recording state changes; the report distinguishes "would succeed" from "did succeed." The endpoint docstring and tests assert the dry run never changes SAP state.
- **Human approval** (`request_approval`, `submit_approval_decision`): see §11.
- **Policy/authorization gates:** execution level (§16), production system allow-list, two-person rule, destructive/UNCERTAIN denial, emergency stop, circuit breaker, rate limit.
- **Execution engine** (`execute_step`): exactly one step per call, in sequence, with the approval token consumed, the rate-limit slot acquired only when a step actually reaches the executor, and the state machine advanced at each transition.
- **Verification:** the `VerificationEngine` performs a deterministic state query against the executor and compares it to the step's expected result — the model is never asked "did it work?"
- **Rollback** (`rollback_step`): executed only for steps whose declaration said rollback is supported, with the declared method; a failed rollback is reported honestly (`ROLLBACK_REQUIRED` persists) rather than papered over.
- **Audit** (`generate_audit_report`): every transition and parameter lands in a hash-chained log (each record carries the SHA-256 of its predecessor; editing or reordering breaks the chain and `verify_integrity()` detects it), with secret-shaped values replaced by `[FILTERED]` at record time.

**Integration:** 12 API routes under `/api/v1/execution/*` (denials surface as HTTP 403/409/404/422 — never silent) and an `/execution` console page: engine banner with emergency-stop button, plan editor, live state chips, dry-run table, approval dossier, step execution controls, and the audit trail with a chain-integrity badge.

**Clearly stated:** the executor behind the engine is the built-in SAP execution simulator (`simulator.py`, a seeded deterministic fake SAP with failure injection). **No real SAP write connector exists.** Phase 4 is a complete, tested control plane around a simulated SAP — which is exactly what it should be before anyone points it at a real system.

---

## 10. Execution Engine

`ControlledExecutionEngine` (`backend/app/execution_engine/engine.py`) — all of the following exist in code and are covered by 44 engine tests plus 12 API tests:

| Method | Purpose |
|---|---|
| `validate_plan(plan, config)` | Registers a plan: computes and binds the `plan_hash`, classifies every step's transaction safety, enforces level/system/production gates, freezes the plan. Returns the run in `PLANNED`. |
| `estimate_impact(run)` | Deterministic impact report: affected objects, risks, execution sequence, authorization-sensitive steps, rollback availability. |
| `dry_run(run)` | Simulates every step without state change; returns a per-step report and the expected verification criteria. |
| `request_approval(run, requested_by)` | Opens an approval request with the full dossier (target system/object, operation, impact, risks, rollback, verification) and returns it for human review. |
| `submit_approval_decision(request_id, approve, approver, plan_hash, note)` | Records the explicit human decision; binds it to the plan hash (a modified plan invalidates approval), enforces expiry, single decision, and the two-person rule for production. |
| `execute_step(run, step, approval_request_id)` | Executes ONE step: sequence guard, duplicate guard (409), valid-token check, rate limit, breaker check, emergency-stop check, then executor call, then verification, then state transition. |
| `rollback_step(run, step)` | Rolls back an executed step using its declared rollback method; reports honestly if rollback fails or was never supported. |
| `get_status(run)` | Current state-machine position plus per-step statuses — the observable state the UI renders. |
| `cancel(run, user, reason)` | Cancels a run from any pre-completion state; audited. |
| `set_emergency_stop(stopped, reason, user)` | Global kill switch: blocks every new step and demotes already-approved runs. Audited. |
| `generate_audit_report(run)` | Full append-only audit trail plus an execution summary; chain integrity is verifiable. |

Supporting components (all implemented and tested): `classifier.py` (transaction-safety classification — destructive first, `UNCERTAIN` denied as destructive), `approvals.py` (the `ApprovalStore`), `analysis.py` (impact, dry-run, transport-plan, ABAP gate with forbidden patterns), `simulator.py` (executor + `VerificationEngine.verify_step`), `audit.py` (hash-chained log), `models.py` (levels, states, plan hash, idempotency keys), `service.py` (process-wide singleton configured via `EXECUTION_LEVEL`, default `DRY_RUN`).

---

## 11. Human Approval

Human approval exists for one reason: **the AI can reason about a proposed action, but authorization must be controlled independently.** The LLM writes the plan; it has no vote on whether the plan runs. Approval is a separate subsystem with its own store, its own tokens, and its own tests — the model has no code path into it.

Before approving, the human reviews a dossier containing:

- **target system** (system ID, client, environment — production flagged)
- **target object** (the specific SAP object/table/record each step touches)
- **proposed operation** (what will actually be done, per step)
- **expected impact** (from the deterministic impact analysis)
- **prerequisites** (steps and conditions that must hold first)
- **risks** (per-step risk classification, destructive flags)
- **rollback strategy** (declared per step — or an explicit "no rollback," because false promises are worse than none)
- **verification method** (how success will be checked after execution)

The approval itself is engineered against the obvious failure modes:

- **Plan-hash binding** — the approval token is valid only for the exact SHA-256 plan hash that was approved. If anything in the plan changes afterward, the approval is invalidated (`APPROVAL_INVALIDATED`), closing the "approve one thing, run another" hole.
- **Single decision, one-time token** — a request is decided once; the token is consumed by one execution.
- **Expiry** — approvals expire after 120 minutes; expired approvals are rejected.
- **Two-person rule** — production executions require the approver to differ from the requester plus a written justification.
- **Fail-closed errors** — any approval anomaly surfaces as a denial (HTTP 403), never as a warning the model can ignore.

This is precisely how the LLM is prevented from "deciding it is allowed": there is no such decision for it to make.

---

## 12. Dry Run

A dry run executes the full plan against the simulator in a mode that provably records no state changes. Its value before touching an enterprise system is obvious: it converts "the plan looks right" into "the plan ran end-to-end and each step produced the expected outcome — on a system where being wrong is free."

VAYRA's dry run evaluates, per step: prerequisites and sequence validity, affected objects, dependencies on earlier steps, potential impact, risks, and — critically — the **verification criteria** that will later be applied after real execution. The dry-run report is the same artifact the approver sees, so approval is granted against evidence, not against a description.

**Dry run ≠ actual execution.** The distinction is enforced structurally, not by convention: the dry-run path never invokes the state-mutating executor path, and tests assert the engine state is untouched afterward. A dry run that accidentally wrote would be a correctness bug, not a UX detail — so it's tested like one.

---

## 13. Execution State Machine

Twelve states are implemented (`ExecutionState` in `execution_engine/models.py`) and rendered live in the UI:

```
PLANNED → DRY_RUN → AWAITING_APPROVAL → APPROVED → EXECUTING → VERIFYING
    → SUCCESS
    → FAILED → ROLLBACK_REQUIRED → ROLLED_BACK
    → CANCELLED
    → DENIED
```

- `PLANNED` — validated and registered; plan hash bound
- `DRY_RUN` — dry run completed
- `AWAITING_APPROVAL` — dossier open, awaiting a human decision
- `APPROVED` — valid approval token on record
- `EXECUTING` — a step is being executed
- `VERIFYING` — deterministic verification of the executed step
- `SUCCESS` — all steps executed and verified
- `FAILED` — a step failed (execution error, verification mismatch, timeout, or auth failure)
- `ROLLBACK_REQUIRED` — a step failed and its rollback failed or is unsafe — escalated, not hidden
- `ROLLED_BACK` — rollback completed after failure
- `CANCELLED` — cancelled by an operator
- `DENIED` — policy refused the operation (wrong level, destructive/uncertain class, no approval, breaker open, emergency stop, sequence violation…)

Legal transitions are enforced in code; illegal transitions are denials. This is what makes execution **observable** (the UI always shows the true position) and **controlled** (every transition is a guarded, audited event — nothing advances "in the background").

---

## 14. Failure Handling & Rollback

When a step fails — execution error, verification mismatch, timeout, or authorization failure — the engine:

1. **Stops** — no further steps run (partial-execution stopping is tested).
2. **Captures the failure** — error, classification, and the step's parameters (scrubbed) go to the audit log.
3. **Inspects actual system state** — the verifier performs a state query to distinguish "the step failed and changed nothing" from "the step changed something and then reported failure." These are different worlds and the engine treats them differently.
4. **Determines whether the previous step succeeded** — verification results for completed steps are on record, so the failure boundary is known exactly.
5. **Determines rollback availability** — from the step's declared `RollbackDeclaration` (`supported`, `method`, `risk`).
6. **Rolls back when supported** — using the declared method, then verifying the rollback.
7. **Escalates when rollback is unsafe or fails** — the run lands in `ROLLBACK_REQUIRED`, visibly, with the reason. It is never silently reclassified as clean.
8. **Records the incident** — the hash-chained audit trail carries the whole story.

**On idempotency and blind retries:** every step carries an idempotency key, and the engine enforces a duplicate guard (a second submission of the same step is a 409). This exists because in SAP, retrying blindly is dangerous: a retry of a step that actually succeeded (but reported failure — a timeout after commit, say) applies the change twice. A pricing condition created twice, a posting duplicated — the "fix" becomes the incident. The engine's rule: never retry on the assumption the step didn't run; verify state first, and let the verification layer answer whether anything happened.

---

## 15. Security Architecture

VAYRA's security model is layered so that no single component — and especially not the LLM — can cause an unsafe SAP action:

- **Separation of reasoning and authorization** — the model proposes; a deterministic policy engine and a human decide. Structurally separate code, stores, and tests.
- **Policy engine** — Phase 3's deny-by-default read-only policy (no write path exists to even policy-check) and Phase 4's classifier (destructive and `UNCERTAIN` operations denied like destructive).
- **Human approval** — plan-hash-bound, expiring, single-use, two-person for production (§11).
- **Execution boundaries** — the only path to the executor runs through the five-layer security pipeline (`intent validation → authorization → policy validation → plan validation → approval validation`); denials are explicit statuses, never silent no-ops.
- **SAP data as untrusted input** — SAP observations enter prompts only inside `[BEGIN SAP_DATA]…[END SAP_DATA]` delimiters and are labeled `SAP_OBSERVED`; the model is instructed to treat them as data, not instructions.
- **Prompt-injection resistance** — tested at two layers: Phase 2 (hostile user input cannot change routing or fabricate evidence) and Phase 4 (hostile text in plan fields and simulated SAP payloads cannot raise the execution level, skip approval, or forge a write). Note the honest limit: this is defense-in-depth around the model, not a guarantee about the model.
- **Execution limits** — maximum 25 steps per run, sequence and duplicate guards, one step per call.
- **Concurrency controls and rate limits** — bounded concurrent runs and executions/minute; the rate-limit slot is acquired only when a step actually reaches the executor (a denial does not leak a slot — a bug class the tests pin).
- **Circuit breaker** — opens after repeated consecutive failures; only a VERIFIED success resets it (so a flapping system can't self-heal its way past the breaker).
- **Emergency stop** — global kill switch; blocks new steps and demotes approved runs; audited; also settable at startup via environment.
- **Production restrictions** — production requires `CONTROLLED_PRODUCTION` level + an explicit system allow-list + two-person approval with justification.
- **Audit logging** — hash-chained, tamper-evident (tampering tests included), secret values scrubbed at record time.
- **Credential isolation** — everything env-only; repr-safe credential objects; `redact()` applied at audit boundaries; `backend/.env` gitignored; no secrets in the repository.

The security principle in one line:

> **LLM ≠ Authorization ≠ Execution** — the reasoner is not the authorizer, and neither is the executor.

---

## 16. SAP Automation Levels

Five levels are defined (`ExecutionLevel`); their actual status:

| Level | Name | Status | What it permits |
|---|---|---|---|
| 0 | `READ_ONLY` | **Operable** (default alongside L1) | Reads only — mapped to the Phase 3 observation layer |
| 1 | `DRY_RUN` | **Operable — the default** | Full pipeline, dry runs; no SAP state change |
| 2 | `APPROVED_NON_PRODUCTION` | **Operable** (simulator-backed) | Writes after explicit approval, non-production systems only |
| 3 | `CONTROLLED_PRODUCTION` | **Operable** (simulator-backed) | Production writes requiring allow-list + two-person approval |
| 4 | `AUTONOMOUS` | **DISABLED BY DESIGN** | Nothing. Parsing the level raises; the engine fails closed (§21 of the spec). Enabling it "requires governance controls that do not exist yet." |

Levels 2 and 3 are *operable in code against the simulator* — they run the full approval/verification/rollback machinery, but the executor is simulated. Since no real SAP write connector exists, no level today performs a real SAP write. That is the honest reading, and the README, EXECUTION.md, and the commit message all state it.

---

## 17. Current End-to-End Architecture

```
USER  (consult console / execution console / API client)
  ↓
INPUT NORMALIZATION            — query + optional error-code normalization; SAP error
  ↓                              messages parsed into message-class/number form
INTENT ROUTER                  — mode (AUTO/FUNCTIONAL/TECHNICAL/ABAP/CROSS_MODULE/PLANNER),
  ↓                              functional domain, two-signal integration gate
CONSULTANT ORCHESTRATOR        — fixed pipeline, one place where everything composes
  ↓
[READ-ONLY SAP OBSERVATIONS]   — Phase 3, optional: policy → capability → connector
  ↓                              (mock/OData) → normalization → provenance-tagged context
SAP KNOWLEDGE / RAG            — curated corpus → embeddings (bge-m3) → Qdrant →
  ↓                              ranked retrieval → bounded context assembly
LLM REASONING                  — one of six providers (incl. deterministic offline demo);
  ↓                              mode-specific prompt + strict output contract
CLAIM & OUTPUT VALIDATION      — validators 1–9: evidence labeling, fabricated-BAPI/
  ↓                              unknown-T-code warnings, cross-module two-signal rule,
                                  plan/dependency/ABAP checks, bounded 3-attempt retry,
                                  INSUFFICIENT calibration
IMPLEMENTATION PLANNER         — ordered steps, risks, verification requirements,
  ↓                              missing information, approval flags, execution honesty
                                  (Phase 1: "execution NOT supported")
─────── below this line, Phase 4 ───────
PLAN REGISTRATION              — SHA-256 plan hash bound; plan frozen
  ↓
IMPACT ANALYSIS                — deterministic affected-objects/risks/sequence report
  ↓
DRY RUN                        — full simulation, zero state change, produces the
  ↓                              verification criteria
HUMAN APPROVAL                 — dossier review → plan-hash-bound, expiring, single-use
  ↓                              token; two-person rule for production
POLICY / AUTHORIZATION         — execution level, production allow-list, destructive/
  ↓                              UNCERTAIN denial, breaker, rate limit, emergency stop
EXECUTION ENGINE               — one step per call; sequence + duplicate guards;
  ↓                              idempotency keys
SAP  (SIMULATOR)               — executor seam; today the §23 simulator
  ↓
VERIFICATION                   — deterministic state query vs expected result;
  ↓                              the model is never asked "did it work?"
ROLLBACK / SUCCESS             — declared-method rollback on failure; honest
  ↓                              ROLLBACK_REQUIRED escalation when rollback fails
AUDIT LOG                      — hash-chained JSONL, secret-scrubbed, tamper-evident,
                                  readable through the API and the console
```

Each box is a real module with real tests. The pipeline is the product; the LLM is one box among many.

---

## 18. Important Design Principles

As implemented, not just professed:

1. **Do not guess.** Missing information becomes questions (`missing_information`), not assumptions; no evidence becomes `INSUFFICIENT`.
2. **Retrieve evidence before reasoning.** Retrieval precedes the LLM call and is asserted per eval case.
3. **Separate reasoning from authorization.** The approval subsystem has no LLM anywhere in it.
4. **Separate planning from execution.** Phase 1 shipped plans with an explicit "execution NOT supported" boundary; execution arrived later, behind its own gates.
5. **Validate generated claims.** Nine validators; fabricated BAPIs and unknown T-codes are flagged; contracts are enforced or the API returns 503.
6. **Detect missing information.** Golden cases assert question-generation for incomplete scenarios.
7. **Make execution observable.** A 12-state machine, rendered live, every transition audited.
8. **Require approval for state-changing operations.** Plan-hash-bound, expiring, single-use; two-person for production.
9. **Verify after execution.** Deterministic state checks against expected results; the model never self-certifies.
10. **Fail safely.** Deny-by-default everywhere; `AUTONOMOUS` raises at parse time; uncertain operations are treated as destructive; errors surface as statuses (403/409/503), never silent.
11. **Preserve auditability.** Hash-chained append-only logs on both the read and execution sides; tampering is detectable.
12. **Never blindly trust model output.** Every LLM answer passes Pydantic validation and deterministic analyzers; confidence is computed, not declared.
13. **Treat external SAP data as untrusted input.** Delimited, labeled, scrubbed, length-bounded.
14. **Prefer deterministic controls around probabilistic reasoning.** The architecture is literally this sentence: probabilistic LLM at the center, deterministic retrieval, validation, policy, approval, verification, and audit around it.

---

## 19. Representative SAP Use Cases

All scenarios below run end-to-end today **against the mock SAP adapter and the execution simulator** — they demonstrate the real pipeline, not a real SAP connection.

**SD — billing/account determination issue (simulated)**
Input: *"Billing document VF032 shows no accounting document; error from the SD-FI interface."*
→ Diagnosis routed to FUNCTIONAL/SD, retrieving `billing-account-determination.md` and the SD–FI process-chain document; evidence states separate the retrieved account-determination procedure from inferences about this specific customer's condition records. → Plan: check VKOA condition records / account assignment, ordered, each step with verification. → Impact: flags the SD–FI interface objects affected. → Dry run: sequence verified, nothing changed. → Approval: dossier shows target objects, rollback (config changes reversible; postings not), verification method. → Execution (simulator): one configuration update step, verified against expected state. → Audit: full trail.
The same shape covers **pricing issues** (condition technique, `pricing-condition-technique.md`) and **ATP/delivery issues** at the knowledge level.

**MM — valuation/account determination issue (simulated)**
Input: a goods-movement error (the corpus carries the M8 message-class case `obyc-m8147.json` and `valuation-account-determination.md`).
→ Diagnosis links the movement to OBYC valuation-class/account assignment; cross-module analysis flags the MM–FI dependency. → Plan: verify valuation class on the material, check OBYC assignment, test posting — with questions asked first if the material/client are unknown (missing-information detection is asserted in eval). → Approval → simulated execution of the configuration check/fix → verification of the resulting assignment → audit.
The same shape covers **GR/IR and invoice-verification questions** at knowledge depth.

**Cross-module — SD–FI (simulated)**
Input: *"Customers complain invoices post to the wrong revenue account."*
→ Routed CROSS_MODULE (two integration signals: billing + GL posting); the dependency analyzer chains SD billing → FI interface → VKOA; retrieval pulls both module documents plus `integration/sd-fi-process-chain.md`. → Plan with module-ordered steps and per-step verification. → Impact explicitly lists cross-module objects. → Through the full Phase 4 pipeline as above.

**ABAP — runtime error / performance (simulated)**
Input: an ST22 dump excerpt, or ABAP source.
→ ABAP mode; the ST22 parser structures the dump; the static analyzer (`abap/analyzer.py`) flags real code smells — SELECT *, FOR ALL ENTRIES misuse, nested loops over large tables, DELETE inside LOOP, SELECT SINGLE without WHERE — with findings labeled as deterministic analysis, not model opinion. → Plan: code correction with suggested snippets, testing steps, transport note. → If a correction were approved for execution, the ABAP gate in the execution engine checks for forbidden patterns before any write-shaped step is permitted (simulated).
These scenarios are **diagnosis-and-plan** today: there is no code deployment path to SAP, and none is claimed.

---

## 20. Testing & Quality Assurance

33 test files, **561 tests passing**, plus two evaluation suites run from the CLI. Layers:

- **Unit tests** — every module: intent router, normalization, validators, planner, analyzers, SAP policy/normalization/capabilities, execution models/classifier/approvals/audit.
- **Integration tests** — API endpoints (`test_sap_api.py`, `test_execution_api.py`, `test_consult_endpoint.py`), provider adapters (OpenAI/Anthropic/DeepSeek/Kimi), the full consult pipeline.
- **Golden scenarios** — 101 cases with expected routing/retrieval/questions/prohibited-claims/plan-shape assertions.
- **Regression via snapshots** — `golden_snapshot.json` baseline; the golden runner's exit code gates regressions; the baseline evaluation re-runs 26 cases per change.
- **Hallucination tests** — trap cases requiring `UNVERIFIED`/`INSUFFICIENT` surfacing for fabricated BAPIs and unknown T-codes.
- **Retrieval tests** — per-case corpus-relevance assertions (`test_knowledge_tree.py`, golden cases).
- **Security tests** — a dedicated Phase 3 suite (`test_sap_security.py`): secret leakage, injection, capability escalation, caps, audit integrity.
- **Prompt-injection tests** — two layers (user input; plan fields and SAP payloads in the execution engine).
- **Structured-output tests** — contract validation on every LLM-facing path.
- **Execution tests** — the 15 unsafe-scenario families of the spec (§24): approval bypass, modified-plan approval, destructive/uncertain denial, production gates, verify-fail→rollback, rollback-fail reporting, timeout, auth failure, partial execution stop, duplicate 409, replay skip, prompt injection, emergency stop, audit tampering, expired approval — plus breaker open/reset, secret filtering, and the API status-code mapping.
- **Rollback and failure tests** — injected failure modes (`fail_steps`, `fail_auth`, `fail_timeout`, `fail_rollback`, `fail_verify`) proving each behaves as specified.
- **End-to-end** — `scripts/e2e_consult.py` drives a running backend through the full consult pipeline (4/4 passing against the demo provider).

Why AI systems need more than normal tests: a function `add(a,b)` fails loudly when broken; an LLM answer can be *confidently, plausibly wrong* while every process exits 0. Evaluation therefore has to assert on content properties — what was claimed, what was grounded, what was refused — and must be re-runnable with snapshots so quality drift shows up as a test failure, not as a slow accumulation of bad answers nobody noticed.

---

## 21. What VAYRA Can Do Now

**A. Fully implemented (deterministic, real):**
- Intent routing across six modes and thirteen functional domains; consultant orchestration pipeline
- RAG retrieval (bge-m3 + Qdrant) over a curated 20-document SAP corpus with bounded context assembly
- Evidence-state labeling (VERIFIED/USER_PROVIDED/INTERNAL_KNOWLEDGE/INFERRED/RECOMMENDED/UNVERIFIED + INSUFFICIENT calibration)
- Validators 1–9 (grounding, cross-module two-signal rule, fabricated-BAPI/unknown-T-code warnings, plan/dependency/ABAP checks) with bounded retries
- Implementation planner with the strict plan contract, missing-information questions, risk/verification fields
- Deterministic ABAP static analyzer and ST22 dump parser
- Dependency/cross-module analysis
- Golden evaluation (101 cases + snapshots + gate) and baseline evaluation (26 cases)
- Phase 3 read-only SAP layer: policy engine, capability gating, credentials, normalization/filtering, audit trail, rate limiter, breaker, provenance tags/delimiters
- Phase 4 execution control plane: plan validation, impact analysis, dry run, approvals (hash-bound/expiring/one-time/two-person), state machine, step execution guards, deterministic verification, rollback, cancellation, breaker, emergency stop, hash-chained audit
- FastAPI backend, Next.js UI (diagnosis, consult, execution, history, graph, settings), desktop wrapper, JSON/Markdown/PDF/Outlook exports
- 561 tests; all documented gates pass; documentation matches the code

**B. Implemented but simulated/mock:**
- All SAP *reads* — mock adapter (with failure injection); the OData adapter is real code tested only against `httpx.MockTransport`
- SAP data appearing in consult answers — from the mock when enabled
- All SAP *writes* — the execution engine's executor is the §23 simulator; execution, verification, and rollback all operate on simulated state
- The live E2E suite — runs against the local backend using the demo provider

**C. Partially implemented:**
- Real SAP connectivity — adapter boundary + OData GET adapter + connection runbook exist; no live system has ever been connected
- Prompt-injection resistance — layered mitigations with tests; inherent model-level risk remains
- ABAP handling — static analysis is deep; "fix and deploy" is out of scope and not attempted
- Provider-quality dependence — contract-tested with six providers; reasoning quality varies by model and is evaluated only via deterministic checks, not semantic scoring

**D. Architectural capability (designed, not operational):**
- `AUTONOMOUS` (Level 4) — placeholder that fails closed
- RFC/BAPI/IDoc adapters behind the connector ABC — documented extension points, no code
- Transport management — `TransportManager` produces transport *plans*; no CTS integration
- Deep knowledge for PS, WM/EWM, HCM, TM, S/4HANA, CDS, AMDP, RAP — router-recognized, corpus-extensible, no dedicated documents yet

**E. Not implemented:**
- Any connection to a real SAP system (read *or* write)
- Any real SAP write, transport release/import, code deployment, or job scheduling
- Autonomous execution; LLM-initiated actions of any kind
- Enterprise identity integration (the two-person rule is enforced in code over explicit identities provided per request — it is not wired to SSO/AD)
- Multi-user/production hosting hardening (the product is a local workstation tool by design)

---

## 22. What VAYRA Cannot Yet Claim

- **It is not a replacement for a certified SAP consultant.** It is a workstation tool that makes a competent person faster and more disciplined. Accountability for changes to SAP remains with people.
- **It does not guarantee zero hallucinations.** It grounds, labels, validates, and refuses — it does not make the model omniscient. Labeled `INTERNAL_KNOWLEDGE` claims can still be wrong.
- **It does not automatically understand a customer's SAP customization.** The corpus is generic best-practice knowledge; it knows nothing about any specific company's Z-objects, enhanced logic, or bespoke configuration until that knowledge is added (and nothing today ingests it automatically).
- **It cannot execute arbitrary SAP changes.** Only plan-shaped, classified, approved, verification-bearing steps run — and only against the simulator today. Arbitrary change is not a feature gap; it is the rejected design.
- **A mock adapter is not production SAP integration.** Real systems bring RFC quirks, authorization realities, data volume, timeouts under load, and semantic messiness that no MockTransport reproduces.
- **Architectural support ≠ operational support.** The existence of the connector ABC, the Level 3 enum, or the runbook does not mean the capability works against a real system. It doesn't — yet.
- **The two-person rule is a control, not an identity system.** It enforces distinct, justified approver/requester identities in code; it does not authenticate humans against an enterprise directory.
- **Evaluation is deterministic, not semantic.** Golden cases assert structural properties; they cannot judge whether a nuanced functional recommendation is *good* — a human still does that.

---

## 23. Difference Between VAYRA and a Normal LLM

**Normal LLM:**

```
Question → Answer
```

**VAYRA:**

```
Question → Understand → Identify intent → Retrieve evidence → Reason → Validate
→ Identify missing information → Build implementation plan → Assess impact
→ Dry run → Approval → Controlled execution → Verification → Audit
```

Why the difference matters in SAP: in a chat, the model's confidence and your trust are the only controls, and both are unreliable. In VAYRA, the load-bearing properties are structural: claims are labeled by provenance, missing information forces questions, plans carry verification and rollback, changes require hash-bound human approval, execution is one audited step at a time, and success is verified deterministically. The model can be wrong the same way chat models are wrong — but its wrongness gets caught by validators, labeled in evidence states, stopped at the approval gate, or caught by verification. There is a system between the model's opinion and the system of record. That system is the difference.

---

## 24. Difference Between VAYRA and a Generic AI Agent

Generic agent frameworks optimize for *capability*: tools, loops, autonomy. VAYRA optimizes for *domain discipline* — the specifics of SAP work:

- **SAP terminology** — token-boundary routing over T-codes, message classes (M8, VF, FB), BAPI names, customer Z-objects; near-miss collisions handled explicitly.
- **Module awareness** — thirteen functional domains, per-module retrieval and analysis.
- **Cross-module dependencies** — a two-integration-signal rule and a dedicated SD–FI / procure-to-pay knowledge layer, because SAP errors routinely originate in a different module than the one where they surface.
- **Configuration reasoning** — corpus documents encode configuration *procedure* (OBYC, VKOA, pricing procedure), not just definitions.
- **Implementation planning** — a strict plan contract (order, risk, verification, rollback story, missing info), validated by dedicated validators.
- **ABAP technical reasoning** — a deterministic static analyzer plus ST22 parsing, so code findings don't depend on the model's mood.
- **SAP evidence** — provenance-tagged observations from an actual (currently simulated) system, delimited as untrusted data.
- **SAP execution boundaries** — the write-shaped-operation classifier, destructive-first, with rollback declarations required per step — an SAP transaction-safety model, not a generic "tool use" permission.
- **Testing** — golden cases written by SAP scenario, not code coverage.
- **Auditability** — hash-chained trails on both read and write sides, because in SAP "who changed what, when, and why" is a first-class question.
- **Enterprise safety** — levels, breakers, emergency stop, two-person rules: the controls an SAP change process assumes, built in rather than bolted on.

A generic agent asks "what tool can I call?" VAYRA asks "what would a careful SAP consultant need to know, check, and get approved before touching this system?"

---

## 25. Current Project Maturity

**Classification: Advanced technical prototype — sandbox-ready by design, deliberately not production-connected.**

Why:

- **Beyond a functional prototype:** full deterministic control planes on both the read and write sides, 561 tests including adversarial/security suites, evaluation snapshots with regression gates, honest failure handling (rollback escalation), tamper-evident audit, and documentation that matches the code.
- **Not sandbox-ready *in fact*:** "sandbox-ready" would mean the runbook has been executed against a real system. It hasn't — no SAP system of any kind is connected. The phrase used here is "sandbox-ready by design": the adapter boundary, credential model, capability scoping, and connection runbook exist and are the natural next step, but they are unexercised against reality.
- **Not production-ready:** no real SAP connectivity, no write connector, simulator-backed execution, no enterprise identity/SSO, no multi-user hosting story, and evaluation that is structural rather than semantic. Every one of these is known, documented, and intentional at this stage.

The maturity is concentrated exactly where it should be before first contact with a real system: in the controls.

---

## 26. Project Achievement From Phase 1 to Phase 4

| Phase | Main Objective | Major Capability | Safety Boundary | Status |
|---|---|---|---|---|
| **Phase 1** (2026-10-01/03, `0a2c182`, `f8383e8`, `7253a63`) | Turn a diagnostic tool into a consultant platform | Intent routing, RAG over a curated corpus, structured consultant responses with evidence states, dependency/cross-module analysis, strict implementation plans, exports | Plans are data-only: `approval_required` flags, explicit "execution NOT supported"; execution seam is interface + mock; legacy diagnostic pipeline untouched | **IMPLEMENTED** |
| **Phase 2** (2026-10-04, `75887ed`) | Prove it works repeatably | 101 golden cases + snapshots + exit-code gates, 26-case baseline eval, hallucination traps, INSUFFICIENT calibration, bounded retries, routing hardening, readiness report | INSUFFICIENT-evidence refusal, fabricated-object warnings, contract validation (503 on violation), injection-resistant routing | **IMPLEMENTED** |
| **Phase 3** (2026-10-06, `6d2697d`) | Let VAYRA *see* SAP without touching it | Read-only observation layer: deny-by-default policy, capability gating, mock + GET-only OData adapters, normalization/filtering, provenance-tagged delimited observations, audit, rate limiting, breaker | `READ_ONLY = True` enforced at class level; no write path exists in the layer; write-shaped capability names dropped at parse; fail-closed everywhere | **IMPLEMENTED (SIMULATED SAP)** — no sandbox connected |
| **Phase 4** (2026-10-06, `bdde838`) | Control an approved SAP change end to end | ControlledExecutionEngine: plan hash, impact, dry run, plan-hash-bound approvals, 12-state machine, guarded step execution, deterministic verification, rollback, breaker, emergency stop, hash-chained audit; 12 API routes; execution console | Destructive/UNCERTAIN denied; 25-step cap; duplicate/sequence guards; one-time expiring approval tokens; production allow-list + two-person rule; L4 fails closed; executor is a simulator | **IMPLEMENTED (SIMULATED EXECUTION)** — no real SAP writes possible |

---

## 27. Technical Architecture Summary

| Layer | Technology / implementation |
|---|---|
| Frontend | Next.js App Router (React 19, TypeScript, Tailwind CSS), client-only React Three Fiber visualization; desktop wrapper via PowerShell + WebView2 |
| Backend | Python 3.14, FastAPI, Pydantic v2 contracts; uvicorn; runs on localhost |
| LLM layer | `LLMService` ABC with 6 adapters: demo (deterministic offline), OpenAI, Anthropic, DeepSeek, Kimi, Ollama (OpenAI-compatible, default Qwen3-14B local) |
| RAG layer | bge-m3 embeddings, Qdrant vector store (local), ingestion pipeline, ConsultantRetriever with bounded context assembly |
| Knowledge layer | 20 curated markdown/JSON documents (7 modules + cross-module + T-codes + technical/ABAP) with metadata for the knowledge graph |
| Validation | 9 deterministic validators + Pydantic contract enforcement + bounded 3-attempt retry + INSUFFICIENT calibration |
| Planner | `implementation_planner.py` — strict step/missing-info/verification/rollback contract |
| SAP connector | `app/sap/` — SAPConnector ABC (READ_ONLY enforced), mock adapter + GET-only OData adapter (MockTransport-tested), policy engine, capabilities, credentials, normalization, audit, rate limiting |
| Execution engine | `app/execution_engine/` — ControlledExecutionEngine, classifier, ApprovalStore, analysis (impact/dry-run/transport/ABAP gate), simulator + VerificationEngine, hash-chained audit log, service singleton |
| Policy engine | ReadOnlyPolicy + OperationClassifier (Phase 3); ExecutionLevel + TransactionSafety classification + production gates (Phase 4) |
| Verification | VerificationEngine — deterministic state queries vs expected results; never LLM-judged |
| Audit | JSONL, append-only, SHA-256 hash chain, secret scrubbing at record time, `verify_integrity()` |
| Testing | pytest (561 tests, 33 files), golden runner + snapshot gate, baseline eval runner, live E2E script |
| Security | Env-only credentials, gitignored `.env`, deny-by-default policy, plan-hash binding, breaker/emergency stop, secret scrubbing, capability parse fail-closed |

---

## 28. Project Development Journey

**Stage 1 — AI diagnostic concept (`0a2c182` precursor work, preserved as the legacy pipeline).** The original tool took an SAP error message and produced a structured diagnosis. Limitation: it only handled what it was given — no general questions, no planning, no breadth.

**Stage 2 — Consultant + RAG (Phase 1).** Added the consultant contract, routing, retrieval, evidence states, and the planner. This solved Stage 1's limitation: arbitrary SAP questions in, disciplined consulting artifacts out. New limitation: *trustworthy how?*

**Stage 3 — Reliability and evaluation (Phase 2).** Added golden scenarios, snapshots, calibration, and validation hardening. This solved Stage 2's limitation: quality became measurable and regressions became loud. New limitation: VAYRA still knew nothing about *your actual system* — everything was corpus plus model.

**Stage 4 — Read-only SAP integration (Phase 3).** Added the observation layer, so answers could be grounded in real (currently simulated) system data, with policy/audit/rate-limiting controls. This solved Stage 3's limitation partially — the ground-truth gap. New limitation: VAYRA could *see* and *recommend*, but not *act* under control.

**Stage 5 — Controlled SAP execution (Phase 4).** Added the execution control plane: approval, state machine, verification, rollback, audit. This solved Stage 4's limitation while refusing its risk: acting became possible, but only as a controlled, approved, verified, audited process over a simulator.

Each stage kept the previous stage's machinery untouched (the legacy pipeline and seams still pass their tests) and added one honest capability with its safety boundary designed in, not retrofitted.

---

## 29. What I Learned From Building VAYRA

*(First person, grounded in what the architecture actually required.)*

**SAP functional consulting is mostly epistemics, not answers.** The hard part of every scenario I modeled wasn't producing a recommendation — it was knowing what must be true before the recommendation means anything: which client, which condition technique, which valuation class. That's why missing-information detection became a core feature rather than a nice-to-have. A consultant's first deliverable is the question list.

**The LLM is simultaneously the best and least trustworthy component.** It writes excellent structured reasoning given evidence and a contract — and it will fabricate a BAPI name in the same sentence as a correct one. I stopped trying to fix that with prompting. Prompting helped; contracts, validators, and evidence labeling *enforced* it. Every serious control in VAYRA is deterministic code around the model, never the model policing itself.

**RAG solves grounding, not correctness.** Retrieval dramatically narrowed the hallucination surface — the eval cases prove it — but retrieved context can be misapplied, so validation had to exist independently. The two layers catch different failure modes, and I needed both.

**Evaluation is the real product of an AI system.** The golden snapshot baseline caught drift I would never have seen manually, and the trap cases (fabricated objects, conflicting evidence) found real bugs that normal tests structurally couldn't. If I rebuilt this, I'd build the evaluation harness even earlier.

**Authorization is a system boundary, not a prompt rule.** "Never execute anything without approval" works as architecture (separate store, hash binding, one-time tokens, fail-closed parsing) and fails as an instruction. Every injection test that passed, passed because of structure — delimiters, parse-time capability dropping, level parsing that raises — not because the model was told to behave.

**Human-in-the-loop is a design constraint on the *dossier*, not a checkbox.** An approval button is worthless if the approver can't see target object, impact, rollback, and verification method in one artifact. Most of the approval work went into making the dossier honest — including declaring "no rollback" where rollback doesn't exist.

**Failure handling is where systems earn trust.** The interesting bugs were all failure paths: a dangling ROLLBACK_REQUIRED state, a breaker that reset too early, a rate-limit slot leaked on denials, verification consumed by the wrong code path. Happy paths write themselves; I had to test failures explicitly and by name.

**Verification must be deterministic.** Asking the model "did it work?" would have quietly reintroduced exactly the unreliability the rest of the system removes. The verifier compares simulator/system state to the expected result — boring, checkable, correct.

**Auditability changes how you build everything upstream.** Once every action must land in a hash-chained trail with secrets scrubbed at record time, you design data flow differently: less guessing, more explicit intent, fewer side channels. The audit requirement improved the architecture even though its only job is to be read after something goes wrong.

**API design is contract design.** Pydantic contracts plus additive evolution (new fields, new subsystems, never breaking the legacy pipeline) is why four phases shipped without destabilizing what worked.

---

## 30. Interview Explanation

**"What is VAYRA?"**

> VAYRA is an AI-assisted SAP consulting platform I built end to end. It combines retrieval-augmented reasoning over a curated SAP knowledge base with a deterministic validation and control layer, so that every answer is evidence-labeled and every proposed system change goes through impact analysis, dry run, explicit plan-bound human approval, step-by-step execution with verification, rollback, and a hash-chained audit trail. It currently runs against a simulated SAP — the control plane is real and tested; the SAP connection is the next step.

**30-second version:**

> VAYRA is an AI SAP consultant that doesn't just answer questions — it shows its evidence, asks for missing information, produces a validated implementation plan, and can execute an approved change under a fail-closed pipeline: dry run, human approval bound to the exact plan hash, one step at a time, deterministic verification, rollback, and tamper-evident audit. The principle throughout: the LLM reasons, but it never authorizes. It's fully implemented against a simulator — 561 tests — and deliberately has no path to write to real SAP yet.

**1-minute version:**

> The starting observation was that an SAP consultant needs more than an answer: evidence, dependencies, missing information, impact, testing, approval, and audit. So VAYRA is a pipeline, not a chatbot. A request gets routed by SAP intent — functional, technical, ABAP, cross-module — then retrieves from a curated SAP knowledge corpus via embeddings and a local vector store, reasons with a local or cloud LLM, and passes nine deterministic validators that label every claim VERIFIED, INFERRED, or UNVERIFIED, flag fabricated BAPIs and unknown T-codes, and refuse to answer as INSUFFICIENT when evidence is missing. The implementation planner produces an ordered, risk- and verification-bearing plan. Phase 4 added the execution side: impact analysis, dry run, explicit approval bound to the SHA-256 of the exact plan, a twelve-state execution machine, per-step verification, rollback, emergency stop, and a hash-chained audit log. Everything is evaluated against 101 golden scenarios with snapshot baselines, 561 tests pass, and the whole thing runs locally with any of six LLM providers.

**2-minute technical version:**

> Architecture-wise it's a FastAPI backend and a Next.js frontend, desktop-wrapped, running fully locally. The knowledge layer is about twenty curated markdown/JSON documents covering SD, MM, FI, CO, PP, QM, PM, cross-module SD–FI and procure-to-pay, plus ABAP performance and ST22 methodology — chunked, embedded with bge-m3 into a local Qdrant instance. The orchestrator routes intent with token-boundary matching — things like keeping underscores in Z-object names and distinguishing a REPORT statement from the word "report" — then retrieves, then calls the LLM under a strict Pydantic output contract. Response confidence is computed from the evidence basis, not self-reported: INSUFFICIENT means the system refuses to grade the answer.
>
> The SAP integration phase is a read-only observation layer with a deny-by-default policy engine, capability gating that drops write-shaped names at parse time, env-only repr-safe credentials, normalization with sensitive-data filtering, and provenance-tagged observations injected into prompts inside explicit untrusted-data delimiters. Two adapters exist: a deterministic mock with failure injection, and a GET-only OData adapter tested over MockTransport — no live SAP system is connected, by design, so far.
>
> The execution phase is where the safety engineering concentrates. Plans are SHA-256-fingerprinted and frozen; approval tokens bind to the hash, expire in 120 minutes, and are single-use; production requires a system allow-list and a two-person rule with justification. Steps are classified read/write/destructive/uncertain — uncertain is denied like destructive. Execution is one guarded step per call with sequence, duplicate, and idempotency checks, a rate limiter, a circuit breaker that only a verified success resets, and a global emergency stop. Verification is a deterministic state query against the expected result — the model never certifies its own work. Rollback only runs where the step declared it, and a failed rollback escalates to a visible ROLLBACK_REQUIRED state rather than being hidden. The audit log is append-only and hash-chained; tampering is detectable.
>
> Quality: 561 tests including all fifteen unsafe-execution scenario families, 101 golden SAP scenarios with snapshot gating, and a 26-case baseline suite. The honest limitation: the executor is a simulator — the control plane is production-grade in structure, but it has never touched a real SAP system, and the autonomous level exists only to fail closed.

---

## 31. Resume Version

- Built **VAYRA**, an AI-powered SAP consulting and controlled-automation platform (Python/FastAPI, Next.js/TypeScript): LLM + **RAG** pipeline (bge-m3, Qdrant) over a curated **SAP** knowledge corpus spanning **SD, MM, FI, CO, PP, QM, PM** and **ABAP** diagnostics, with intent routing, evidence-state labeling, and **implementation planning** — all independently built, no SAP implementation-project experience implied.
- Designed a fail-closed **execution engine** for proposed SAP changes: **human-in-the-loop approval** bound to SHA-256 plan hashes, a 12-state execution state machine, step-level **verification**, **rollback**, circuit breaker, emergency stop, and tamper-evident **audit logging** — enforcing the principle that the **LLM** reasons but never authorizes.
- Implemented a **read-only SAP integration layer** with a deny-by-default policy engine, capability gating, credential isolation, data minimization, prompt-injection-resistant context delimiting, and rate limiting/circuit breaking; delivered a deterministic mock adapter and a GET-only OData adapter behind a SAPConnector abstraction.
- Built an AI **regression testing** and evaluation harness: 101 golden SAP scenarios with snapshot baselines and exit-code gates, hallucination-trap and prompt-injection suites, and 561 automated tests covering the full **validation** → **execution** → verification → audit pipeline.

---

## 32. GitHub README Summary

**VAYRA** is a local, open, AI-powered SAP consulting and controlled-automation platform. It helps you work through SAP functional, technical, ABAP, and cross-module problems the way a careful consultant would: with evidence, missing-information questions, validated plans — and, for system changes, a controlled approval-and-verification pipeline.

**The problem.** LLMs answer SAP questions confidently, including when they're wrong. They don't know what they don't know about your system, can't distinguish a fact from an invention, and have no concept of authorization. In SAP, a confident wrong answer becomes a wrong configuration.

**The solution.** VAYRA wraps the LLM in deterministic machinery: intent routing → RAG over a curated SAP corpus (bge-m3 + Qdrant) → reasoning under a strict output contract → nine validators that label every claim and flag fabricated objects → an implementation planner with verification and rollback fields → and, through Phase 4, impact analysis, dry run, plan-hash-bound human approval, a 12-state execution machine, deterministic step verification, rollback, and a hash-chained audit trail.

**Phases.** 1 — Consultant + RAG + implementation planning. 2 — Reliability: 101 golden scenarios, snapshots, calibration, hardening. 3 — Read-only SAP observation layer (policy engine, capability gating, mock + GET-only OData adapters, provenance-tagged data). 4 — Controlled execution engine with approvals, verification, rollback, audit.

**Current capabilities.** Everything above runs end to end on a local machine with six selectable LLM providers (including a deterministic offline demo). 561 automated tests; evaluation-gated quality; desktop or browser UI.

**Safety model.** The LLM is responsible for reasoning; it is not responsible for authorization. Deny-by-default policy, hash-bound expiring approval tokens, two-person rule for production, destructive/uncertain denial, rate limiting, circuit breaker, global emergency stop, tamper-evident audit. Level 4 ("autonomous") exists only to fail closed.

**Limitations.** No real SAP system is connected; the executor is a built-in simulator; no real SAP writes exist at any level; the two-person rule is code-enforced but not wired to enterprise identity; evaluation is structural, not semantic; VAYRA is a consultant's tool, not a consultant.

**Future direction.** Connect a read-only SAP sandbox via the documented runbook (the OData adapter and capability scoping are ready); add RFC/BAPI read adapters; grow the corpus (PS, WM/EWM, HCM, TM, S/4HANA, CDS/AMDP/RAP); extend golden coverage; only then, consider the executor seam against a real non-production system under the same controls.

---

## 33. Final Project Status

**VAYRA PROJECT STATUS**

- **Phase 1:** STATUS — **COMPLETE & COMMITTED** (`0a2c182`, `f8383e8`, `7253a63`). Consultant + RAG + implementation planning fully implemented; legacy pipeline preserved.
- **Phase 2:** STATUS — **COMPLETE & COMMITTED** (`75887ed`). Golden evaluation (101 cases), baseline eval (26), calibration, validation hardening; 561 tests passing.
- **Phase 3:** STATUS — **COMPLETE & COMMITTED** (`6d2697d`). Read-only SAP integration layer implemented and tested against the mock/MockTransport; **no real SAP connection**.
- **Phase 4:** STATUS — **COMPLETE & COMMITTED** (`bdde838`). Controlled execution engine fully implemented and tested against the simulator; **no real SAP writes possible at any level**.

**Overall status:** Advanced technical prototype — functionally complete across all four phases, heavily tested and evaluation-gated, security-first by architecture; deliberately pre-connectivity (sandbox runbook ready, never executed).

**Current capabilities:**
- End-to-end SAP consulting: intent routing (6 modes, 13 domains) → RAG (20-doc corpus, Qdrant/bge-m3) → LLM reasoning (6 providers) → validation (evidence states, fabricated-object warnings, INSUFFICIENT refusal) → implementation plans (order/risk/verification/rollback/missing-info)
- Read-only SAP observation layer (policy, capabilities, normalization, audit, rate limiting) with provenance-tagged data in answers
- Controlled execution: plan hash → impact → dry run → plan-bound approval (expiry, one-time token, two-person for production) → guarded step execution → deterministic verification → declared rollback → hash-chained audit; 12 API routes; execution console UI
- Quality: 561 tests, 101 golden scenarios with snapshot gate, 26-case baseline eval, live E2E suite; all gates green at the current commit

**Known limitations:**
- No SAP system connected (read or write); mock/OData-MockTransport only; runbook exists but unexecuted
- Executor is a simulator; Level 4 (AUTONOMOUS) is a fail-closed placeholder; no RFC/BAPI adapters
- Generic knowledge only — no customer-specific customization awareness; corpus extensible but not auto-ingesting
- Two-person rule not wired to enterprise identity; hosting is single-user local by design
- Evaluation is structural (routing/labels/contracts), not semantic judgment of recommendation quality

**Next logical development stage:**
1. **Connect a real read-only SAP sandbox** — execute the documented runbook (communication user, display-only authorizations, scoped S_RFC), exercise the OData adapter against the real Gateway, harden timeouts/paging against reality, and extend golden coverage with live-data fixtures.
2. **Add RFC/BAPI read adapters** behind the existing ABC for capabilities OData can't reach (ST22 dump retrieval, job logs).
3. **Grow the knowledge corpus** toward the architecturally-scoped modules (PS, WM/EWM, TM, HCM, S/4HANA, CDS/AMDP/RAP) with matching golden cases.
4. **Enterprise identity for the two-person rule** (SSO/AD integration) — required before any non-simulated Level 3 use.
5. Only after 1–3: exercise the executor seam against a **real non-production** system under the existing approval/verification/rollback/audit controls — the simulator/executor interface was built exactly so this step changes no control logic.

---

*Report generated from repository inspection: commits `0a2c182`…`bdde838` (2026-10-01 → 2026-10-06) — six commits covering the four phases (Phase 1 spans three) — 55 indexed source files, 33 test files, 20 knowledge documents. No capability is described as operational unless it exists in code and passes tests; simulated capabilities are labeled as simulated throughout.*
