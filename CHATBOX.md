# VAYRA Chatbox (Phase 6A) — Agent Console

The Agent Console is VAYRA's in-application conversational interface: one place where a consultant talks to VAYRA in natural language and VAYRA answers through its **existing** pipelines with **governed tool-calling**. The LLM reasons; the policy engines authorize; the execution engine executes; the verification engine verifies; the audit records. This document reflects the implemented system, not an aspiration.

## Architecture

```
Browser (frontend/app/chat) ── POST /api/v1/chat ──▶ ChatService
                                                      │ deterministic intent routing (keywords, not model output)
                                                      │ ToolRegistry (real tools only, schema-validated)
                                                      ├── consultant_orchestration → run_consultation(get_llm_service(), …)
                                                      ├── sap_read_<op>           → SAPService.perform()  (Phase 3 policy pipeline)
                                                      └── execution_register_validate / execution_dry_run
                                                                                   → ControlledExecutionEngine (Phase 4, §23 simulator)
 Conspiracy-check points: no side agent, no duplicate execution logic, no
 direct adapter calls from chat.
```

- `backend/app/chat/tool_registry.py` — the catalog. Every tool binds to its real handler.
- `backend/app/chat/handlers.py` — thin adapters over existing paths.
- `backend/app/chat/service.py` — turn orchestration, rate limit (10/min/conversation), per-tool timeout (default 120s), bounded tool summaries, error taxonomy.
- `backend/app/chat/conversation_store.py` — local JSON persistence per conversation, `sap_redact` + pattern scrub for unconfigured secrets, bounded 200-message cap and a 20-message LLM window (tool outputs stay out of the LLM prompt).
- Routes in `app/main.py`: `POST /api/v1/chat`, `GET /api/v1/chat/tools`, `GET|DELETE /api/v1/chat/conversations[/{id}]`, `POST /api/v1/chat/conversations/{id}/cancel`.

## Governed L3 handoff (chat → Execution console)

Write capabilities stay **unreachable from chat**, but chat activities now deep-link into the real approval flow instead of dead-ending:

1. When a chat dry-run registration succeeds, the engine registers + validates the plan and the activity carries `deep_link = {page: "/execution", run_id, plan_hash, state, note}` — "plan is validated and registered; approval dossier and step execution happen on the Execution console".
2. Blocked-in-chat write specs (execute/rollback) emit the same handoff shape **without** `run_id`/`plan_hash` — nothing was created through chat.
3. The Execution console (`frontend/app/execution/page.tsx`) accepts `?run_id=&plan_hash=` and preloads the engine state, re-verifying: plan-hash mismatch → explicit "Plan hash mismatch against the handoff" error; audit-chain integrity failure → "do not proceed".
4. The chat never carries an approval decision; every authorization check re-runs in the console/engine. Approval requests, two-person decisions, and step execution remain console-only.

## Tool registry and capability levels

Discovery endpoint `GET /api/v1/chat/tools` lists every registered tool with `capability_level`, `classification`, `execution_mode`, `requires_approval`, `deterministic_verification`, `risk`, and honest `unavailable_reason` where applicable. Currently registered (16):

| Tool id | Level | Class | Callable in chat |
|---|---|---|---|
| `consultant_orchestration` | L0 | READ_ONLY | yes |
| `implementation_planning` | L2 | READ_ONLY | yes (inside consult response) |
| `execution_register_validate` | L2 | SIMULATION | yes |
| `execution_dry_run` | L2 | SIMULATION | yes |
| `sap_read_{health_check,get_system_info,query,read_object,read_table,read_metadata,get_error_context,get_document,get_configuration_context}` | L1 | READ_ONLY | yes (as discovered from connector support) |
| `execution_execute_step`, `execution_rollback` | L3 | WRITE | **no — `UNAVAILABLE_IN_CHAT`** (discovery-only; the chat path has no handler, bypass is structural) — activities surface a governed **handoff deep link** instead |
| `sap_live_connector` | — | — | **no — `UNAVAILABLE_LIVE`** (no credentials; never fabricated) |

