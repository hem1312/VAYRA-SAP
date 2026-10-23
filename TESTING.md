# Testing

## Commands

```bash
# Backend unit + API tests (no LLM, no Qdrant, no network needed)
cd backend
.venv\Scripts\python.exe -m pytest tests/ -q

# Deterministic evaluation suite (routing/analyzers over the SAP eval set)
.venv\Scripts\python.exe -m app.evaluation.runner

# Phase 2 golden eval (101 cases) + regression snapshot (exit 1 on regression)
.venv\Scripts\python.exe -m app.evaluation.golden_runner          # compare vs snapshot
.venv\Scripts\python.exe -m app.evaluation.golden_runner --update-snapshot  # re-baseline after a green pass

# Live end-to-end consult check (needs a running backend; asserts the
# implementation-plan contract and the clarification round-trip)
.venv\Scripts\python.exe ..\scripts\e2e_consult.py

# Frontend typecheck
cd frontend
npx tsc --noEmit
```

On Windows shells use `PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe …` for the
Python commands (cp1252 console otherwise mangles Unicode output).

The Phase 4 execution engine is exercised in-process against the §23 simulator; a live
HTTP walkthrough is available at `GET /api/v1/execution/status` on a running backend
(set `EXECUTION_LEVEL` deliberately to go beyond DRY_RUN — see EXECUTION.md).

## What the suites cover

| Area | Files |
|------|-------|
| Intent router (domain/problem/mode/general) | `tests/test_intent_router.py` |
| Phase 1 intent categories, missing-info, reliability | `tests/test_phase1_platform.py` |
| Implementation planner, risks, test plan, missing info | `tests/test_implementation_planner.py` |
| RAG protocols, plan/dependency/test-plan validators, mock execution | `tests/test_phase1_platform.py` |
| Consultant retriever, validators, confidence | `tests/test_consultant_pipeline.py` |
| ABAP analyzer + ST22 parser | `tests/test_abap_analyzer.py` |
| Consultant endpoint (routing, analyzers, contract) | `tests/test_consult_endpoint.py` |
| LLM surface (`generate`/`structured_generate`/`health_check`) | `tests/test_llm_surface.py` |
| Knowledge tree + ingestion + incremental hashing | `tests/test_knowledge_tree.py` |
| Legacy diagnostic pipeline (regression) | `tests/test_vayra_pipeline.py` |
| Providers, settings, exports, models | `test_openai_provider.py`, `test_settings.py`, … |
| Evaluation guard (26 SAP examples, incl. planner cases) | `tests/test_evaluation.py` |
| Golden dataset integrity (101 cases, intents, catalog mapping) | `tests/test_phase2_golden_dataset.py` |
| Golden-runner mechanics (catalog tiering, ranking, snapshot contract) | `tests/test_phase2_golden_runner.py` |
| Validation hardening (BAPI, Z-objects, notes, INSUFFICIENT) | `tests/test_phase2_validation.py` |
| Intent boundary-matching regressions | `tests/test_phase2_intent_boundaries.py` |
| **Phase 3** policy engine + capability parsing (deny-by-default, fail-closed) | `tests/test_sap_policy.py` |
| **Phase 3** mock SAP adapter (§16: reads, failure injection, write refusal, READ_ONLY enforcement) | `tests/test_sap_mock_adapter.py` |
| **Phase 3** normalization pipeline (parser, schemas, sensitive filter, truncation, delimiters) | `tests/test_sap_normalization.py` |
| **Phase 3** SAP service (lifecycle, rate limit, breaker, retries, audit, diagnostic context, OData over MockTransport) | `tests/test_sap_service.py` |
| **Phase 3** SAP security (§19: leakage, injection, escalation, caps, audit integrity) | `tests/test_sap_security.py` |
| **Phase 3** SAP endpoints + consult SAP fields (403/429/503 mapping, no secrets) | `tests/test_sap_api.py` |
| **Phase 4** controlled execution engine (§3 levels, §5 immutability, §7 classifier, §24 unsafe scenarios, §6 step flow, §17 audit chain) | `tests/test_execution_engine.py` |
| **Phase 4** execution API (§22 states, 403/409/422 mapping, emergency stop, audit endpoint) | `tests/test_execution_api.py` |

Negative cases are first-class: fabricated SAP Notes must surface `UNVERIFIED`
warnings, unknown T-codes must be flagged, empty retrieval must cap
confidence, and no-domain queries must not invent a domain.

## Offline guarantees

The autouse fixtures in `tests/conftest.py` keep the suite hermetic:

- `isolated_demo_env` — forces the demo provider and a temp `.env`
  (pydantic resolves `env_file` relative to cwd, so tests chdir to tmp_path)
- `offline_vector_store` — replaces the vector store with an inert stand-in
  (no Qdrant, no embedding downloads)

Live-provider adapters are tested with `httpx.MockTransport`, never real
endpoints.

## Adding tests

Follow the existing pattern: pure-function tests for deterministic modules
(intent, analyzers, validators), endpoint tests via the `client` fixture,
and mock-transport tests for provider wire behavior. Every new validator or
analyzer rule ships with positive **and** negative cases.

Phase 1 additions to keep in mind: planner tests assert the advisory-only
contract (`requires_human_approval=True`, `execution_supported=False` on
every step), the missing-information detectors must suppress questions for
given values ("company code 1000"), and every plan must stay DRAFT while
critical information is missing.

Phase 2 additions to keep in mind: the golden snapshot
(`app/evaluation/golden_snapshot.json`) is the regression baseline — update it
only after a fully green run, never to hide a failure; keyword-boundary
regressions (wm/ewm, atc/dispatching) are pinned in
`test_phase2_intent_boundaries.py`; and per-case golden results are reported
with real measured numbers only (see `VAYRA_RELIABILITY_REPORT.md`,
`VAYRA_READ_ONLY_INTEGRATION_READINESS.md`).
