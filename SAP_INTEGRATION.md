# VAYRA SAP Integration (Phase 3) — Read-Only Observation Layer

Status: **implemented against the mock adapter; NO real SAP sandbox connected** (see §17 below).

Core philosophy: **OBSERVE SAP. UNDERSTAND SAP. VALIDATE SAP. DO NOT MODIFY SAP.**

VAYRA can inspect, retrieve, analyze, query, validate, diagnose, explain and plan —
it can never create, modify, post, transport or execute anything on SAP. There is no
write path in the codebase: not in the connector interface, not in the policy engine,
not in the capability model.

---

## 1. Architecture

```
Consultant request (POST /api/v1/consult)
        │
        ▼
Consultant orchestrator ── step 1b: bounded SAP observation (≤2 reads)
        │                          SAPService.collect_diagnostic_context()
        ▼
SAP Service facade  ────────────  app/sap/service.py
        │    OperationClassifier → ReadOnlyPolicy (deny-by-default)
        │    RateLimiter → CircuitBreaker
        ▼
SAP Connector abstraction  ────  app/sap/connector.py  (READ_ONLY = True mandatory)
        │    MockSAPAdapter (tests / demo)   ODataAdapter (GET-only HTTP)
        ▼
Normalization pipeline  ───────  Parser → Normalizer → Schema Validator
        │                        → Sensitive-data Filter → Context Builder
        ▼
LLM prompt (SAP data inside [BEGIN SAP_DATA] … [END SAP_DATA] untrusted-data
delimiters) → response carries sap_status + sap_observations (provenance-tagged)
```

The connector layer is fully separate from the reasoning engine: the orchestrator
never sees an adapter, only `SAPService` results and `Observation` objects.

REST endpoints (Phase 3):

| Endpoint | Purpose |
|----------|---------|
| `GET  /api/v1/sap/status` | Connection state for the UI (§15). Contains no secrets. |
| `POST /api/v1/sap/read`   | One read-only observation through the full policy pipeline. |

Failure mapping on `/api/v1/sap/read`: policy/circuit denial → **403**, rate limit → **429**,
SAP-side failure → **503**. A failed read never returns fabricated data.

## 2. Connector abstraction

`SAPConnector` (ABC) declares the 11 conceptual operations — all READ:

`connect, disconnect, health_check, get_system_info, query, read_object,
read_table, read_metadata, get_error_context, get_document, get_configuration_context`

Every subclass **must** declare `READ_ONLY = True`; the base class refuses any
subclass that does not (`TypeError` at class-definition time). There is no write
method on the interface. A `__getattr__` guard on the mock adapter additionally
refuses (and records) any dynamic attribute whose name smells like a write.

Typed failure hierarchy (§14): `SapConnectorError` with `SapConnectionError`,
`SapUnavailableError`, `SapTimeoutError`, `SapAuthorizationError`,
`SapInvalidRequestError`, `SapMalformedResponseError`, `SapUnsupportedOperationError`,
`SapRateLimitedError`, `SapPartialDataError`. Authorization failures are never retried.

## 3. Interfaces supported

| Interface | Status |
|-----------|--------|
| **Mock adapter** (`MockSAPAdapter`) | Implemented, deterministic, failure-injectable. All tests run against it first. |
| **OData / SAP Gateway** (`ODataAdapter`) | Implemented, **GET-only**, exercised over `httpx.MockTransport`. Not yet tested against a real SAP system. |
| RFC / BAPI reads | Designed (adapter seam exists), **not implemented**. |
| Middleware / other enterprise APIs | Future work behind the same `SAPConnector` seam. |

Capabilities are detected dynamically per adapter (`detect_capabilities()`): no adapter
is assumed to expose everything. The OData adapter advertises `SAP_CONNECTION` +
`READ_METADATA` always, `READ_TABLE` only when services are configured, and
`READ_DOCUMENT`/`READ_CONFIGURATION` only with more than one service. Generic table
access (`read_table`) is refused over OData — reads ride exposed services only.