Classification discipline: `executed_against` stamps every activity `SIMULATOR` (§23 sandbox), `LIVE` (real SAP read via the policy pipeline — only when a live connector exists), or `NOT_SAP_FACING` (reasoning/analysis). The frontend renders these labels verbatim; nothing is presented as live when it is simulated.

## Invocation lifecycle

1. Client sends `POST /api/v1/chat {message, conversation_id?, module?, system?, user}`.
2. Backend validates the payload (4–20,000 chars).
3. If `conversation_id` is empty a new local conversation is created; an unknown id yields `UNKNOWN_CONVERSATION` in a structured degraded response (HTTP 200 with `errors`, because the turn itself is the API).
4. Deterministic intent routing decides whether the deterministic dry-run path also runs (`"dry run"`/`"simulate"` in the message → plan validate + simulate against the §23 simulator).
5. The consultant pipeline runs (it IS an L0 tool call) and the planning contract is captured.
6. Tool arguments are validated against strict Pydantic schemas (`extra="forbid"`) before dispatch; failures produce `PENDING → ERROR` with `invalid arguments: …`.
7. Dispatch runs the real handler under `asyncio.wait_for` (timeout per spec). Results are summarized (redacted, ≤1.2 KB) into `ChatToolActivity`.
8. The assistant text is synthesized from the actual response (summary, root cause, resolution steps, verification, confidence) plus dry-run stamps.
9. The turn is appended to the conversation store with sanitized tool payloads.
10. Structured `ChatResponse` returns `assistant_text`, `intent`, `tool_activities[]`, `capability_level_used`, bounded-context note, `degraded`/`errors`.

Cancellation: the browser `Stop` button aborts the in-flight fetch (`AbortController`), and `POST /api/v1/chat/conversations/{id}/cancel` returns the explicit note that any already-started backend operation is **not** rolled back (no false rollback semantics).

Non-goal (documented): server-side streaming/SSE and true server-side cancellation of an in-flight LLM call. Timeouts bound the damage instead; streaming can be added later without contract changes (the response already separates text and activity).

## Permissions and security boundaries

- The chat path holds **no** SAP write capability: `sap/capabilities.py` parses `WRITE_*` requests to an empty set at the connector layer, and the chat registry never registers a handler for execution/rollback — the two are separate layers of the same fail-closed design.
- Client-supplied `user` strings are display/audit-only; they cannot authorize anything.
- Every stored message and tool summary passes `sap_redact` plus a pattern-level scrub (`password/token/api-key/... = value`) for secrets that were never configured, so user-typed credential examples cannot leak through history.
- Prompt injection resistance: a follow-up model turn never receives tool outputs as instructions; tool data is rendered only as activity metadata, and validation/`run_plan_validation` still gate all plan content.
- Rate limit, payload caps, timeouts, bounded result summaries (≤1.2 KB), bounded conversation histories (200 messages, 20-message LLM window).

## Local setup

Same as before:

1. `cd backend && .venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000`
2. `cd frontend && npm run dev` (or use `start.bat`.)
3. Open `http://localhost:3000/chat` — the Agent Console appears in the sidebar as "Agent Console".

## Tests and results (documented run)

- `cd backend && .venv/Scripts/python.exe -m pytest tests/test_chat.py -q` → **21 passed, exit 0**
- Full suite: **601 passed, exit 0** (Phase 1–5 regressions included), evaluations 26/26 and 101/101
- Frontend: `npx tsc --noEmit` → 0 errors; `npm run build` → success (10/10 pages, incl. `/chat`)

## Unsupported / simulator-only capabilities (explicit)

- All execution/rollback/dry-run behavior runs on the §23 simulator; live SAP remains unavailable pending an authorized system and credentials — unchanged from Phase 3/4 and never fabricated here.
- Multi-user auth is still absent (pre-existing limitation): the chat API inherits the desktop/loopback trust model and must not be exposed to a network until per-user authentication lands.
- Conversation persistence is local JSON per backend process — sufficient for the single-workstation story, not multi-instance durable storage; no LLM long-term memory is claimed beyond the 20-message window.

## Known limitations and next steps

- Client-side stop only, server continues processing until timeout (bounded at 120s default).
- Tool discovery is per-process snapshot (`GET /api/v1/chat/tools`);
- No true streaming; SSE is the recommended next step if long thinking turns become painful.
