# Security

## Secrets

- All provider credentials come from environment variables / `backend/.env`
  (git-ignored). No key is ever hard-coded or committed.
- `GET /api/v1/settings` returns only masked keys and configured-flags;
  `PUT` writes managed keys to the local `.env` file.
- The log pipeline applies a redaction filter for `Bearer …`, `sk-…`,
  `x-api-key`, and `api_key=…` patterns (`app/logging_config.py`) as defense
  in depth alongside the "never log credentials" rule.

## Input handling

- Pydantic models validate and bound every request body
  (`ConsultantRequest.query` ≤ 20 000 chars; diagnostic fields bounded).
- No user input is ever passed to a shell or a file path — there is no
  shell execution anywhere in the runtime.
- File-upload support does not exist yet; the request schema leaves room
  for it so it can be added with explicit size limits later.

## Prompt-injection resistance

The LLM only ever sees: the validated user query, deterministic routing
metadata, **retrieved knowledge-base evidence**, and analyzer output. The
system prompt hard-requires evidence-grounding, forbids fabricating SAP
objects, and instructs the model to treat knowledge as the sole source for
configuration claims. The deterministic validators (`app/validation.py`)
then re-check the answer independently of the LLM:

- T-codes / SAP Notes / customer objects (`Z*`) are verified against the
  knowledge base; unsupported ones are flagged as unverified, never silently
  dropped or trusted
- configuration claims without configuration evidence are replaced by an
  explicit insufficiency notice
- confidence is recomputed from evidence, not taken from the model

## Scope of operations

VAYRA is **diagnostic and advisory only**:

- no write operations against any SAP system
- the `SAPSystemConnector` interface (`app/sap_connector.py`) documents the
  read-only contract and ships only a clearly-labeled mock; no live
  connector is implemented
- no destructive actions are reachable from any endpoint

## Logging & observability

Structured logs carry a per-request `X-Request-ID`; requests, routing
decisions, retrieval counts, validation warnings, and latencies are logged.
Confidential user content is not logged beyond request metadata.
