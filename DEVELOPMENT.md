# Development Guide

## Prerequisites

- Python 3.12+ (backend/.venv already provisioned in this checkout)
- Node.js 18+ for the Next.js frontend
- Optional: Ollama (`ollama pull qwen3:14b`, `ollama pull bge-m3`) for a
  local LLM + embeddings; Qdrant (see `docker-compose.yml`) for server-mode
  vector search

## Local workflow

```bash
# Backend (from backend/)
cd backend
.venv\Scripts\python.exe -m uvicorn app.main:app --port 8000

# Frontend (from frontend/)
cd frontend
npm run dev -p 3000
```

Then:

- UI: http://localhost:3000 (Diagnostic console + Consultant page)
- API docs: http://localhost:8000/docs
- Health: `GET /health`, `GET /api/v1/llm/health`,
  `GET /api/v1/provider-status`, `GET /api/v1/knowledge/status`

## Common tasks

### Add a knowledge document
Create `backend/app/knowledge/data/<area>/<domain>/<topic>.md` with
front-matter (see SAP_KNOWLEDGE.md), then re-ingest. No code changes.

### Add a new SAP domain to routing
Extend `_FUNCTIONAL_KEYWORDS` or `_TECH_KEYWORDS` in
`backend/app/knowledge/intent.py`, add the domain to `DOMAIN_OPTIONS` in
`frontend/app/consult/page.tsx`, and (for chains) to
`backend/app/knowledge/cross_module.py`. Add an evaluation example.

### Add an LLM provider
Subclass `OpenAICompatibleLLMService` (if wire-compatible) or `LLMService`
in `backend/app/llm_service.py`; add a factory branch in `main.py::get_llm_service`
plus settings fields; cover it with a mock-transport test.

### Add an ABAP analyzer rule
Add the check in `backend/app/abap/analyzer.py` and positive/negative tests
in `tests/test_abap_analyzer.py`.

### Extend the consultant response
Update `ConsultantResponse` in `backend/app/consultant_models.py`, the
mapping in `consultant_orchestrator.py::_to_response`, the mirror types in
`frontend/lib/types.ts`, and the UI in `frontend/app/consult/page.tsx`.
Keep backend/frontend contracts synchronized (spec rule 15).

## Conventions

- Type hints everywhere; Pydantic for contracts; no global mutable state
  beyond the documented singletons (`get_retriever`, `get_vector_store`,
  `get_consultant_retriever`).
- Deterministic services (routers, analyzers, validators) are pure functions
  / stateless classes — unit-test them directly, no mocks needed.
- Retrieval and embedding I/O run in the threadpool (`run_in_threadpool`)
  so the async event loop never blocks.
- Tests must stay offline: use the `client`/`payload` fixtures and the
  autouse offline fixtures; mock provider HTTP with `httpx.MockTransport`.

## Definition of done for a change

1. `pytest tests/ -q` green (210+ tests).
2. `python -m app.evaluation.runner` — 21/21 examples pass.
3. `npx tsc --noEmit` clean when frontend types changed.
4. Docs updated when architecture or usage changed.
