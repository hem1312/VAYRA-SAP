# VAYRA Agent Chatbox — Tool-Access Inventory & Capability Catalog

**Phase 6A audit · tool-access levels per task §6 · all items verified against actual code, not docs.**

Legend: **IMPLEMENTED** = callable backend path exists today · **SIMULATOR_ONLY** = works against the §23 simulator (`simulated: true`), never against a live SAP system · **UNAVAILABLE** = dependency missing (live SAP credentials, API auth layer, durable server-side persistence).

---

## 1. Capability levels

| Level | Definition | Status in this repository |
|---|---|---|
| **L0 — Consultation** | Natural-language responses, supported SAP guidance, knowledge retrieval | **IMPLEMENTED** — `/api/v1/consult` → `ConsultantOrchestrator.consult()` (intent router → RAG → deterministic analyzers → LLM → validation) and `/api/v1/diagnostics` → `DiagnosticOrchestrator.diagnose()` |
| **L1 — Read-only tools** | Authorized metadata reads, connector health, supported SAP queries | **IMPLEMENTED / SIMULATOR_ONLY** — `/api/v1/sap/read` → `SAPService.perform()`; 8 registered GET-only OData-core operations (`health_check`, `get_system_info`, `query`, `read_object`, `read_table`, `read_metadata`, `get_error_context`, `get_document`, `get_configuration_context`) behind `sap/policy.py` (deny-by-default, WRITE_* capability names unparseable per `capabilities.py`) |
| **L2 — Planning & simulation** | Implementation plans, impact assessment, dry-run | **IMPLEMENTED / SIMULATOR_ONLY** — deterministic planner (`implementation_planner.py`, never LLM-owned), `run_plan_validation`, `/api/v1/execution/plans` → `validate_plan`, `/dry-run`, `/impact` |
| **L3 — Approved execution** | Explicitly supported write operations with full authorization + human approval | **IMPLEMENTED / SIMULATOR_ONLY** — `/api/v1/execution/runs/{id}/approval` → §4 dossier, `approvals.py` (plan-hash-bound, expiring, fail-closed; §20 two-person rule for PRODUCTION), `/steps` → `execute_step` + deterministic `VerificationEngine`, `/rollback` (§10 snapshot-restoring), `emergency-stop` (§19) |
| **L4 — Autonomous production execution** | Unrestricted autonomous mode | **DISABLED BY DESIGN** — `ExecutionLevel.AUTONOMOUS` fails closed (`parse_execution_level`); no write-capable connector exists; not implemented |

## 2. Tool inventory (what the Chatbox may invoke)

| Tool id | Callable via | Level | Classification | Human approval | Deterministic verification |
|---|---|---|---|---|---|
| `consultant_orchestration` | `/api/v1/consult` | L0 | read-only, no SAP state | n/a | evidence validation (deterministic) |
| `sap_knowledge_retrieval` | inside consult pipeline (`get_consultant_retriever`) | L0 | read-only, local knowledge base | n/a | provenance-tagged evidence |
| `diagnostic_orchestration` | `/api/v1/diagnostics` | L0 | read-only | n/a | `DiagnosisValidator` |
| `sap_connector_health` | `POST /api/v1/sap/read` op `health_check` / `get_system_info` | L1 | read-only | no | connector status |
| `sap_query` / `sap_read_object` / `sap_read_table` / `sap_read_metadata` | `POST /api/v1/sap/read` ops | L1 | read-only, policy-gated | no | redaction + audit log |
| `sap_error_context` / `sap_read_document` / `sap_config_context` | `POST /api/v1/sap/read` ops | L1 | read-only, policy-gated | no | redaction + audit log |
| `implementation_planning` | planner inside consult pipeline | L2 | advisory plan, no state change | plan-level required | `run_plan_validation` |
| `execution_validate` / `dry_run` / `impact` | `/api/v1/execution/plans`, `/dry-run`, `/impact` | L2 | **SIMULATION** (§23 sandbox) | no (dry-run changes nothing) | dry-run report |
| `execution_approve`, `execution_execute_step`, `execution_rollback`, `execution_verify`, `execution_status`, `execution_cancel`, `emergency_stop` | execution routes | L3 | write, **SIMULATOR_ONLY** | yes — approved run + step-scoped, two-person for PRODUCTION | `VerificationEngine` + reconciliation |
| **Chat handoff (Phase 6A)** | chat activity `deep_link` → `/execution?run_id&plan_hash` | L3 | governance handoff, no execution in chat | approval re-verified console-side (hash mismatch → deny; integrity failure → stop) | engine state machine + audit chain |
| `reconciliation` | `/api/v1/execution/runs/{id}/reconciliation` | L3 | read-only post-run | n/a | Phase 5 report |
| `audit_report` | `/api/v1/execution/runs/{id}/audit` | L1 | read-only | n/a | hash-chain integrity |

## 3. Hard exclusions (enforced, not configurable)

- No shell execution, no arbitrary code execution, no SQL passthrough, no direct SAP writes outside the execution engine.
- `sap/capabilities.py`: a `WRITE_*` capability name parses to an **empty set** — the connector layer structurally cannot request or hold write capacity.
- Write attempts route only through `ControlledExecutionEngine` (policy → approval → hash-audit), never directly to an adapter.
- LLM output is untrusted: `DiagnosisValidator`/`run_validation` verify T-codes/evidence against the knowledge base; tool arguments are schema-validated in the chat layer before any dispatch.

## 4. Known environment/dependency gaps

| Gap | Impact | Prerequisite |
|---|---|---|
| Live SAP connectivity | every SAP execution/observation is simulated | authorized SAP credentials + approved OData services |
| OData adapter coverage | `read_table`/`get_error_context`/`get_document`/`get_configuration_context` raise `SapUnsupportedOperationError` in the OData adapter (only `query`, objects, metadata, docs service-exposed) | approved service configuration per system |
| API authentication | single-user desktop/loopback trust model; no per-user identity | required before any network exposure |
| Durable server-side conversation store | conversations persist client-side only | storage backend (e.g., D1/DB) if multi-session needed |
| `knowledge/status` degradations | Qdrant/fastembed optional; retrieval degrades gracefully | none (documented behavior) |

## 5. Provider matrix (LLM)

`llm_service.py`: OpenAI-compatible, Anthropic, DeepSeek, Kimi, Ollama, Demo providers behind the same `LLMService` ABC; `structured_generate` drives the consult pipeline; health probes available per route. No provider can request tools or escalate permissions — tool selection goes through the governed chat layer (intent → registry → schema validation → policy), never through raw model output.
