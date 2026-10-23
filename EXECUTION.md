# VAYRA Controlled Execution (Phase 4)

Status: **implemented and tested against the SAP execution simulator** (§23). No real
SAP write connector exists yet — the executor seam is the simulator; a future
connector must implement the same three-call surface and would remain subject to
every policy layer below.

Core philosophy: **UNDERSTAND. PLAN. SIMULATE. APPROVE. EXECUTE. VERIFY.
ROLL BACK WHEN POSSIBLE. AUDIT.** And above all: **SAFETY > AUTONOMY.**

## 1. Architecture

```
USER
 ↓
VAYRA CONSULTANT (Phase 1: RAG → reasoning → ImplementationPlan)
 ↓
EXECUTION CONSOLE (/execution) + execution API
 ↓
ControlledExecutionEngine (backend/app/execution_engine/)
 ├─ validate_plan     — §15 layer 4 (plan contract, categories, ABAP gate §14)
 ├─ estimate_impact   — §9 structured impact analysis
 ├─ dry_run           — §8 report, provably no SAP state change
 ├─ request_approval  — §4 dossier + ApprovalStore (§5 plan-hash binding)
 ├─ execute_step      — §15 layers 1-5, then: snapshot → execute → verify (§6/§11)
 ├─ rollback_step     — §10 declared rollback, verified after
 ├─ get_status/cancel — §22 states / §2 cancel (never auto-rollback)
 └─ generate_audit_report — §17 hash-chained, tamper-evident
 ↓
SapExecutorProtocol (§23 simulator today; connector seam for tomorrow)
 ↓
VERIFICATION (deterministic state queries — never LLM-judged, §11)
 ↓
SUCCESS / ROLLBACK / INCIDENT REPORT (§18 failure protocol)
```

## 2. Execution levels (§3)

| Level | Name | Writes | Notes |
|-------|------|--------|-------|
| 0 | `READ_ONLY` | never | read-classification only |
| 1 | `DRY_RUN` (default) | never | simulation/reports only |
| 2 | `APPROVED_NON_PRODUCTION` | after explicit approval | two-person rule deferred to production |
| 3 | `CONTROLLED_PRODUCTION` | elevated approval | allow-listed systems, plan-hash validation, justification, second-person approval |
| 4 | `AUTONOMOUS` | **DISABLED** | architectural placeholder; construction and env-config both fail closed (§21) |

## 3. Approval (§4/§5)

The dossier shows: objective, target system + client, environment, affected modules,
affected objects, **exact operations**, expected impact, risks, prerequisites, rollback
strategy (including *unsupported* rollback counts — no false promises, §10), test plan,
verification plan and the plan hash. Decisions are explicit (`submit_approval_decision`),
never implicit; double decisions refuse; approvals expire (120 min default) and are bound
to the exact plan hash — **any** plan change after approval invalidates them (§5), and the
engine re-validates the hash before *every* step.

## 4. Step execution (§6/§7/§25/§18)

Steps run one at a time, in sequence, each followed by a deterministic verification
query. Sequence violations, duplicates (409 + idempotency ledger, §25), destructive and
UNCERTAIN classifications (§7), level violations, expired/invalid approvals, emergency
stop, rate limits and the circuit breaker all deny before anything is touched. On
failure: STOP, capture the error, verify SAP state, attempt declared rollback (verified
after), report an incident — remaining steps never run blindly (§18).

## 4b. Backpressure (§19)

Max 25 steps/run, per-step timeout (60 s), concurrency cap (2), **operation rate
limits** (sliding 60-s window, default 30 executions/min — the slot is acquired only by
calls that actually reach the executor, so denied requests never leak capacity), a
**circuit breaker** (opens after 5 consecutive execution failures — including steps that
wrote but failed verification; a verified success closes it; `reset_circuit_breaker`
after incident review re-opens the path, audited), and the global `EMERGENCY STOP`
latch (API + `EXECUTION_EMERGENCY_STOP` boot flag): engaging it denies all new writes,
refuses new approval requests, and demotes approved-but-unstarted runs to DENIED.

## 5. Security pipeline (§15) — every execution request

```
intent validation → authorization → policy validation
→ plan validation → approval validation → execution
```

§16 prompt-injection protection: plan fields and SAP data are DATA. Hostile text
("IGNORE ALL PREVIOUS INSTRUCTIONS…") cannot raise the level, skip approval, or forge a
write — verified by tests with hostile text in both plan fields and simulated SAP
payloads.