## 4. Read capabilities (§5)

Exactly seven, all read-only — no WRITE capability exists in the codebase:

`SAP_CONNECTION, READ_METADATA, READ_CONFIGURATION, READ_DOCUMENT, READ_TABLE,
READ_ERROR, READ_MASTER_DATA`

`parse_capabilities()` fails closed: unknown names and anything starting with
`WRITE_/CREATE_/POST_/MODIFY_/DELETE_/TRANSPORT_/EXECUTE_` are silently dropped.

## 5. Security model

- **Deny-by-default policy engine** (§6): every operation passes
  `OperationClassifier → permission check → ReadOnlyPolicy`. WRITE → DENY,
  DESTRUCTIVE → DENY, unclassifiable (UNKNOWN) → DENY, missing capability → DENY.
- **Credentials** (§4): environment variables only, never hard-coded.
  `SapCredentials.__repr__/__str__/safe_config()` cannot leak secrets; `redact()`
  scrubs secret values plus `Bearer `/`Basic `/`password=`/`api_key=`/`sap-client=`
  patterns out of every string that could reach a log, audit event, exception or prompt.
- **LLM isolation** (§7/§8/§10): SAP data is parsed, schema-validated, sensitive-field
  filtered (`password, token, secret, iban, credit_card, ssn, salary, email, …` →
  `[FILTERED]`), row-capped (50) and field-capped (500 chars), then wrapped in
  `[BEGIN SAP_DATA — …] … [END SAP_DATA]` untrusted-data delimiters. Provenance labels:
  `USER_PROVIDED / SAP_OBSERVED / KNOWLEDGE_VERIFIED / INFERRED / RECOMMENDED / UNVERIFIED`.
- **Audit** (§12): every read *and every denial* produces a JSONL audit event with
  timestamp, user, request_id, SAP system, operation, object, purpose, result status,
  response classification and latency. Credential redaction runs at record time.
  Configure via `SAP_AUDIT_LOG`; **never place the audit file in a public folder.**
- **Backpressure** (§13): sliding-window request limit (30/min default), concurrency
  cap (3), per-request timeout (15 s), bounded retries (1), circuit breaker
  (OPEN after 5 consecutive failures, HALF_OPEN after 30 s).
- **Failure handling** (§14): every failure mode above surfaces as a typed error with
  `ok=False, data=None`. VAYRA never fabricates SAP data; consultant calls degrade
  gracefully (SAP failure never breaks a consult).

Security tests live in `backend/tests/test_sap_security.py` (§19): credential leakage,
prompt injection, malicious field content, unauthorized operation, write attempt,
destructive operation, excessive retrieval, audit bypass, permission escalation —
all must fail safely.

## 6. Configuration (environment variables)

| Variable | Default | Purpose |
|----------|---------|---------|
| `SAP_MODE` | `disabled` | `disabled` \| `mock` \| `odata` |
| `SAP_BASE_URL` | — | OData root, e.g. `https://sandbox.example.sap:44300` |
| `SAP_SYSTEM_ID` | — | Logical system id shown in status/UI |
| `SAP_CLIENT` | — | SAP client (e.g. `100`) |
| `SAP_USERNAME` / `SAP_PASSWORD` | — | Technical identity (Basic auth) |
| `SAP_API_TOKEN` | — | Bearer token alternative |
| `SAP_CAPABILITIES` | all 7 read caps | Comma list, parsed fail-closed |
| `SAP_ODATA_SERVICES` | — | Comma list of exposed OData service paths |
| `SAP_MAX_REQUESTS_PER_MINUTE` | `30` | Sliding-window limit |
| `SAP_MAX_CONCURRENT` | `3` | In-flight cap |
| `SAP_TIMEOUT_SECONDS` | `15` | Per-request timeout |
| `SAP_MAX_RETRIES` | `1` | Extra attempts for transient failures only |
| `SAP_AUDIT_LOG` | — | JSONL audit path |
| `SAP_AUDIT_USER` | `consultant-api` | Audit user for service-initiated reads |

