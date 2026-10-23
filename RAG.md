# RAG — Retrieval-Augmented Generation

## Pipeline interfaces (Phase 1 spec §6)

Every retrieval stage is formalized as a swappable protocol in
`backend/app/rag/protocols.py` — **DocumentLoader**, **Chunker**,
**EmbeddingService**, **VectorStore**, **Retriever**, **Reranker**,
**ContextBuilder** — so no stage is coupled to one embedding model or vector
database. `backend/app/rag/pipeline.py` documents the shipped composition
and exposes `RAGPipeline` for one-line composition. The existing production
classes satisfy the protocols structurally — nothing was rewritten.

## Pipeline

```
Documents (data/**/*.json, data/**/*.md)
   ↓
Parser        JSON loader / Markdown+front-matter parser
   ↓
Chunker       JSON sections / Markdown headings
   ↓
Metadata      domain, module_type, verification, topic, content_hash
   ↓
Embeddings    OllamaEmbeddingService (BAAI/bge-m3 via /api/embed)
              fallback: fastembed multilingual-e5-large (1024-dim)
   ↓
Vector DB     Qdrant (server) or persistent local store
   ↓
Retriever     metadata-filtered semantic search + keyword layer
   ↓
Ranking       verification-aware (verified beats unverified at similar score)
   ↓
Context       bounded (char budget) evidence block for the LLM
```

## Embedding providers

| Provider | Model | Dim | Notes |
|----------|-------|-----|-------|
| Ollama | `BAAI/bge-m3` (served as `bge-m3`) | 1024 | default; `POST /api/embed` |
| fastembed fallback | `intfloat/multilingual-e5-large` | 1024 | offline, no Ollama needed |

`bge-m3` is served by Ollama, not fastembed; the factory in `embeddings.py`
routes it to `OllamaEmbeddingService` automatically. The vector dimension is
1024 for both, so collections are interchangeable.

## Vector database

Qdrant server first (`QDRANT_URL`, default `http://localhost:6333`), then a
persistent embedded local store at `backend/.qdrant_local/` (created
automatically). Collection: `sap_knowledge` (configurable via
`QDRANT_COLLECTION`). Point IDs are `uuid5(NAMESPACE_URL, "vayra-chunk/<chunk_id>")`
so re-ingestion overwrites the same points; the readable id stays in the
payload as `chunk_id`.

## Ingestion

```bash
cd backend
.venv\Scripts\python.exe -m app.knowledge.ingestion.ingest
```

- Loads legacy JSON runbooks **and** Markdown documents (front-matter metadata)
- Chunks Markdown by headings; keeps title context per chunk
- Stamps every chunk with a `content_hash`
- `run_ingestion(incremental=True)` embeds only new/changed documents
  (hash comparison against the store); `force=True` re-embeds everything
- HTTP equivalent: `POST /api/v1/knowledge/ingest` (full re-ingestion),
  status at `GET /api/v1/knowledge/status`

## Retrieval filters

The consultant retriever applies `module` (domain) filters when intent
confidence ≥ 0.55, and retries unfiltered when the filter returns nothing.
Verification state is part of ranking: verified evidence is preferred over
unverified at similar similarity. The deterministic keyword layer catches
exact T-code and dump-name mentions the embedding model may rank low.
