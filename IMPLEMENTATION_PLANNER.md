# VAYRA — Implementation Planner (Phase 1)

The Implementation Planner turns a validated consultant analysis into a
**machine-readable implementation plan**. It is the formal boundary between
VAYRA's reasoning layer and future SAP execution:

- every step carries `requires_human_approval = true`
- every step carries `execution_supported = false`
- VAYRA Phase 1 **never** connects to SAP, never performs write operations
  and never executes a plan — see `backend/app/execution.py` (§18) for the
  future execution seam (interface + mock only)

Core philosophy: DO NOT GUESS. RETRIEVE. REASON. VALIDATE. PLAN. VERIFY.

## Where it runs

```
ConsultantOrchestrator.consult()
    1-6  intent routing → retrieval → analyzers → dependencies → LLM → validation
    7    run_validation (layers 1-6)
    8    generate_implementation_plan()          ← this module
         run_plan_validation()                    ← layers 7-9 (plan/dependency/test plan)
    9    ConsultantResponse.implementation_plan
```

The planner (`backend/app/implementation_planner.py`) is deterministic and
LLM-free — pure functions over routing + dependency engine + validated
analysis, fully unit-testable and provider-independent.

## ImplementationPlan model (`consultant_models.py`)

| Field | Content |
|---|---|
| `plan_id` | `PLAN-<MODULE>-<response-id-prefix>`, traceable to the consultant response |
| `objective`, `business_requirement` | from the validated summary / stated requirement |
| `assumptions`, `prerequisites` | LLM assumptions + upstream dependency prerequisites |
| `affected_modules`, `affected_processes` | from routing + process-chain detection |
| `steps` | ordered `PlanStep` list (below) |
| `configuration_steps`, `development_steps`, `integration_steps` | step descriptions by category |
| `data_dependencies`, `authorization_dependencies`, `transport_dependencies` | from the risk rules for those categories |
| `testing_steps` | `TestPlanItem` list (7 categories, §13) |
| `validation_steps` | the analysis' verification steps |
| `rollback_strategy` | how to undo every planned change |
| `risks` | `RiskItem` list (8 categories, §14) |
| `impact_analysis` | affected modules/processes, upstream/downstream, integration points |
| `approval_required` | always `true` in Phase 1 |
| `execution_status` | `DRAFT` (missing information) / `AWAITING_APPROVAL` / `NOT_EXECUTED` |
| `missing_information` | targeted clarification questions (§16) |

### PlanStep fields (§11)

`step_id` (CFG-/DEV-/INT-001…), `sequence`, `category`
(configuration/development/integration/…), `description`, `SAP_object`,
`transaction_or_tool`, `prerequisite`, `expected_result`,
`verification_method`, `risk` (low/medium/high/critical — a word, never a
number), `requires_human_approval` (`true`), `execution_supported` (`false`).

**No fabrication (§9):** SAP objects and T-codes in steps are extracted from
the validated analysis/evidence only. If the analysis names no object, the
field stays empty.

## Risk analysis (§14)

Eight categories — configuration, data, integration, authorization,
performance, transport, regression, business-process — each with
`severity` (low/medium/high/critical), `probability`
(unlikely/possible/likely/very-likely), `mitigation`, `verification`.
There is **no numeric scoring**; a risk fires on textual signals or on
structural facts (a plan with customizing steps always carries configuration
risk; a cross-module chain always carries integration risk).

## Test plan (§13)

Every plan carries seven test categories: **unit, configuration,
integration, negative, authorization, regression, business** — each with a
description, an expected result and an explicit failure condition.

## Missing information (§16)

The router (`route_intent` → `missing_information`) and the planner
(`detect_missing_information`) emit targeted clarification questions instead
of guessing. A plan with missing critical information is generated as
`DRAFT` and lists the questions; the plan validator downgrades any
`AWAITING_APPROVAL` plan that still has missing information back to `DRAFT`.
Given values ("company code 1000") suppress their question; module-critical
topics (SD → company code + sales org, MM → company code + plant + purchasing
org, …) are asked even when the query does not mention them.

**Clarification round-trip:** the consultant console renders these questions
as an answerable form under the DRAFT plan. Answers travel back via
`ConsultantRequest.context.clarifications` (`{"<question text>": "<answer>"}`);
the orchestrator extends the LLM query with them and the planner drops the
answered questions — once nothing critical is missing, the regenerated plan
advances from `DRAFT` to `AWAITING_APPROVAL`.

## Validation layers (§15)

| # | Layer | Module |
|---|---|---|
| 1 | Input validation | pydantic `ConsultantRequest` |
| 2 | Intent validation | `route_intent` reliability flag |
| 3 | Retrieval validation | retriever min-score + fallback |
| 4 | Evidence validation | `EvidenceValidator.stamp` |
| 5 | Structured-output validation | pydantic `ConsultantResponse` |
| 6 | Claim validation | `SAPObjectValidator`, `ClaimValidator` |
| 7 | Implementation-plan validation | `PlanValidator` (approval/execution contract) |
| 8 | Dependency validation | `DependencyValidator` (engine-supported claims) |
| 9 | Test-plan validation | `TestPlanValidator` (coverage + conditions) |

## Mock execution interface (§18)

`backend/app/execution.py` defines the `ExecutionEngine` ABC
(`validate/execute/verify/rollback/get_status`) and `MockExecutionEngine` —
the only implementation. The mock validates plans against the advisory-only
contract (violations are reported, never executed), refuses execution by
design, and reports verification/rollback capability from the plan's own
data. A live engine is a future phase requiring explicit, audited
configuration.

## API + export

`POST /api/v1/consult` returns the plan inside
`ConsultantResponse.implementation_plan`. The consultant console exports it
as **JSON** (machine-readable, plan contract) and **Markdown**
(human review document with steps, risk table, test plan, rollback) —
see `frontend/lib/exportMarkdown.ts` (`exportPlanMarkdown`, `downloadJson`).

## Live end-to-end check

```powershell
cd backend
.venv\Scripts\python.exe ..\scripts\e2e_consult.py
```

Runs four consult scenarios against a running backend — SD diagnostic,
implementation request, clarification round-trip, ABAP review — asserts the
full plan contract (approval/execution flags, test coverage, risk shape) and
writes `scripts/e2e-consult-result.json`.