## 6. Audit (§17)

`ExecutionAuditLog` is append-only and hash-chained: each record carries the previous
record's SHA-256; editing, deleting or reordering records breaks the chain and
`verify_integrity()` detects it (§24 audit tampering). Secrets are value-replaced at
record time (`password`/`token`/`secret`/… keys → `[FILTERED]`) and long/complex values
bounded; `generate_audit_report(run_id)` returns the trail plus the §26 execution
summary.

## 7. Simulator + executor seam (§23)

`SAPExecutionSimulator` holds in-memory configuration/master-data/document objects and
implements the full write/read-back/snapshot/rollback surface, with failure injection:
authorization, timeout, verification mismatch, rollback failure, per-step failures,
partial failures. Tests for every §24 scenario run against it. A future SAP connector
implements `SapExecutorProtocol` (execute/verify/snapshot/rollback) and nothing else
changes.

## 8. API (12 routes, `/api/v1/execution/*`)

`GET status` · `POST plans` · `POST runs/{id}/dry-run` · `POST runs/{id}/impact` ·
`POST runs/{id}/approval` · `POST approvals/decision` · `POST steps` ·
`POST rollback` · `GET runs/{id}` · `POST runs/{id}/cancel` ·
`GET runs/{id}/audit` · `POST emergency-stop`.

Denials: 403 (policy/approval/stop), 409 (duplicates/sequence/state conflicts),
404 (unknown run), 422 (contract). The §22 states are surfaced verbatim:
`PLANNED DRY_RUN AWAITING_APPROVAL APPROVED EXECUTING VERIFYING SUCCESS FAILED
ROLLBACK_REQUIRED ROLLED_BACK CANCELLED DENIED`.

## 9. Frontend (/execution)

Execution console: engine banner (level, emergency-stop toggle, "Autonomous mode:
DISABLED (§21)"), plan editor with §15 validation, run state chip, dry-run table,
impact line, full approval dossier with explicit approve/reject, step-by-step
execution with verification results, and the audit trail with chain-integrity badge.

## 10. Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `EXECUTION_LEVEL` | `DRY_RUN` | §3 level; `AUTONOMOUS` raises (§21) |
| `EXECUTION_EMERGENCY_STOP` | unset | `1` → engine starts stopped |
| `EXECUTION_PRODUCTION_SYSTEMS` | unset | comma allow-list for level 3 |
| `EXECUTION_AUDIT_LOG` | unset | JSONL audit path |
| `EXECUTION_AUDIT_DIR` | unset | approval persistence dir |

## 11. Test results (real numbers, 2026-10-05)

| Suite | Result |
|-------|--------|
| `tests/test_execution_engine.py` — levels, classifier, approvals, §24 scenarios, §6 flow, §19 breaker, audit | **44 passed** |
| `tests/test_execution_api.py` — 12 endpoints, status-code mapping, emergency stop, audit | **12 passed** |
| Full backend suite (Phases 1–4) | **560 passed** (exit 0) |
| Eval runner / golden runner | 26/26 · 101/101 (exit 0, snapshot intact) |
| Frontend tsc · production build | clean · `/execution` route builds |
| Live HTTP smoke (full flow vs running backend) | register→dry-run→impact→approval→execute→verified→dup 409→audit chain ok |
| e2e consult | 4/4 (exit 0) |

§24 unsafe scenarios verified fail closed: approval bypass, modified approved plan,
unauthorized operation, destructive operation, production operation (level + allow-list +
two-person), rollback failure, verification failure, SAP timeout, partial execution,
duplicate execution, replay attack, prompt injection (plan fields + SAP data), emergency
stop, audit tampering, expired approval.

## 12. Known limitations

- The executor is the §23 simulator; no real SAP write connector exists (deliberate —
  Phase 3 built read-only only). Connecting one requires: an approved write-capable
  technical identity, the §3/§20 governance changes, and re-running the full §24 suite
  against a non-production system first.
- RBAC for the execution API endpoints is out of scope: identity is user-declared
  (`user`/`approver` fields), recorded in the audit chain, not cryptographically
  authenticated. Deployment-level SSO/rate-limiting must wrap the API.
- Approval persistence is JSONL (optional); multi-instance deployments require a shared
  store so the approval/idempotency ledgers are consistent across replicas.
- Snapshot capture is delegated to the executor's `capture_snapshot`; the simulator
  stores bounded non-sensitive fields.
- `AUTONOMOUS` exists only as the disabled placeholder the spec requires.
