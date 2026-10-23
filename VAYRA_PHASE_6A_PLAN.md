# VAYRA Phase 6A Plan — Unified Agent Chatbox & Tool Orchestration Console

**Status:** COMPLETED (M1–M4 delivered; acceptance in CHATBOX.md) · **Baseline:** Phase 1–5 complete (580 pytest, e2e 4/4, golden 101/101) · **Branch:** `master @ bdde838` + uncommitted Phase 1–5 changes (preserved)

---

## 1. Objective and business value

One central conversational interface — the **Agent Console** — where a consultant talks to VAYRA in natural language; VAYRA routes through its **existing consultant orchestration layer** and invokes only its **real, registered tools** through a governed, schema-validated, policy-enforced tool-calling path. The LLM reasons and recommends; the backend authorizes and executes; the verification engine verifies; the audit records.

## 2. Repository audit summary (what exists and is reused — nothing rebuilt)

| Component | Reused as is |
|---|---|
| Consultant orchestrator | `ConsultantOrchestrator.consult()` — intent routing, RAG, ABAP/ST22 analyzers, cross-module deps, LLM, deterministic validation, plan generation (`app/consultant_orchestrator.py`) |
| Diagnostic orchestrator | `DiagnosticOrchestrator.diagnose()` (`app/orchestrator.py`) |
| LLM providers | `get_llm_service()` singleton (`main.py`) — demo/openai/anthropic/deepseek/kimi/ollama |
| SAP read layer | `SAPService.perform()` — 9 read-only operations, policy-gated, rate-limited, circuit-breaker, audited (`app/sap/service.py`, `policy.py`: WRITE capabilities unparseable) |
| Execution engine | `ControlledExecutionEngine` + `get_execution_service()` — validate/dry-run/impact/approve/execute/verify/rollback/status/cancel/emergency-stop (`app/execution_engine/`) |
| Reconciliation | `engine.reconcile()` + `GET /api/v1/execution/runs/{id}/reconciliation` (Phase 5) |
| Audit | hash-chained `ExecutionAuditLog`, `ExecutionAuditRecord` |
| Frontend | Next.js App Router + existing Shell/StatusOrb/components, `lib/api.ts` (`apiBase()`), execution page patterns |
| Storage seam | New minimal `ConversationStore` mirrors `settings_store`'s local approach: **JSON file under `backend/` (git-ignored), with a clear UNAVAILABLE note for durable server-side persistence** — documented limitation, not pretending to be multi-user |

## 3. Chat architecture (no side agent)

```
ChatRequest(message)
  → auth: trusted-environment identity (documented limitation; no client-supplied roles are trusted for authorization — identity strings are redacted, never used to self-authorize)
  → store: ConversationStore.get_history(conv_id)  (bounded, redacted)
  → intent routing (deterministic, from knowledge/intent.py — NOT model output)
  → ToolRegistry.discover(applicable tools for the intent)
  → for each requested tool_call from the model:
        LLM_TOOLS.toggle/permission gate by capability level + policy
        schema validation (Pydantic tool argument models)
        execution via the REAL existing path:
            sap_read_*   → SAPService.perform(operation…)          (L1)
            plan_*       → deterministic planner + run_plan_validation (L2)
            dry_run_*    → engine.validate_plan + dry_run          (L2 simulated)
            consult_*    → run_consultation(get_llm_service(), …)  (L0, already the orchestrator)
  → governed results stitched into a ChatResponse (md summary + tool activity)
  → ConversationStore.put (tool outputs stored separately from system instructions)
  → audit conversation + tool events through ExecutionAuditLog-equivalent redaction
```

WRITES (L3) are **never callable from chat** in Phase 6A: the tool registry exposes them as `unavailable_in_chat` with guidance to use the existing Execution page approval flow. This satisfies fail-closed: a chat path cannot even construct a `ControlledExecutionEngine.execute_step` call because the registry has no handler for it. The approval/dossier UI remains the dedicated execution surface.

## 4. New files (minimal diff principle)