Secrets must be provided through the deployment secret manager, never committed.

## 7. Authorization requirements for a real connection

1. A **dedicated read-only technical/service identity** in SAP (e.g. `VAYRA_RO`) —
   no dialog user, no write authorizations, no `S_RFC` execute on mutating BAPIs.
2. Authorizations limited to the enabled capability set (display-only on the relevant
   objects/services).
3. **Non-production system only** (sandbox/QA). Production is refused unconditionally.
4. Approved OData services allow-listed in `SAP_ODATA_SERVICES`.
5. Network path from the VAYRA host to the SAP gateway (HTTPS, allow-listed firewall).

## 8. Real SAP sandbox connection runbook (§17 — NOT YET EXECUTED)

> **Status: no sandbox has been connected.** No approved non-production SAP system
> was available during Phase 3, so §17 remains open. Everything below is the
> procedure to be executed by the team when a sandbox and a dedicated read-only
> identity are approved. **Do not connect to production under any circumstance.**

1. Obtain an approved **non-production** SAP system URL and a **read-only technical
   user** from the SAP Basis team (see §7 requirements).
2. Ask which OData services are exposed (e.g. `API_SALES_ORDER_SRV`); put them in
   `SAP_ODATA_SERVICES`.
3. Configure the environment:

   ```bash
   SAP_MODE=odata
   SAP_BASE_URL=https://<sandbox-host>:<port>
   SAP_SYSTEM_ID=<SID>
   SAP_CLIENT=<client>
   SAP_USERNAME=<VAYRA_RO>
   SAP_PASSWORD=<from-secret-store>
   SAP_ODATA_SERVICES=API_SALES_ORDER_SRV,API_MATERIAL_STOCK_SRV
   SAP_AUDIT_LOG=/secure/logs/sap-audit.jsonl
   ```

4. Start the backend and verify:
   `GET /api/v1/sap/status` → `"state": "READ_ONLY"`, expected capabilities, no secrets.
5. Run one approved read via `POST /api/v1/sap/read` and verify an audit event lands
   in the JSONL file with redacted content.
6. Run the mock test suite green again (`pytest -q`) and confirm the golden snapshot
   is unaffected; then run the consultant e2e and confirm `sap_observations` appear.
7. Record the sandbox results (endpoints reachable, latency, capability set detected)
   in this document.

## 9. Execution boundary (§18)

```
Consultant → Implementation Planner → Human Approval → Execution Layer
```

Unchanged. Implementation plans remain advisory-only with
`requires_human_approval` and `execution_supported: false` on every step. The SAP
connector introduced in this phase is read-only and cannot be invoked by a plan;
`ReadOnlyPolicy` denies any write/destructive/unknown operation name even if a future
adapter grew one.

## 10. Frontend (§15)

`SapStatusPanel` (consult page) polls `GET /api/v1/sap/status` every 60 s and shows:
state badge (`DISCONNECTED / CONNECTED / READ_ONLY / ERROR`), system id, SAP version,
read capabilities, last sync, last request status. Secrets are never displayed — the
endpoint cannot return them. When SAP is disconnected the panel renders nothing
(quiet default). Consult answers additionally list SAP observations with their
provenance labels (`SAP_OBSERVED`, …).

## 11. Known limitations

- **No RFC/BAPI adapter yet** — only OData (GET-only) and the mock.
- **The OData adapter has never faced a real SAP system** — tested over
  `httpx.MockTransport`; real systems may need CSRF/service-group handling.
- `read_table` is unsupported over OData (services only, by design).
- System info over OData is minimal (no component/product payload without an
  approved discovery service).
- Capability names cannot be extended without a reviewed change: parsing fails closed.
- SAP-side throttling patterns other than HTTP 429 are not recognized.
- Prompt-block delimiters are advisory to the model, not a sandbox; hostile field
  content is also bounded by JSON encoding, field caps and provenance labeling.
