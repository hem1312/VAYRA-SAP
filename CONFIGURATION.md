# Configuration

All configuration is environment-based. `backend/.env` (git-ignored) is the
runtime source of truth; the Settings PUT endpoint writes managed keys there.
See `backend/.env.example` for the full template.

## Core settings

| Variable | Default | Meaning |
|----------|---------|---------|
| `LLM_PROVIDER` | `demo` | `openai` \| `anthropic` \| `deepseek` \| `kimi` \| `ollama` \| `demo` |
| `OPENAI_TIMEOUT_SECONDS` | `45.0` | LLM call timeout (5–1,080,000 s); raise for slow local models |
| `CORS_ORIGINS` | `http://localhost:3000,…` | allowed browser origins |

## Provider settings

| Provider | Key variable | Model variable | Base URL variable |
|----------|--------------|----------------|-------------------|
| OpenAI | `OPENAI_API_KEY` | `OPENAI_MODEL` | `OPENAI_BASE_URL` |
| Anthropic | `ANTHROPIC_API_KEY` | `ANTHROPIC_MODEL` | `ANTHROPIC_BASE_URL` |
| DeepSeek | `DEEPSEEK_API_KEY` | `DEEPSEEK_MODEL` | `DEEPSEEK_BASE_URL` |
| Kimi | `KIMI_API_KEY` | `KIMI_MODEL` | `KIMI_BASE_URL` |
| Ollama | — (no key) | `OLLAMA_MODEL` | `OLLAMA_BASE_URL` |

## RAG settings

| Variable | Default | Meaning |
|----------|---------|---------|
| `QDRANT_URL` | `http://localhost:6333` | Qdrant server; local persistent store used when unreachable |
| `QDRANT_COLLECTION` | `sap_knowledge` | collection name |
| `EMBEDDING_MODEL` | `BAAI/bge-m3` | served by Ollama; offline fallback is automatic |

## Security rules

- Never commit `backend/.env` or real keys (`.gitignore` covers it).
- Keys entered in the Settings UI are written to the local `.env` and are
  never returned unmasked by the API (only `*_configured` / `*_masked`).
- Log lines pass a redaction filter (`app/logging_config.py`) as a second
  line of defense; request IDs are injected per request.
- VAYRA performs **no destructive SAP operations** — the platform is
  diagnostic/advisory; the SAP connector interface ships a mock only.

## Timeouts for local models

A CPU-bound local model (e.g. qwen3:14b on partial GPU offload) can take
many minutes per structured answer. Set `OPENAI_TIMEOUT_SECONDS=5400` (or
higher, up to 1,080,000) for such setups; the "Test connection" probe uses a
separate bounded 20 s timeout so it always returns promptly.
