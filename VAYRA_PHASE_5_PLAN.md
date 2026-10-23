# VAYRA Phase 5 Plan — Execution Reconciliation & Post-Run Verification

**Status:** COMPLETED · **Baseline:** Phase 1–4 audit `READY FOR PHASE 5` (566 tests, e2e 4/4, golden 101/101)

---

## 1. Selected objective and business value

**Objective:** Close the execution loop with a deterministic **Execution Reconciliation** layer: after a controlled run completes (or partially fails), VAYRA produces one evidence-grounded report that reconciles what was planned, what executed, what the verification engine confirmed, what the SAP object state actually changed (pre/post snapshot diff), which of the plan's own test-plan items are automatically verified versus still requiring manual validation, and the audit chain integrity.

**Business value:** today a completed run answers "did the steps succeed?" but not "did we achieve the planned outcome, and what still needs human testing?". A release manager closing an SAP change needs exactly that reconciliation before signing off — and needs it deterministically, never LLM-opinionated.

## 2. Gap addressed (evidence from the repository)

1. **`SnapshotRecord` is a dead model** (`execution_engine/models.py:273`) — defined in Phase 4, never instantiated anywhere.
2. **Per-step pre-execution snapshots are captured but never surfaced:** `execute_step` stores `run.snapshots_before` (added by the Phase 4 audit fix), but no API, report or UI exposes before/after state to a human.
3. **The plan's `testing_steps` are never reconciled:** `TestPlanItem` (test_id, category, expected_result, failure_condition) is validated into every plan, but nothing maps those items to execution outcomes after a run — the plan's own test contract silently disappears after approval.
4. **No post-run closure artifact:** `generate_audit_report` returns raw audit records; `ExecutionSummary` lists verification results; neither reconciles them into a sign-off-ready verdict.

## 3. Existing components reused (no rewrites)

- `ExecutionRun.snapshots_before` (per-step pre-execution state, Phase 4 audit fix).
- `SapExecutorProtocol.capture_snapshot()` — reused for the AFTER state at reconciliation time.
- `VerificationResult` / `run.verification_results` — deterministic per-step outcomes.
- `TestPlanItem` from the plan contract (`consultant_models.py`).
- `ExecutionAuditLog.verify_integrity()` / `audit_report()` — chain evidence.
- `redact` (Phase 3 credentials) — snapshots already filter sensitive keys; reconciliation redacts again at build time.
- Existing routes/service singleton (`get_execution_service`) — one new read-only route.

## 4. Architecture and workflow (preserves the mandated chain)

```
plan → impact → dry run → approval → EXECUTE → VERIFY → audit
                                                      ↓
                              RECONCILE (new, read-only, deterministic)
                              snapshots before/after → step diffs
                              plan testing_steps → verification mapping
                              audit chain integrity → verdict
```

The LLM plays **no role** in reconciliation. It is a pure deterministic computation over recorded engine state — the LLM still reasons and proposes, the planner still structures, the policy engine still authorizes, the execution engine still executes, the verification engine still verifies, the audit still records; reconciliation only **reads** those records and reports.

## 5. APIs, services, data models, UI

- **New module** `backend/app/execution_engine/reconciliation.py`:
  - `StepReconciliation`: step_id, sap_object, before/after snapshot (redacted), field diff (`added`/`removed`/`changed`), existence change, verification ok/actual.
  - `TestItemOutcome`: test_id, description, status ∈ `AUTOMATED_VERIFIED` | `NEEDS_MANUAL_VERIFICATION` | `BLOCKED_BY_FAILURE`, correlated_step (if any), correlation method (explicitly labelled `keyword-correlation` — a transparent heuristic, never a fabricated proof).
  - `ReconciliationReport`: run_id, run_state, verdict ∈ `RECONCILED` | `PARTIALLY_RECONCILED` | `NOT_RECONCILED` | `NOT_APPLICABLE` (nothing executed), steps, test_items, audit_integrity, remaining_issues, generated_at.
  - `ReconciliationEngine.build(run, executor, audit)` — pure function of recorded state.
- **Engine method:** `ControlledExecutionEngine.reconcile(run_id)` (denies unknown runs; read-only, audited as a RECONCILE event).
- **API route:** `GET /api/v1/execution/runs/{run_id}/reconciliation` (404 unknown run; no new authorization surface — read-only on an existing run).
- **Frontend:** new reconciliation section in `frontend/app/execution/page.tsx` — fetched when a run reaches a terminal state; shows verdict, per-step before/after diffs, test-item outcomes.

