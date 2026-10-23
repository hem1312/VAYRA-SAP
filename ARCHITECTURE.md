# VAYRA — Architecture

VAYRA is an AI SAP Functional + Technical Consultant: it classifies a request,
retrieves verified SAP knowledge, reasons over that knowledge with a
configurable LLM, and deterministically validates the answer before showing it.

```
Developer
   ↓
Freebuff (engineering agent, edits this repository)
   ↓
VAYRA Source Code
   ↓
--------------------------------
VAYRA Runtime (independently runnable)
--------------------------------
Next.js / React Frontend
        ↓
FastAPI Backend
        ↓
Intent Router  →  Consultant Orchestrator
        ↓                ↓
Knowledge Retrieval / RAG   Deterministic Analyzers (ABAP, ST22)
        ↓                ↓
LLM Provider Abstraction  →  Local / Hosted LLM
        ↓
Validation Layer (deterministic)
        ↓
Implementation Planner (plan · risks · test plan)
        ↓
Human Approval          ← formal boundary — [FUTURE SAP EXECUTION]
        ↓
Structured Consultant Response
```

Freebuff is the **development environment only**. The VAYRA runtime has no
dependency on it — `uvicorn` + `npm run dev` is a complete runtime.

## Backend layout

```
backend/app/
├── main.py                     FastAPI app, settings, probes, endpoints
├── logging_config.py           structured logging, request IDs, redaction
├── models.py                   legacy diagnostic models (unchanged)
├── consultant_models.py        ConsultantRequest / ConsultantResponse / ImplementationPlan
├── consultant_prompts.py       per-mode system prompts + user prompt builder
├── consultant_orchestrator.py  ConsultantOrchestrator (incl. plan generation)
├── implementation_planner.py   Implementation Planner + risks + test plan (§11/§13/§14/§16)
├── execution.py                ExecutionEngine ABC + MockExecutionEngine (§18)
├── orchestrator.py             legacy DiagnosticOrchestrator (unchanged)
├── validation.py               validators 1-6 + plan/dependency/test-plan validators 7-9
├── execution_engine/           Phase 4 controlled execution (see EXECUTION.md)
│   ├── models.py               §3 levels (AUTONOMOUS disabled), §22 states, §7 safety, plan hash
│   ├── classifier.py           transaction-safety classification (§7, fail-closed)
│   ├── approvals.py            §4/§5 explicit plan-hash-bound approvals, expiry, two-person rule
│   ├── analysis.py             §9 impact · §8 dry run · §13 transport · §14 ABAP gate
│   ├── simulator.py            §23 SAP execution simulator + §11 deterministic verifier
│   ├── audit.py                §17 hash-chained, tamper-evident execution audit
│   ├── engine.py               §2 ControlledExecutionEngine (§15 pipeline, §6 step loop, §19 stop)
│   └── service.py              process-wide singleton (EXECUTION_LEVEL env, default DRY_RUN)
├── sap/                        Phase 3 read-only SAP observation layer (see SAP_INTEGRATION.md)
│   ├── connector.py            SAPConnector ABC (READ_ONLY = True mandatory) + typed failures
│   ├── capabilities.py         7 read capabilities, fail-closed parsing (no WRITE exists)
│   ├── policy.py               OperationClassifier + ReadOnlyPolicy (deny-by-default)
│   ├── credentials.py          env-only secrets, repr-safe, redact()
│   ├── audit.py                JSONL audit trail, redacted at record time (§12)
│   ├── rate_limit.py           sliding-window limiter + circuit breaker (§13)
│   ├── normalization.py        parser → schemas → sensitive filter → context (§7/§8)
│   ├── observation.py          provenance labels + [BEGIN SAP_DATA] delimiters (§10)
│   ├── service.py              SAPService facade — one read path (§6/§9)
│   ├── adapters/mock_adapter.py    deterministic mock + failure injection (§16)
│   └── adapters/odata_adapter.py   GET-only OData adapter (MockTransport-tested)
├── sap_connector.py            legacy seam (unused, superseded by app/sap/)
├── llm_service.py              LLMService ABC + provider adapters
├── embeddings.py               EmbeddingService + VectorStore (Qdrant)
├── rag/
│   ├── protocols.py            RAG pipeline interfaces (§6: loader/chunker/embedding/store/retriever/reranker/context)
│   └── pipeline.py             default adapters over the production components
├── abap/analyzer.py            ABAPAnalyzer + ST22Parser (deterministic)
├── knowledge/
│   ├── intent.py               SAP Intent Router (intent categories, missing info, reliability)
│   ├── cross_module.py         dependency engine (data-driven catalog)
│   ├── normalization.py        error normalization (legacy diagnostic flow)
│   ├── retrieval/
│   │   ├── retriever.py        legacy hybrid retriever
│   │   └── consultant_retriever.py  intent-aware RAG + context builder
│   ├── ingestion/ingest.py     JSON + Markdown ingestion pipeline
│   └── data/                   knowledge tree (see SAP_KNOWLEDGE.md)
└── evaluation/                 synthetic SAP evaluation set + runner (26 examples)
```

