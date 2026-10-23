# VAYRA — Phase 3 Report: Read-Only SAP Integration

**Date:** 2026-10-05 · **Phase:** 3 (Read-Only SAP Integration) · **Status:** implemented and fully tested against the mock environment. **No real SAP sandbox was connected** (§17 remains open — see §6).

Design document: [SAP_INTEGRATION.md](SAP_INTEGRATION.md) · Tests: `backend/tests/test_sap_*.py` (6 files, 177 tests)

---

## 1. SAP interfaces supported

| Interface | Status | Notes |
|-----------|--------|-------|
| **Mock adapter** (`MockSAPAdapter`) | Implemented | Deterministic canned data, failure injection (unavailable/timeout/malformed/authorization), write-rejection guard, hostile-field injection for security tests. All integration + security tests run against it. |
| **OData / SAP Gateway** (`ODataAdapter`) | Implemented, sandbox-untested | **GET-only** by construction (`_get` refuses any other method), OData v2 (`d.results`) + v4 (`value`) row parsing, dynamic capability detection, `read_table`/document/error/config reads refused without an approved service. Exercised over `httpx.MockTransport`. |
| RFC / BAPI reads | Designed, **not implemented** | The `SAPConnector` ABC is the seam; a future RFC adapter must declare `READ_ONLY = True` or the base class refuses it. |
| Middleware / other enterprise APIs | Future work | Same seam. |

Capabilities are detected dynamically per adapter (§3): nothing is assumed. The OData
adapter advertises `SAP_CONNECTION + READ_METADATA` always, `+ READ_TABLE` when services
are configured, `+ READ_DOCUMENT/READ_CONFIGURATION` only with more than one service.

## 2. Read capabilities

Exactly seven, all read-only. No WRITE capability exists anywhere in the codebase —
`SapCapability` cannot express one, and `parse_capabilities()` silently drops any name
starting with `WRITE/CREATE/POST/MODIFY/DELETE/TRANSPORT/EXECUTE` plus all unknown names
(fail-closed):

`SAP_CONNECTION · READ_METADATA · READ_CONFIGURATION · READ_DOCUMENT · READ_TABLE · READ_ERROR · READ_MASTER_DATA`

Effective authorization = *configured grant ∩ adapter-detected* — a configured
capability the connected system cannot serve is simply not verified.

## 3. Security model

- **Deny-by-default policy engine** between VAYRA and SAP (§6): every operation passes
  `OperationClassifier → permission check → ReadOnlyPolicy`. WRITE → DENY, DESTRUCTIVE →
  DENY, unclassifiable (UNKNOWN) → DENY, capability missing → DENY. Destructive stems
  (`delete/remove/drop/truncate/reset/purge/transport/import/mass_*`) are checked before
  write stems, so `delete_document` can never slip through a write-word collision.
- **Credentials** (§4): environment variables only. `SapCredentials` hides secrets in
  `repr`/`str`/`safe_config()`; `redact()` scrubs configured secret values plus
  `Bearer `/`Basic `/`password=`/`api_key=`/`sap-client=` patterns from every string that
  could reach a log, audit event, exception or prompt. The OData adapter redacts httpx
  error text before raising.
- **Normalization + minimization** (§7/§8): SAP responses go through
  Parser → Normalizer → Schema Validator → Sensitive-data Filter → Context Builder.
  Sensitive fields (`password, token, secret, iban, credit_card, ssn, salary, email, …`)
  are replaced with `[FILTERED]`; unknown fields are dropped entirely by the schemas;
  rows capped at 50, fields at 500 chars; truncation is surfaced as `PARTIAL`, never
  silently swallowed (this was a real bug found by the tests and fixed).
- **Prompt isolation** (§10/§19): every SAP-derived prompt block is wrapped in
  `[BEGIN SAP_DATA — …] … [END SAP_DATA]` untrusted-data delimiters and every claim in
  the answer carries a provenance label (`USER_PROVIDED / SAP_OBSERVED /
  KNOWLEDGE_VERIFIED / INFERRED / RECOMMENDED / UNVERIFIED`). Hostile SAP field content
  (deliberate injection fixtures in the mock) stays inside the data region — verified by
  tests.
- **Audit** (§12): every read *and every denial* is audited with timestamp, user,
  request id, SAP system, operation, object, purpose, result status, response
  classification and latency. JSONL file optional (`SAP_AUDIT_LOG`); redaction runs at
  record time; JSONL verified credential-free by test.
- **Backpressure** (§13): 30 req/min sliding window, concurrency 3, timeout 15 s,
  1 retry (transient failures only — authorization/invalid/malformed never retried),
  circuit breaker OPEN after 5 consecutive failures (verified: once OPEN, the adapter
  is not called again).
