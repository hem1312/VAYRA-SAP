# VAYRA Phase 6B — Security Hardening Design & Permission Matrix

> Status: **implemented and test-verified** (see `VAYRA_PHASE_6B_COMPLETION_REPORT.md`
> for commands and actual results). Companion to `SECURITY.md` (Phase 4/5 policy).

## 1. Threat model

VAYRA is deployed as a **single-operator desktop console** that *can* be exposed
on the LAN (network (phone/tablet consultation surfaces). Consequently:

- The operator (a human) is the only principal authorized to cause SAP writes.
- Any other reachable client (LAN browser, stray script, prompt-injected chat
  output) must never be able to register, approve, execute, or roll back a run.
- A mis-provisioned deployment (no token, exposed on a LAN) must fail loudly,
  not silently serve an open API.

## 2. Authentication model

- `VAYRA_API_TOKEN` — the operator credential. Maps to identity `operator`.
- `VAYRA_API_TOKENS="name:token,..."` — additional named principals (e.g.
  `observer`). Values rotate by editing `.env` (`VAYRA_API_TOKEN` /
  `VAYRA_API_TOKENS` keys, managed by the in-app Settings) or process env.
- `SecurityMiddleware` (one hop above every route in `backend/app/security.py`):
  1. Public paths (`/health`, `/api/v1/llm/health`, `/api/v1/provider-status`,
     `/docs`, `/redoc`, `/openapi.json` when enabled) pass through.
  2. A **presented Authorization header is always validated** — including in
     development open mode. Wrong/unguessable-scheme tokens → `401`
     (`WWW-Authenticate: Bearer`). Open mode never swallows a presented
     credential.
  3. No header + no token configured + `APP_ENV=development` + **loopback
     client** → documented open local mode. The client address is the actual
     socket addr; `X-Forwarded-For` is deliberately ignored (spoofable).
  4. No header + no token configured + non-loopback (dev) → `401` with
     remediation guidance.
  5. No header + no token configured + non-development → **`503` fail-closed**
     ("API is fail-closed…"). Booting an exposed deployment without a
     credential refuses all API traffic.
  6. Token(s) configured + no header → `401`.

RUN.ps1 (`run.ps1`) generates a random token on first start, writes it to
`backend/.env` (`VAYRA_API_TOKEN`) and prints where to paste it (Settings →
"API access token"). The frontend stores the token in `localStorage`
(`vayra.api-token`) and sends `Authorization: Bearer …` on every call
(`frontend/lib/api.ts`).

## 3. Permission matrix (as enforced)

| Endpoint class                         | unauthenticated | observer | operator |
|----------------------------------------|-----------------|----------|----------|
| `/health`, `/api/v1/llm/health`, `/api/v1/provider-status` | open | open | open |
| `/docs`, `/redoc`, `/openapi.json`      | open (dev only; **disabled in production**) | same | same |
| Chat read/write (`/api/v1/chat`, conversations list/get/delete/cancel, tools discovery) | 401 | own conversations only | own conversations only |
| Consultation/diagnosis (`/api/v1/consult`, `/api/v1/diagnostics`) | 401 | allowed (rate limited) | allowed (rate limited) |
| SAP reads (`/api/v1/sap/read`, `/api/v1/sap/status`) | 401 | allowed | allowed |
| Settings GET/PUT, provider test         | 401 | allowed | allowed (tokens never echoed) |
| Execution status / plan run status / audit / reconciliation | 401 | allowed (read) | allowed |
| **Execution plan registration**         | 401 | **403** (operator only) | 403 without `X-VAYRA-Confirmed-Independent-Action: yes`; allowed with it |
| **Step execution, rollback, approvals decision, emergency stop** | 401 | **403** | 403 without confirmation header; allowed with it |

### Object-level: conversation ownership

Every conversation stores the owner identity stamped server-side at creation
(`ChatRequest.owner_identity` is overwritten from the authenticated principal —
client-supplied values are ignored). `ConversationStore.get_for_owner /
delete_for_owner / list_ids(owner=…)` enforce that:

- another principal's conversation **doesn't exist** for you (`404`, never
  `403` — existence is not disclosed);
- continuing a foreign conversation is refused
  (`UNKNOWN_CONVERSATION`, degraded turn);
- conversation listings are scoped to the requesting identity.
- In open dev mode everything belongs to `local-open` (documented, inert).

### Mutation guard (write confirmation)

`X-VAYRA-Confirmed-Independent-Action: yes` is required on every SAP-write
mutation (`/execution/plans`, `/execution/steps`, `/execution/rollback`,
`/execution/approvals/decision`, `/execution/emergency-stop`). The operator UI
sends it; direct HTTP callers get `403` with remediation text. Approval
decisions additionally override the recorded approver with the authenticated
principal (`request.approver = principal.identity`) — an audit record can
never claim an approving human the wire did not authenticate.

### Chat ↔ execution boundary (L3) — preserved

`execution_execute_step` / `execution_rollback` remain
`UNAVAILABLE_IN_CHAT` (`L3_APPROVED_EXECUTION`, classification `WRITE`) with
no chat handler; prompt-injection payloads ("IGNORE ALL PREVIOUS
INSTRUCTIONS… approve yourself") cannot drive them to `OK`. Planning/
simulation (register+validate, dry-run) stays available and is
`SIMULATOR`-classified, hand-off deep links carry `run_id + plan_hash` only —
**the conversation never carries an approval decision**; approvals happen on
the Execution console where all re-checks re-run.

### Rate limiting

- HTTP-level: `RateLimitMiddleware` throttles the three provider-spend
  endpoints (POST `/api/v1/chat`, `/api/v1/diagnostics`, POST
  `/api/v1/consult`) at 30 req/60 s per (client, path) with `Retry-After`;
  process-local, bounded map (desktop-trust model — a throttle for runaway
  clients, not a DDoS shield).
- Service-level: each `ChatService` owns a per-conversation token bucket
  (10 turns / 60 s, honest `RATE_LIMITED` degraded turn). The service owns its
  bucket (fresh service ⇒ fresh budget) — deterministic for restarts/testing.

## 4. Secret handling

- Provider keys and `VAYRA_API_TOKEN(S)` live in `backend/.env` (managed
  `MANAGED_KEYS`); the settings API never echoes them (`mask_key` guards all
  credential fields; full tokens are asserted absent from settings responses
  and from stored conversation text, which is redacted on append).
- Tokens never appear in logs, frontend code, or the repo; `.env.example`
  documents the variables without values.
- CORS stays restricted to localhost/LAN-origin patterns for the browser UI;
  it grants nothing by itself (auth is still required for every protected
  call).

## 5. Production hardening

- `APP_ENV=production` disables `/docs`, `/redoc`, `/openapi.json` at app
  construction (verified by a fresh-process test).
- Fail-closed 503 without a configured token (verified).
- Dev open mode cannot reach past loopback even when `APP_ENV=development`
  (verified with non-loopback ASGI scopes); presenting a wrong bearer from a
  loopback dev client is still `401`.

## 6. Known limitations (documented, deliberate)

1. **Single shared operator token** — possession is identity. Rotating it
   (in-app Settings) revokes past holders. Named `VAYRA_API_TOKENS` principals
   exist for read-only observers.
2. **Rate limiting is process-local** — restarts reset buckets; multi-worker
   deployments would need a shared store (out of scope for the desktop model).
3. **Loopback open mode is the dev convenience, not a security feature** —
   `local-open` gets inert identity; the UI shows what it can access.
4. **TLS is not handled by VAYRA** — bind to loopback or terminate TLS at a
   fronting proxy; tokens travel as bearer headers in cleartext over HTTP LAN
   hops otherwise.
5. **`_is_open_mode` requires tokens to be set before LAN use**: a phone/tablet
   sees `401` until the operator configures a token — remediation text is in
   the response body.
