# VAYRA — AI SAP Functional + Technical Consultant

Production-oriented platform for an AI-powered SAP consultant console: the
original error diagnostic pipeline plus a full multi-domain consultant.

## Structure

- `frontend/` — Next.js App Router UI with Tailwind CSS and a client-only React Three Fiber status visualization.
- `backend/` — FastAPI service with Pydantic contracts and an LLM provider abstraction.

## What VAYRA is

VAYRA is an AI-powered SAP consulting and automation platform. Every answer and
every change follows one explicit pipeline:

```text
Understand → Retrieve → Reason → Validate → Plan → Assess Impact → Dry Run
→ Human Approval → Execute → Verify → Rollback → Audit
```

Delivered in four phases:

| Phase | Scope |
| --- | --- |
| **Phase 1** | Consultant + RAG + implementation planning |
| **Phase 2** | Reliability, evaluation & hardening (golden evals, validation layers) |
| **Phase 3** | Read-only SAP integration (observation layer, no write path) |
| **Phase 4** | Controlled SAP execution & automation (simulator-backed, approval-gated) |

Division of responsibility: **the LLM is responsible for reasoning; it is not
responsible for authorization.** Every SAP read is gated by a deny-by-default
policy engine, and every state-changing SAP action requires policy validation,
an explicit plan-hash-bound human approval, step-level verification and a
hash-chained audit trail. Phase 4 executes against the built-in SAP execution
simulator — no real SAP write connector exists yet — and `AUTONOMOUS` execution
is a disabled placeholder that fails closed.

## Run locally (Windows)

### Desktop app (recommended)

The desktop app is a native window (WebView2) that launches both services itself — no browser involved:

```powershell
# first time only: installs dependencies and validates the build
.\setup.ps1

# launch the native desktop window
.\run-desktop.ps1

# or just double-click start-desktop.bat in File Explorer
```

A **SAP Diagnostic Agent** shortcut is also installed on the desktop (`scripts/make_shortcut.ps1` recreates it). Closing the window stops the managed services.

### Browser mode

```powershell
# start both services and open http://localhost:3000 in your default browser
.\run.ps1

# or just double-click start.bat in File Explorer
# stop everything with .\stop.ps1
```

Any modern browser works — Chrome, Edge, Firefox, or Brave. The console runs entirely on localhost; no cloud resources are needed.

### Manual setup (any OS)

```bash
# backend
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000

# frontend (separate terminal)
cd frontend
npm install
npm run dev
```

```bash
# stop both services
.\stop.ps1
```

Copy `backend/.env.example` to `backend/.env` and provide credentials only through environment variables. The default backend uses a deterministic demo provider until an LLM adapter is configured.

---

## VAYRA — local LLM + SAP RAG diagnostic pipeline

VAYRA extends the diagnostic console with a fully local, free pipeline:

```text
SAP error input → error normalization → SAP knowledge retrieval (Qdrant + bge-m3)
                → local LLM reasoning (Qwen3-14B via Ollama) → deterministic validation
                → structured DiagnosticResponse (VERIFIED / UNVERIFIED evidence)
```

The existing providers (`demo`, `openai`, `anthropic`, `deepseek`, `kimi`, `ollama`) all remain selectable; the RAG + validation layer wraps whichever provider is active. The demo provider always works offline.

### 1. Install Ollama (Windows)

Download the installer from <https://ollama.com/download> (or `winget install Ollama.Ollama`). It runs as a background service on `http://localhost:11434`. Verify with `ollama --version`.

### 2. Pull the models

```powershell
ollama pull qwen3:14b   # local reasoning LLM (~9.3 GB)
ollama pull bge-m3      # embedding model used for retrieval (~1.2 GB)
```

`bge-m3` is the SAP-RAG embedding model. fastembed (the Python fallback embedded in the backend) cannot serve BGE-M3, so the real weights are served by the local Ollama runtime; when Ollama is unreachable the backend falls back to a 1024-dim multilingual fastembed model — re-ingest after switching embedding backends.