## Request flow (consult endpoint)

1. **Intent Router** (`knowledge/intent.py`) — deterministic keyword/regex
   classification: intent category (DIAGNOSTIC / CONFIGURATION /
   IMPLEMENTATION / PERFORMANCE / INTEGRATION / …), consultant type
   (FUNCTIONAL / TECHNICAL / CROSS_MODULE / GENERAL_SAP), consultant persona
   (incl. IMPLEMENTATION_PLANNER), primary module + technical domain, problem
   type, error code, dump name, ABAP-code presence, cross-module signals,
   **reason** (the signals behind the classification),
   **missing_information** (targeted clarification questions),
   `routing_reliable` (low-confidence guard: unreliable routing never
   silently justifies a specific answer), confidence.
2. **ConsultantRetriever** (`knowledge/retrieval/consultant_retriever.py`) —
   metadata-filtered semantic search + deterministic keyword layer,
   verification-aware ranking, bounded context (`build_context`). The RAG
   stages are formalized as swappable protocols (`rag/protocols.py`, §6).
3. **Deterministic analyzers** — `ABAPAnalyzer` (SELECT *, FOR ALL ENTRIES
   guard, nested loops, DELETE in LOOP, package size, unfiltered reads) and
   `ST22Parser` when the request contains ABAP code or a dump.
4. **Cross-module engine** (`knowledge/cross_module.py`) — process chains,
   upstream causes, downstream impacts; pure data catalog. Feeds the
   planner's impact analysis and dependency validation (layer 8).
5. **LLM reasoning** — `ConsultantOrchestrator` assembles the per-mode prompt
   (`consultant_prompts.py`) and calls `LLMService.structured_generate`.
6. **Validation** (`validation.py`) — SAPObjectValidator (T-codes, SAP Notes,
   customer objects), ClaimValidator (unsupported configuration, contradictions),
   EvidenceValidator (stamping), ResponseValidator (completeness),
   ConfidenceModel (evidence-aware confidence + status).
7. **Implementation Planner** (`implementation_planner.py`) — deterministic
   machine-readable plan: steps (approval-required, execution-unsupported),
   8-category risk analysis, 7-category test plan, impact analysis,
   rollback strategy, missing-information DRAFT gating. Validated by layers
   7-9 (`run_plan_validation`). See IMPLEMENTATION_PLANNER.md.
8. **ConsultantResponse** — structured contract consumed by the frontend;
   the plan rides inside `implementation_plan`.

## Preserved legacy flow

`POST /api/v1/diagnostics` still runs the original error-code pipeline:
`normalize_error → SAPRetriever → diagnose_with_context → DiagnosisValidator →
DiagnosticResponse`. Nothing in the consultant work modified it.

## LLM provider abstraction

`LLMService` exposes both the legacy surface (`diagnose`,
`diagnose_with_context`) and the consultant surface (`generate`,
`structured_generate`, `health_check`, `supports_generate`). Adapters:
OpenAI-compatible (OpenAI, DeepSeek, Kimi), Anthropic, Ollama (local), Demo
(deterministic offline). Model/base-url/timeout all come from settings/env —
never hard-coded keys.

## Vector store

`VectorStore` (embeddings.py) prefers a Qdrant server (`QDRANT_URL`) and
falls back to a persistent local store (`backend/.qdrant_local/`). Point IDs
are deterministic UUIDs derived from readable chunk ids; payloads keep all
metadata (`module`, `module_type`, `verification`, `content_hash`, …) used by
retrieval filters and incremental ingestion.