- **Failure handling** (§14): all nine failure modes map to typed
  `SapConnectorError` subclasses; results carry `ok=False, data=None` with a
  human-readable reason. Missing operation parameters are a typed
  `SapInvalidRequestError` (found by API tests — previously a raw `KeyError` that would
  have surfaced as HTTP 500). A failed consult-time SAP read never breaks consulting.
- **Execution boundary** (§18): unchanged — plans remain approval-gated and
  execution-unsupported; the SAP layer cannot be invoked by a plan and cannot write.

## 4. Authorization requirements (for a future real connection)

1. **Dedicated read-only technical/service identity** (no dialog user, no write
   authorizations, no execute on mutating BAPIs).
2. Authorizations scoped to exactly the enabled capability set (display-only).
3. **Non-production system only** — production is refused unconditionally.
4. OData services explicitly allow-listed via `SAP_ODATA_SERVICES`.
5. Network path allow-listed from the VAYRA host to the SAP gateway (HTTPS).

## 5. Mock test results (real numbers, this machine, 2026-10-05)

| Suite | Result |
|-------|--------|
| `test_sap_policy.py` — classifier, deny-by-default, capability parsing | **40 passed** |
| `test_sap_mock_adapter.py` — §16 success/failure/permission/write/destructive/READ_ONLY | **30 passed** |
| `test_sap_normalization.py` — pipeline stages, filtering, caps, delimiters | **34 passed** |
| `test_sap_service.py` — lifecycle, limits, breaker, retries, audit, diagnostics, OData | **35 passed** |
| `test_sap_security.py` — §19 leakage/injection/escalation/caps/audit integrity | **23 passed** |
| `test_sap_api.py` — endpoints, 403/429/503 mapping, consult SAP fields | **15 passed** |
| **Phase 3 total** | **177 passed** |
| Full backend suite (incl. Phases 1–2 regression) | **505 passed** (exit 0; baseline was 328) |
| Evaluation runner | **26/26** (exit 0) |
| Golden runner + snapshot | **101/101**, pass rate 100.0%, exit 0 (snapshot intact) |
| Frontend `tsc --noEmit` | clean (exit 0) |
| E2E consult (`scripts/e2e_consult.py`, backend on :8000, demo provider) | **4/4** (exit 0, 27.6 s) |
| `GET /api/v1/sap/status` on the live server (SAP_MODE unset) | `{"state":"DISCONNECTED","read_only":true,"mode":"disabled", …}` — no secrets |

Security scenarios verified to **fail safely** (§19): credential leakage (repr / safe
config / status / audit / JSONL), prompt injection from SAP data, malicious SAP text
fields, unauthorized operation, write attempt, destructive operation, excessive data
retrieval (5000-row flood → 50 rows + `PARTIAL`), audit bypass (denials audited too),
permission escalation (READ_METADATA-only identity denied everything else).

## 6. Sandbox test results

**Not connected. No approved non-production SAP sandbox was available during Phase 3,
so §17 could not be executed.** Per the spec, all tests were therefore run against the
mock environment first. [SAP_INTEGRATION.md §8](SAP_INTEGRATION.md) contains the
step-by-step sandbox runbook (identity requirements, env configuration, verification
steps) to be executed when the team provides an approved sandbox host and a dedicated
read-only technical identity. The `ODataAdapter` is ready but has never faced a real
SAP system.

## 7. Known limitations

1. **No RFC/BAPI adapter yet** — OData (GET-only) + mock only.
2. **OData adapter is sandbox-untested** — real gateways may need CSRF token handling,
   service-group discovery, or client-specific paths not covered by MockTransport tests.
3. `read_table` (generic table access) is unsupported over OData by design — reads ride
   exposed services only.
4. System info over OData is minimal (version reports `detected-at-connect`; component
   lists need an approved discovery service).
5. Capability names cannot be extended without a reviewed code change (parsing fails
   closed by design).
6. SAP-side throttling other than HTTP 429 is not recognized as rate limiting.
7. The `[BEGIN SAP_DATA]` delimiters are advisory to the model, not a sandbox — hostile
   field text cannot escape the block boundaries, but the literal marker text could
   appear inside a data value (mitigated by JSON encoding, field caps and provenance
   labels; documented in tests).
8. The audit JSONL file is local-only and unencrypted; place it on a secured path
   (`sap-audit*.jsonl` is gitignored).

## 8. Philosophy

OBSERVE SAP. UNDERSTAND SAP. VALIDATE SAP. **DO NOT MODIFY SAP.**