## 6. Security and authorization implications

- **No new write path.** Reconciliation only reads run/audit state and issues `capture_snapshot` (a read) through the existing executor protocol.
- Snapshots already exclude sensitive keys (`password/token/secret/key`); reconciliation applies `sap_redact` again defensively at report build.
- Audit records the RECONCILE event through the same hash-chained, redacted log.
- No LLM output is trusted: nothing in the report derives from model text.
- Read-only route inherits the desktop loopback trust model (documented Phase 1–4 limitation, unchanged).

## 7. Dependencies and external prerequisites

- **None new** — no new packages, no new services. Everything runs against the §23 simulator.
- Live SAP remains **BLOCKED** (unchanged): reconciliation against a real system requires the Phase 3/4 live connectors to exist first; documented as a limitation, never simulated as verified.

## 8. Measurable acceptance criteria

1. `ReconciliationEngine` produces a verdict for every run state, including NOT_APPLICABLE for runs with zero executed steps.
2. Field-level before/after diffs are exact for the simulator (added/changed/removed fields) and existence changes are reported.
3. Every plan `TestPlanItem` appears exactly once in the report with an explicit status; runs that failed mark all items `BLOCKED_BY_FAILURE`; successful runs correlate only on genuine keyword overlap with executed steps and label the correlation method.
4. Sensitive field names never appear with values in the report.
5. Unknown run → 404; the engine denies reconciliation of a run it does not know.
6. All existing Phase 1–4 tests, evaluations and builds remain green (no regressions).
7. Frontend renders the reconciliation section from the new endpoint without type errors.

## 9. Tests

- **Unit:** `backend/tests/test_execution_reconciliation.py` — verdict logic per state; exact diff semantics (create/update/rollback cases); test-item mapping (automated / manual / blocked); sensitive-key redaction; NOT_APPLICABLE path.
- **API contract:** route returns 200 with full report; 404 unknown run; report shape matches the documented schema.
- **Integration:** full flow (plan → dry run → approve → execute → reconcile) asserts AUTOMATED_VERIFIED correlation and RECONCILED verdict; failure flow asserts BLOCKED_BY_FAILURE and NOT_RECONCILED.
- **Regression:** full pytest suite, eval, golden, tsc, build (all must stay green).

## 10. Rollback strategy and known limitations

- **Rollback:** the feature is additive (one new module + one route + one engine method + one UI section). Removing the module/route/section restores the exact Phase 4 behavior; no existing schema or state machine changes.
- **Limitations (documented, honest):**
  - Keyword correlation between test items and steps is a transparent heuristic (`keyword-correlation`), not proof of business outcome; uncorrelated items are explicitly `NEEDS_MANUAL_VERIFICATION`.
  - AFTER snapshots are captured at reconciliation time, not the instant the step verified; concurrent out-of-band changes would appear in the diff (in a real system this is a feature — it surfaces drift).
  - Against the simulator only; live-SAP reconciliation is blocked until a real read-capable connector exists.
  - Reconciliation does not itself roll anything back — remediation stays behind the existing §10 approval-gated rollback path.

---

## 11. Implementation progress (final)

| Milestone | Status | Evidence |
|---|---|---|
| M1: `reconciliation.py` + unit tests | ✅ Done | [reconciliation.py](backend/app/execution_engine/reconciliation.py), 12 unit tests in `test_execution_reconciliation.py` |
| M2: `engine.reconcile()` + API route + API tests | ✅ Done | `engine.py:741`, `main.py:751` (`GET /api/v1/execution/runs/{run_id}/reconciliation`), route tests in `test_execution_api.py` |
| M3: frontend reconciliation section | ✅ Done | `frontend/app/execution/page.tsx` — verdict banner, per-step before/after diff cards, test-item statuses; `tsc --noEmit` 0 errors, `npm run build` success |

**Post-plan deviations (all improvements, documented):**
- Added `all_test_items_resolved_impl` static helper so the verdict path and report property share one source of truth.
- Color-coded `state_change_confirmed` surfaced per step in the UI (shows "verification ok but state unchanged" drift cases).

**Verification summary:** 580 pytest passed (Phase 4 baseline 566 + 14 new), 26/26 eval, 101/101 golden, e2e 4/4 (exit 0), tsc 0, build OK. Full detail in `VAYRA_PHASE_5_COMPLETION_REPORT.md`.