> **Hardware note:** Qwen3-14B needs ~10 GB of memory (VRAM or system RAM). Without sufficient GPU VRAM it runs CPU-bound at roughly 2 tokens/s — a diagnosis can then take 10–20 minutes (one cold model load of several minutes + generation). For interactive development on modest hardware, pull a smaller model (`ollama pull qwen3:8b`, or reuse an already-installed one) and set `OLLAMA_MODEL=qwen3:8b` in `backend/.env` or via Settings. The Settings probe distinguishes "Ollama is not running", "model not installed", and "model loading/answering slowly". A ready-made end-to-end check with a long timeout is included:
>
> ```powershell
> cd backend
> .venv\Scripts\python.exe ..\scripts\e2e_diagnostic.py   # writes ..\scripts\e2e-result.json
> ```

### 3. Start Qdrant (optional)

```powershell
docker compose up -d    # starts Qdrant on http://localhost:6333 (data in a named volume)
```

This is optional: if no Qdrant server answers, the backend automatically uses a persistent local store in `backend/.qdrant_local/` (git-ignored), so development works with zero extra services.

### 4. Configure the provider

Either edit `backend/.env`:

```env
LLM_PROVIDER=ollama
OLLAMA_MODEL=qwen3:14b
OLLAMA_BASE_URL=http://localhost:11434/v1
QDRANT_URL=http://localhost:6333
QDRANT_COLLECTION=sap_knowledge
EMBEDDING_MODEL=BAAI/bge-m3
```

…or use the in-app **Settings** page (provider dropdown, model, base URL, Test Connection). Ollama needs no API key. The Settings probe reports precisely what is wrong: `Ollama is not running. Start it…`, or `Model 'qwen3:14b' is not installed. Run: ollama pull qwen3:14b`.

### 5. Ingest the SAP knowledge base

```powershell
cd backend
.venv\Scripts\python.exe -m app.knowledge.ingestion.ingest
```

This chunks every JSON knowledge item under `backend/app/knowledge/data/` (SD/MM/FI + verified T-code catalog), embeds the chunks with `bge-m3`, and upserts them into Qdrant (idempotent — safe to re-run). Equivalently: `POST /api/v1/knowledge/ingest`, with `GET /api/v1/knowledge/status` reporting chunk count and store mode.

**Adding knowledge:** drop a JSON file into `backend/app/knowledge/data/<module>/` with fields `id, module, category, error_code, title, description, possible_causes, configuration, tcodes, resolution, validation, references, provenance` — then re-ingest. Never invent SAP Notes/OSS notes or T-codes; mark unverified references as such in `references`/`provenance`.

### 6. Run and diagnose

Start backend + frontend (above), enter an error such as `VF032 — account determination while creating billing document in VF01`, and run the diagnostic. Retrieval prefers exact error-code matches over semantic similarity, merges both, and grounds the LLM prompt in the retrieved evidence only.

**Knowledge safety (hallucination control):** the deterministic validator checks every T-code, evidence reference, and configuration claim against the retrieved knowledge base. Unsupported claims are flagged in the UI's *Validation warnings* section, evidence is stamped `VERIFIED`/`UNVERIFIED`, and confidence is capped when evidence is weak (0.4 with no evidence, 0.75 with semantic-only evidence). When evidence is missing the response states: *"Insufficient verified SAP knowledge was retrieved to confirm this configuration step."* The pipeline never fabricates SAP Notes, OSS notes, T-codes, or SPRO paths.

### Environment variables (VAYRA-specific)

| Variable | Default | Purpose |
| --- | --- | --- |
| `LLM_PROVIDER` | `demo` | `ollama` selects the local runtime |
| `OLLAMA_MODEL` | `qwen3:14b` | local model tag |
| `OLLAMA_BASE_URL` | `http://localhost:11434/v1` | Ollama's OpenAI-compatible endpoint |
| `QDRANT_URL` | `http://localhost:6333` | vector DB (local fallback if unreachable) |
| `QDRANT_COLLECTION` | `sap_knowledge` | collection name |
| `EMBEDDING_MODEL` | `BAAI/bge-m3` | served by Ollama (`bge-m3`) or fastembed fallback |

---

## VAYRA Consultant platform (functional + technical)

Beyond error diagnosis, VAYRA answers free-form SAP consulting requests:

```text
free-form request (question / error / ABAP code / ST22 dump)
    → SAP Intent Router (intent: DIAGNOSTIC | CONFIGURATION | IMPLEMENTATION |
      PERFORMANCE | INTEGRATION | …; persona: FUNCTIONAL | TECHNICAL | ABAP |
      CROSS_MODULE | IMPLEMENTATION_PLANNER; 13 functional + 17 technical
      domains, 18 problem types, missing-information detection)
    → ConsultantRetriever (metadata-filtered RAG over functional/technical/
      integration/cross_module knowledge, verification-aware ranking,
      swappable RAG protocols)
    → deterministic analyzers (ABAPAnalyzer, ST22Parser, dependency engine)
    → shared LLM reasoning with per-mode prompts (AUTO/FUNCTIONAL/TECHNICAL/
      ABAP/CROSS_MODULE/IMPLEMENTATION_PLANNER)
    → deterministic validation + evidence-aware confidence (9 validation layers)
    → Implementation Planner (machine-readable plan: steps, risks, test plan,
      impact analysis, rollback — approval required, execution not supported)
    → structured ConsultantResponse
```

Use the **Consultant** page in the UI (or `POST /api/v1/consult` with
`{"query": "...", "mode": "AUTO", "module": "", "system": ""}`). The response
includes `implementation_plan` (exportable as JSON/Markdown from the UI).
The legacy `POST /api/v1/diagnostics` error pipeline is unchanged and fully
preserved. The execution seam (`backend/app/execution.py`) is interface + mock only.

### SAP integration (Phase 3 — read-only observation layer)

VAYRA can now *observe* a SAP system through a strictly read-only connector layer:
deny-by-default policy engine, capability gating, GET-only OData adapter + mock
adapter, normalization with sensitive-data filtering, audit logging and rate
limiting. There is **no write path** — SAP data enters answers as provenance-tagged
observations (`SAP_OBSERVED`, …) inside untrusted-data delimiters. No sandbox is
connected yet; the mock adapter backs all tests. See
[SAP_INTEGRATION.md](SAP_INTEGRATION.md) for architecture, configuration and the
sandbox connection runbook.

### Controlled execution (Phase 4)

VAYRA can *propose and drive* controlled SAP changes — under a fail-closed pipeline:
plan validation → impact analysis → dry run → explicit plan-hash-bound human approval
→ step-by-step execution with deterministic verification → declared rollback →
hash-chained audit. Execution levels gate everything (`READ_ONLY`/`DRY_RUN` default/
`APPROVED_NON_PRODUCTION`/`CONTROLLED_PRODUCTION`); `AUTONOMOUS` exists only as a
disabled placeholder and fails closed (§21). The executor is the §23 SAP execution
simulator — no real SAP write connector exists yet. The **Execution** console page
drives the whole flow. See [EXECUTION.md](EXECUTION.md).

### Documentation

| Document | Content |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | runtime architecture, request flow, module map |
| [IMPLEMENTATION_PLANNER.md](IMPLEMENTATION_PLANNER.md) | plan model, risk/test-plan generation, missing-info gating, execution boundary |
| [RAG.md](RAG.md) | embeddings, Qdrant modes, ingestion, retrieval filters, RAG protocols |
| [SAP_KNOWLEDGE.md](SAP_KNOWLEDGE.md) | knowledge tree, metadata schema, verification states, how to add knowledge |
| [ABAP_ANALYSIS.md](ABAP_ANALYSIS.md) | ABAP analyzer rules, ST22 parsing, debugging workflow |
| [CONFIGURATION.md](CONFIGURATION.md) | all environment variables, provider setup, security rules |
| [SAP_INTEGRATION.md](SAP_INTEGRATION.md) | Phase 3 read-only SAP layer: architecture, capabilities, security model, sandbox runbook |
| [EXECUTION.md](EXECUTION.md) | Phase 4 controlled execution: levels, approval, step engine, simulator, audit |
| [TESTING.md](TESTING.md) | test suites, offline guarantees, how to add tests |
| [DEVELOPMENT.md](DEVELOPMENT.md) | local workflow, common tasks, conventions |
| [SECURITY.md](SECURITY.md) | secrets, input handling, injection resistance, scope |

### Consultant tests & evaluation

```powershell
cd backend
.venv\Scripts\python.exe -m pytest tests/ -q          # full suite
.venv\Scripts\python.exe -m app.evaluation.runner      # 26-example SAP eval set
```

The evaluation set covers SD/MM/FI/CO/PP/QM/PM/EWM, ABAP/ST22/CDS/RAP/IDoc/OData,
authorization, cross-module chains, implementation/configuration planning,
general questions, and a negative fabricated-SAP-Note probe that must yield
UNVERIFIED — never a note number.