**Backend**
- `backend/app/chat/__init__.py` — package
- `backend/app/chat/tool_registry.py` — `ToolSpec` (id, name, purpose, level L0–L3, classification `READ_ONLY|SIMULATION|WRITE`, input schema as Pydantic model, output shape, `requires_approval`, `deterministic_verification`, timeout, risk, enabled environments), `ToolRegistry` with `discover()`, `get()`, `validate_args()`, `dispatch()` (reads/writes only; L3 specs carry `execution_mode="UNAVAILABLE_IN_CHAT"` so they show in discovery but never execute)
- `backend/app/chat/handlers.py` — thin adapters that call the EXISTING functions (no duplicate logic)
- `backend/app/chat/conversation_store.py` — local JSON-file conversation persistence (`data/conversations.json`, `.gitignore`d via repo pattern), redacted writes, bounded context (last N=20 messages per request to the LLM)
- `backend/app/chat/models.py` — `ChatRequest`, `ChatResponse`, `ChatMessage`, `ChatToolActivity`, capability level enums, error codes
- `backend/app/chat/service.py` — orchestrator glue: auth (trusted-environment), deterministic intent routing, dispatch, sanitization (`sap_redact` everywhere), rate limiting (per-IP token bucket, reuse `sap.rate_limit` pattern), timeouts (async wait_for), structured errors
- Routes appended to `app/main.py`: `POST /api/v1/chat`, `GET /api/v1/chat/tools`, `GET /api/v1/chat/conversations`, `GET /api/v1/chat/conversations/{id}`, `DELETE /api/v1/chat/conversations/{id}` (per-case), `POST /api/v1/chat/conversations/{id}/cancel`

**Frontend**
- `frontend/app/chat/page.tsx` — Agent Console: conversation sidebar + message stream + tool activity panel + approval/execution status panel (existing engine states) + editing, cancel via `AbortController` (client-side stop; server keeps processing — documented), clear errors, retry on failed request
- `frontend/lib/chatTypes.ts` — shared chat types

**Docs/tests**
- `backend/tests/test_chat.py`, `backend/tests/test_chat_tool_registry.py`, `backend/tests/test_chat_api.py`
- `CHATBOX.md` at repo root

## 5. Tool-access levels & what's enabled in chat (per VAYRA_AGENT_CATALOG.md)

- **L0 enabled:** consultant_orchestration, sap_knowledge_retrieval, diagnostic_orchestration.
- **L1 enabled:** all 9 SAP read operations through `/api/v1/sap/read`'s pipeline; `audit_report`.
- **L2 enabled:** implementation_planning (from consult flow), dry_run + impact (registered, `SIMULATION`).
- **L3 in chat:** visible in discovery as `approval_required` + `UNAVAILABLE_IN_CHAT` — messages tell users to use the Execution console. Prevents chat-side bypasses without weakening the real engine.
- **L4:** does not exist (AUTONOMOUS fails closed in the engine already) — never exposed.

## 6. Security & authorization implications

- LLM **cannot self-authorize:** the flow is deterministic intent→registry→policy; model output only narrows within already-authorized calls.
- Every tool argument validated against the Pydantic schema before dispatch; unknown tool → 404/400 structured error, never fabricated.
- No secrets in/out: `sap_redact` applied to stored messages, tool outputs, logs; snapshots filtered. Conversation history never carries credentials.
- Prompt-injection defense: tool results are marked `SIMULATED`/`OBSERVED` and treated as untrusted data, never instructions; a follow-up model turn receives them inside a clear delimiter block.
- Rate limit + `max_conversation_chars` + `max_tool_calls_per_turn` (5) bound runaway loops.
- Trusted environment loopback model applies (Phase 1–5 known limitation, unchanged).

## 7. Tests to add (all mocked/offline)

1. Registry discovery includes only the real tools; rejects unknown ids.
2. Schema validation rejects malformed args (missing `table` in read_table, etc.).
3. Policy denies tools above level (write → `UNAVAILABLE_IN_CHAT`).
4. Prompt-injection attempt in tool output doesn't become a tool execution; sanitizer strips/flags it.
5. `POST /api/v1/chat` routes consult-intent text to `run_consultation` (mock provider via existing demo path).
6. Tool-activity fields: sanitized args, status, elapsed, simulated/executed, verification/approval states.
7. Conversation store isolation: per-`conv_id` scoping; `GET unknown → 404`; delete removes locally.
8. Request validation: length caps, bad conv ids, non-JSON.
9. Rate-limit: burst → 429 with clear error.
10. Timeouts: adversarial structured_generate provider raising → bounded wait_for and transparent error (deterministic mocked provider).
11. Cancellation/response-boundary: client AbortController behavior documented; server tests for graceful partial.

## 8. Sprint plan (milestones)

1. **M1** backend package + registry + store + tests.
2. **M2** API routes + orchestrator integration + conversation lifecycle + tests.
3. **M3** frontend Agent Console + types + build checks.
4. **M4** docs (CHATBOX.md) + regression (580+ pytest/eval/golden/e2e/tsc/build).

## 9. Rollback strategy

The feature is additive: deleting `app/chat/` + chat routes (registered after the existing execution/consult appends to minimize conflict surface) + frontend `chat` route restores exact Phase 5 behavior. No existing file is structurally rewritten (only additive imports/routes in `main.py`).

## 10. Known future M-bits (non-goals this phase)

- Streaming (SSE) — follow-up phase if justified; request/response now.
- Server-cancelled generation (needs task registry) — client-side stop now, documented.
- Multi-user auth (pre-existing repo-wide prerequisite).
- Live SAP (pre-existing external prerequisite).
